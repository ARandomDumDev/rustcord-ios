import Foundation

struct User: Codable, Hashable {
    let id: String
    let username: String
    let avatar: String?

    var avatarURL: URL? {
        guard let avatar else { return nil }
        let ext = avatar.hasPrefix("a_") ? "gif" : "png"
        return URL(string: "https://cdn.discordapp.com/avatars/\(id)/\(avatar).\(ext)?size=64")
    }
}
struct Guild: Codable, Identifiable, Hashable { let id: String; let name: String }
struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let type: Int
    let name: String?
}
struct MessageAttachment: Codable, Identifiable, Hashable {
    let id: String
    let filename: String
    let url: URL
    let content_type: String?

    var isImage: Bool {
        if content_type?.lowercased().hasPrefix("image/") == true { return true }
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "avif"]
            .contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
    }
}
struct Message: Codable, Identifiable, Hashable {
    let id: String
    let channel_id: String
    let author: User
    let content: String
    let attachments: [MessageAttachment]?

    var imageAttachments: [MessageAttachment] { (attachments ?? []).filter(\.isImage) }
}

struct RustcordError: Error, Decodable { let error: String }

/// Thin wrapper over the Rust C ABI. Blocking calls run on a background queue.
final class Discord: @unchecked Sendable {
    private let client: OpaquePointer
    let token: String
    private let queue = DispatchQueue(label: "rustcord.io", qos: .userInitiated, attributes: .concurrent)

    init(token: String) {
        self.token = token
        client = rustcord_client_new(token)!
    }
    deinit { rustcord_client_free(client) }

    private func call<T: Decodable>(_ f: @escaping (OpaquePointer) -> UnsafeMutablePointer<CChar>?) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let p = f(self.client) else { return cont.resume(throwing: RustcordError(error: "null")) }
                defer { rustcord_free_string(p) }
                let data = Data(bytes: p, count: strlen(p))
                if let e = try? JSONDecoder().decode(RustcordError.self, from: data) { return cont.resume(throwing: e) }
                do { cont.resume(returning: try JSONDecoder().decode(T.self, from: data)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func me() async throws -> User { try await call { rustcord_current_user($0) } }
    func guilds() async throws -> [Guild] { try await call { rustcord_guilds($0) } }
    func channels(_ g: String) async throws -> [Channel] { try await call { rustcord_guild_channels($0, g) } }
    func createDM(recipientID: String) async throws -> Channel {
        try await call { rustcord_create_dm($0, recipientID) }
    }
    func messages(_ c: String) async throws -> [Message] { try await call { rustcord_messages($0, c, 50) } }
    func messages(_ c: String, before: String) async throws -> [Message] {
        try await call { rustcord_messages_before($0, c, before, 50) }
    }
    func send(_ c: String, _ text: String) async throws -> Message { try await call { rustcord_send_message($0, c, text) } }

    /// Gateway events are delivered on a Rust thread; only MESSAGE_CREATE is decoded.
    func listen(_ onMessage: @escaping @Sendable (Message) -> Void) {
        final class Box { let f: @Sendable (Message) -> Void; init(_ f: @escaping @Sendable (Message) -> Void) { self.f = f } }
        let box = Unmanaged.passRetained(Box(onMessage)).toOpaque()
        rustcord_gateway_start(token, { ud, name, json in
            guard let ud, let name, let json, strcmp(name, "MESSAGE_CREATE") == 0 else { return }
            let data = Data(bytes: json, count: strlen(json))
            guard let m = try? JSONDecoder().decode(Message.self, from: data) else { return }
            Unmanaged<Box>.fromOpaque(ud).takeUnretainedValue().f(m)
        }, box)
    }
}
