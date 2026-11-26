import AuthenticationServices
import UIKit

/// "Sign in with Discord" via OAuth2 implicit grant (opens Discord's own login page,
/// so the app never sees the user's password). Set `clientId` to your application's ID and add
/// `rustcord://oauth` as a redirect URI in the Discord developer portal.
///
/// Discord's API gives OAuth user tokens identity and server-list access only; reading or sending
/// messages as a user is not permitted for third-party apps, so that requires a bot token.
enum OAuth {
    static let clientId = "YOUR_DISCORD_APPLICATION_ID"
    static let redirect = "rustcord://oauth"

    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
    private static let anchor = Anchor()

    @MainActor
    static func signIn() async throws -> String {
        var c = URLComponents(string: "https://discord.com/oauth2/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "response_type", value: "token"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: "identify guilds"),
        ]
        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "rustcord") { url, err in
                guard let url, let frag = url.fragment else {
                    return cont.resume(throwing: err ?? RustcordError(error: "cancelled"))
                }
                var comps = URLComponents()
                comps.query = frag
                if let t = comps.queryItems?.first(where: { $0.name == "access_token" })?.value {
                    cont.resume(returning: "Bearer " + t)
                } else {
                    cont.resume(throwing: RustcordError(error: "no token"))
                }
            }
            session.presentationContextProvider = anchor
            session.start()
        }
    }
}
