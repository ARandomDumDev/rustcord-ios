# iOS front end (SwiftUI)

Native SwiftUI UI over the Rust core: `LazyVStack` rows, newest 100 messages kept per channel,
text-only rows, network/JSON off the main thread.

## Build with GitHub Actions (no Mac needed)
`.github/workflows/ios.yml` runs on macOS: builds the Rust static libs, generates `rustcord.h` with
cbindgen, generates the Xcode project from `ios/project.yml` (xcodegen), builds for the simulator and
uploads an **unsigned** `.ipa` artifact. To install on a device, sign it (e.g. with your Apple ID via
Sideloadly/AltStore).

## Signing in
- **Sign in with Discord** (OAuth2): enter your Discord application ID. In Developer Portal → OAuth2
  → Redirects, register the exact URI `rustcord://oauth`. The app uses the authorization-code flow
  with PKCE. Discord OAuth grants identity and server-list access only; personal-account chat is not
  available through this client.
- **Bot token**: full chat (read/send/live events). Enable the "Message Content" intent.
- The app never asks for Discord email/password credentials; Discord handles sign-in in its own web
  authorization page.
