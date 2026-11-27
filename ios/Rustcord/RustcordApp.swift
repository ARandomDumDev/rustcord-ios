import SwiftUI
import ImageIO
import UIKit

/// Keeps only the newest `limit` messages per open channel, so memory stays flat.
@MainActor
final class Store: ObservableObject {
    static let maxHistory = 500
    @Published var guilds: [Guild] = []
    @Published var channels: [Channel] = []
    @Published var messages: [Message] = []
    @Published var error: String?
    @Published var isOAuthAccount = false
    @Published var canLoadOlderMessages = false
    @Published var isLoadingOlderMessages = false
    var api: Discord?
    var openChannel: String?
    private let pageSize = 50

    func login(_ token: String, isOAuth: Bool = false) async {
        let d = Discord(token: token)
        do {
            _ = try await d.me()
            api = d
            isOAuthAccount = isOAuth
            guilds = try await d.guilds()
            if !isOAuth {
                d.listen { [weak self] m in
                    Task { @MainActor in self?.receive(m) }
                }
            }
        } catch { self.error = "\(error)" }
    }

    func loginWithDiscord(clientId: String) async {
        do { await login(try await OAuth.signIn(clientId: clientId), isOAuth: true) }
        catch { self.error = "\(error)" }
    }

    func openGuild(_ g: Guild) async {
        guard let api else {
            error = "Sign in with a bot token first."
            return
        }
        do {
            channels = try await api.channels(g.id).filter { [0, 5, 10, 11, 12].contains($0.type) }
            error = nil
        } catch { self.error = "\(error)" }
    }

    func open(_ c: Channel) async {
        guard let api else {
            error = "Sign in with a bot token first."
            return
        }
        openChannel = c.id
        do {
            let page = try await api.messages(c.id)
            messages = Array(page.reversed())
            canLoadOlderMessages = page.count == pageSize
            error = nil
        } catch { self.error = "\(error)" }
    }

    func loadOlderMessages() async {
        guard let api, let channel = openChannel, let cursor = messages.first?.id,
              canLoadOlderMessages, !isLoadingOlderMessages else { return }
        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        do {
            let page = try await api.messages(channel, before: cursor)
            let existing = Set(messages.map(\.id))
            let older = page.reversed().filter { !existing.contains($0.id) }
            messages.insert(contentsOf: older, at: 0)
            if messages.count > Self.maxHistory {
                messages.removeLast(messages.count - Self.maxHistory)
            }
            canLoadOlderMessages = page.count == pageSize
            error = nil
        } catch { self.error = "\(error)" }
    }

    func send(_ text: String) async {
        guard let api, let c = openChannel, !text.isEmpty else { return }
        do {
            _ = try await api.send(c, text)
            error = nil
        } catch { self.error = "\(error)" }
    }

    func createDM(recipientID: String) async throws -> Channel {
        guard let api else { throw RustcordError(error: "Sign in with a bot token first.") }
        return try await api.createDM(recipientID: recipientID)
    }

    private func receive(_ m: Message) {
        guard m.channel_id == openChannel, !messages.contains(where: { $0.id == m.id }) else { return }
        messages.append(m)
        if messages.count > Self.maxHistory {
            messages.removeFirst(messages.count - Self.maxHistory)
        }
    }
}

@main
struct RustcordApp: App {
    @StateObject private var store = Store()
    @State private var token = ""
    @State private var clientId = ""

    var body: some Scene {
        WindowGroup {
            if store.api == nil {
                Form {
                    Section("1. Create and configure a bot") {
                        Link("Open Discord Developer Portal",
                             destination: URL(string: "https://discord.com/developers/applications")!)
                        Text("Create an application, open its Bot page, and reset/copy the bot token. Under Bot → Privileged Gateway Intents, enable Message Content Intent.")
                    }
                    Section("2. Invite the bot to your server") {
                        TextField("Discord application ID", text: $clientId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let url = botInviteURL {
                            Link("Generate bot invite", destination: url)
                        }
                        Text("Grant View Channels, Read Message History, and Send Messages. The bot must share the server and have channel access.")
                    }
                    Section("3. Connect") {
                        SecureField("Bot token", text: $token)
                        Button("Connect bot") { Task { await store.login(token) } }
                    }
                    Section("Personal Discord account") {
                        Button("Sign in with Discord") {
                            Task { await store.loginWithDiscord(clientId: clientId) }
                        }
                        Text("In the Discord Developer Portal, register this exact OAuth redirect URI: \(OAuth.redirect). Discord opens its own sign-in page; this app never receives your password. Personal accounts can view their profile and server list, but cannot use personal-account chat here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let e = store.error { Text(e).foregroundStyle(.red) }
                }
            } else {
                Group {
                    if store.isOAuthAccount {
                        PersonalAccountView()
                    } else {
                        RootView()
                    }
                }
                .environmentObject(store)
            }
        }
    }

    private var botInviteURL: URL? {
        guard !clientId.isEmpty else { return nil }
        var components = URLComponents(string: "https://discord.com/oauth2/authorize")
        components?.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "scope", value: "bot"),
            .init(name: "permissions", value: "68608"),
        ]
        return components?.url
    }
}

struct PersonalAccountView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List(store.guilds) { guild in
                Text(guild.name)
            }
            .navigationTitle("Your servers")
            .safeAreaInset(edge: .bottom) {
                Text("Signed in with Discord. Personal-account chat is not available to third-party apps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.bar)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                Section("Servers") {
                    ForEach(store.guilds) { g in
                        NavigationLink(g.name) { ChannelList(guild: g) }
                    }
                }
                Section("Direct messages") {
                    NavigationLink("Open a DM by user ID") { DirectMessageStartView() }
                    Text("Bots cannot list your personal DM inbox or access group DMs. Start a bot DM with a user ID instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Discord")
        }
    }
}

struct DirectMessageStartView: View {
    @EnvironmentObject var store: Store
    @State private var recipientID = ""
    @State private var openedChannel: Channel?
    @State private var error: String?
    @State private var isOpening = false

    var body: some View {
        Form {
            TextField("Recipient's Discord user ID", text: $recipientID)
                .keyboardType(.numberPad)
            Text("This opens a one-to-one DM with the bot. The recipient must be reachable by the bot; existing personal-account DMs and group chats are not available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(isOpening ? "Opening…" : "Open DM") {
                Task {
                    isOpening = true
                    defer { isOpening = false }
                    do {
                        openedChannel = try await store.createDM(recipientID: recipientID)
                        error = nil
                    } catch { self.error = "\(error)" }
                }
            }
            .disabled(recipientID.isEmpty || isOpening)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Start a DM")
        .navigationDestination(item: $openedChannel) { ChatView(channel: $0) }
    }
}

struct ChannelList: View {
    @EnvironmentObject var store: Store
    let guild: Guild

    var body: some View {
        List {
            if let error = store.error {
                Text(error).foregroundStyle(.red)
            }
            ForEach(store.channels) { c in
                NavigationLink("# \(c.name ?? "channel")") { ChatView(channel: c) }
            }
        }
        .navigationTitle(guild.name)
        .task { await store.openGuild(guild) }
    }
}

struct ChatView: View {
    @EnvironmentObject var store: Store
    let channel: Channel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if store.canLoadOlderMessages {
                            Button {
                                let anchor = store.messages.first?.id
                                Task {
                                    await store.loadOlderMessages()
                                    await Task.yield()
                                    if let anchor {
                                        proxy.scrollTo(anchor, anchor: .top)
                                    }
                                }
                            } label: {
                                HStack {
                                    if store.isLoadingOlderMessages { ProgressView() }
                                    Text(store.isLoadingOlderMessages ? "Loading…" : "Load older messages")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .disabled(store.isLoadingOlderMessages)
                        }
                        ForEach(store.messages) { m in
                            Row(message: m).id(m.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.messages.last?.id) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            HStack {
                TextField("Message", text: $draft).textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button("Send", action: submit)
            }
            .padding(8)
        }
        .navigationTitle(channel.type == 1 ? "Direct Message" : "# \(channel.name ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.open(channel) }
    }

    private func submit() {
        let t = draft
        draft = ""
        Task { await store.send(t) }
    }
}

private enum ImageMemoryCache {
    static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
}

private struct CachedRemoteImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = nil
            failed = false
            guard let url else {
                failed = true
                return
            }
            if let cached = ImageMemoryCache.images.object(forKey: url as NSURL) {
                image = cached
                return
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1200,
                            kCGImageSourceShouldCache: false,
                        ] as CFDictionary
                      ) else {
                    failed = true
                    return
                }
                let decoded = UIImage(cgImage: thumbnail)
                ImageMemoryCache.images.setObject(
                    decoded,
                    forKey: url as NSURL,
                    cost: thumbnail.width * thumbnail.height * 4
                )
                image = decoded
            } catch {
                failed = true
            }
        }
    }
}

struct Row: View, Equatable {
    let message: Message
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let url = message.author.avatarURL {
                    CachedRemoteImage(url: url)
                } else {
                    Text(String(message.author.username.prefix(1)).uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .background(.quaternary)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(message.author.username).font(.caption.bold()).foregroundStyle(.secondary)
                if !message.content.isEmpty {
                    Text(message.content).textSelection(.enabled)
                }
                ForEach(message.imageAttachments) { attachment in
                    CachedRemoteImage(url: attachment.url)
                        .frame(maxWidth: 420, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel(attachment.filename)
                }
                ForEach((message.attachments ?? []).filter { !$0.isImage }) { attachment in
                    Link(attachment.filename, destination: attachment.url)
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
