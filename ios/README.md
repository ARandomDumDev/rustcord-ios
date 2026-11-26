# iOS front end (SwiftUI)

Native SwiftUI UI over the Rust core: `LazyVStack` rows, newest 100 messages kept per channel,
text-only rows, network/JSON off the main thread.

## Build with GitHub Actions (no Mac needed)
`.github/workflows/ios.yml` runs on macOS: builds the Rust static libs, generates `rustcord.h` with
cbindgen, generates the Xcode project from `ios/project.yml` (xcodegen), builds for the simulator and
uploads an **unsigned** `.ipa` artifact. To install on a device, sign it (e.g. with your Apple ID via
Sideloadly/AltStore). The workflow has not been run yet.

## Signing in
- **Sign in with Discord** (OAuth2): set `OAuth.clientId` in `Rustcord/OAuth.swift` and add `rustcord://oauth`
  as a redirect URI in the Discord developer portal. Discord only grants OAuth user tokens identity and
  server-list access (`identify guilds`), so chat is not available this way.
- **Bot token**: full chat (read/send/live events). Enable the "Message Content" intent.
- Logging in with a regular user account token is deliberately not supported: Discord prohibits it
  (self-botting) and it risks account bans.
