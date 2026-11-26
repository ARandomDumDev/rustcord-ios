import AuthenticationServices
import CryptoKit
import Security
import UIKit

/// Opens Discord's hosted authorization page. The app never receives account passwords.
enum OAuth {
    static let redirect = "rustcord://oauth"

    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
    private static let anchor = Anchor()
    @MainActor private static var activeSession: ASWebAuthenticationSession?

    @MainActor
    static func signIn(clientId: String) async throws -> String {
        guard !clientId.isEmpty else {
            throw RustcordError(error: "Enter your Discord application ID.")
        }
        let state = UUID().uuidString
        let verifier = try codeVerifier()
        var c = URLComponents(string: "https://discord.com/oauth2/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: "identify guilds"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: codeChallenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "rustcord") { url, err in
                Task { @MainActor in
                    Self.activeSession = nil
                    guard let url else {
                        cont.resume(throwing: err ?? RustcordError(error: "Discord sign-in was cancelled."))
                        return
                    }
                    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          parts.queryItems?.first(where: { $0.name == "state" })?.value == state else {
                        cont.resume(throwing: RustcordError(error: "OAuth state validation failed."))
                        return
                    }
                    guard let code = parts.queryItems?.first(where: { $0.name == "code" })?.value else {
                        cont.resume(throwing: RustcordError(error: "Discord did not return an authorization code."))
                        return
                    }
                    do {
                        cont.resume(returning: try await exchange(code: code, verifier: verifier,
                                                                  clientId: clientId, redirect: redirect))
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            session.presentationContextProvider = anchor
            Self.activeSession = session
            session.start()
        }
    }

    private static func codeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw RustcordError(error: "Could not generate secure OAuth verifier.")
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func exchange(code: String, verifier: String, clientId: String,
                                 redirect: String) async throws -> String {
        var form = URLComponents()
        form.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "code_verifier", value: verifier),
        ]
        var request = URLRequest(url: URL(string: "https://discord.com/api/v10/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error_description"]
            throw RustcordError(error: detail ?? "Discord token exchange failed.")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data).access_token
        return "Bearer " + token
    }

    private struct TokenResponse: Decodable {
        let access_token: String
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
