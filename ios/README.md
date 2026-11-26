# iOS front end (SwiftUI)

Native SwiftUI UI over the Rust core: `LazyVStack` rows, newest 100 messages kept per channel,
text-only rows, network/JSON off the main thread.

## Build with GitHub Actions (no Mac needed)
`.github/workflows/ios.yml` runs on macOS: builds the Rust static libs, generates `rustcord.h` with
cbindgen, generates the Xcode project from `ios/project.yml` (xcodegen), builds for the simulator and
uploads an **unsigned** `.ipa` artifact. To install on a device, sign it (e.g. with your Apple ID via
Sideloadly/AltStore).

## Signing in
- **Bot setup:** create an application in the [Discord Developer Portal](https://discord.com/developers/applications),
  create/reset its bot token, and enable **Message Content Intent** under Bot → Privileged Gateway Intents.
  Enter the application ID to generate an invite link with View Channels, Read Message History, and Send
  Messages permissions. Invite the bot to your server, then enter its token in the app. Keep the token secret.
- **Server chat:** after bot sign-in, choose a server and a text/announcement channel the bot can access.
  It can load recent messages, receive live message events, and send messages.
- **Bot DMs:** choose **Open a DM by user ID** to open a one-to-one conversation with the bot. This does
  not expose the signed-in user's existing DM inbox. Discord's bot API does not provide bots access to
  group DMs.
- **Sign in with Discord** (OAuth2): enter your Discord application ID. In Developer Portal → OAuth2
  → Redirects, register the exact URI `rustcord://oauth`. The app uses the authorization-code flow
  with PKCE. Discord OAuth grants identity and server-list access only; personal-account chat is not
  available through this client.
- **Bot token**: full chat (read/send/live events). Enable the "Message Content" intent.
- The app never asks for Discord email/password credentials; Discord handles sign-in in its own web
  authorization page.
