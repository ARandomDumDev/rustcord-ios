import SwiftUI

/// Keeps only the newest `limit` messages per open channel, so memory stays flat.
@MainActor
final class Store: ObservableObject {
    static let limit = 100
    @Published var guilds: [Guild] = []
    @Published var channels: [Channel] = []
    @Published var messages: [Message] = []
    @Published var error: String?
    @Published var isOAuthAccount = false
    var api: Discord?
    var openChannel: String?

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
        } catch { error = "\(error)" }
    }

    func open(_ c: Channel) async {
        guard let api else {
            error = "Sign in with a bot token first."
            return
        }
        openChannel = c.id
        do {
            messages = Array(try await api.messages(c.id).reversed())
            error = nil
        } catch { error = "\(error)" }
    }

    func send(_ text: String) async {
        guard let api, let c = openChannel, !text.isEmpty else { return }
        do {
            _ = try await api.send(c, text)
            error = nil
        } catch { error = "\(error)" }
    }

    func createDM(recipientID: String) async throws -> Channel {
        guard let api else { throw RustcordError(error: "Sign in with a bot token first.") }
        return try await api.createDM(recipientID: recipientID)
    }

    private func receive(_ m: Message) {
        guard m.channel_id == openChannel, !messages.contains(where: { $0.id == m.id }) else { return }
        messages.append(m)
        if messages.count > Self.limit { messages.removeFirst(messages.count - Self.limit) }
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
                    } catch { error = "\(error)" }
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

/// Plain text only: no avatars or embeds, which keeps rendering cheap and memory low.
struct Row: View, Equatable {
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.author.username).font(.caption.bold()).foregroundStyle(.secondary)
            Text(message.content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
