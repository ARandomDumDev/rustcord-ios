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

    func loginWithDiscord() async {
        do { await login(try await OAuth.signIn(clientId: OAuth.clientId), isOAuth: true) }
        catch { self.error = "\(error)" }
    }

    func openGuild(_ g: Guild) async {
        channels = ((try? await api?.channels(g.id)) ?? []).filter { $0.type == 0 }
    }

    func open(_ c: Channel) async {
        openChannel = c.id
        messages = ((try? await api?.messages(c.id)) ?? []).reversed()
    }

    func send(_ text: String) async {
        guard let c = openChannel, !text.isEmpty else { return }
        _ = try? await api?.send(c, text)
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

    var body: some Scene {
        WindowGroup {
            if store.api == nil {
                Form {
                    Section("Personal Discord account") {
                        Button("Sign in with Discord") {
                            Task { await store.loginWithDiscord() }
                        }
                        Text("Configure DISCORD_CLIENT_ID as a GitHub Actions variable and register discord-<application ID>:/authorize/callback in the Discord Developer Portal. Discord opens its own sign-in page; this app never receives your password. Personal accounts can view their profile and server list, but cannot use personal-account chat here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("Bot account") {
                    SecureField("Or bot token", text: $token)
                    Button("Sign in") { Task { await store.login(token) } }
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
            List(store.guilds) { g in
                NavigationLink(g.name) { ChannelList(guild: g) }
            }
            .navigationTitle("Servers")
        }
    }
}

struct ChannelList: View {
    @EnvironmentObject var store: Store
    let guild: Guild

    var body: some View {
        List(store.channels) { c in
            NavigationLink("# \(c.name ?? "")") { ChatView(channel: c) }
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
        .navigationTitle("# \(channel.name ?? "")")
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
