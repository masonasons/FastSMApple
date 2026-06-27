# FastSM for Apple platforms

A native Apple port of [FastSM](https://github.com/masonasons/FastSM) — a fast,
accessible Mastodon/Bluesky client built with blind users in mind. This is a
ground-up rewrite of the Python/wxPython app in Swift, sharing one core between
two native front ends:

- **macOS** — native **AppKit** (`NSTableView`) for the strongest VoiceOver and
  keyboard-first list navigation.
- **iOS** — **SwiftUI**.
- **FastSMCore** — a shared Swift framework: models, networking, auth,
  account/timeline management, post caching, and earcons.

## Status — Milestone 1 (vertical slice)

Working end-to-end on both platforms:

- Add accounts: **Mastodon** (browser OAuth via `ASWebAuthenticationSession`) and
  **Bluesky** (handle + app password).
- Home timeline with keyboard navigation (macOS) / swipe actions (iOS) and rich
  VoiceOver labels.
- Compose posts and replies; **boost** and **favorite** (with optimistic UI).
- Fast startup via an on-disk **post cache** (capped, debounced, off-main).
- Tokens persist in the Keychain across launches.

See `docs`/the project plan for the deferred feature list (notifications,
profiles, media upload, soundpacks, streaming, AI image descriptions, lists,
polls, filters, …).

## Project layout

```
FastSM.xcodeproj          Hand-written project (4 targets, FS-synchronized groups)
FastSMCore/               Shared framework (iOS + macOS)
  Models/                 Status, User, Notification, Media, Card/Poll, Platform
  Platform/               SocialAccount protocol + Mastodon & Bluesky impls
  Auth/                   OAuthSession (ASWebAuthenticationSession wrapper)
  Networking/             URLSession HTTP helpers
  Store/                  Keychain, AppConfig, AccountStore
  Timeline/               TimelineController + TimelineCache
  Sound/                  SoundManager (earcons)
  Presentation/           StatusPresenter (display + VoiceOver labels)
  Util/                   HTMLStripper, RelativeDate, DateParsing
macOS/                    AppKit app
iOS/                      SwiftUI app
Tests/FastSMCoreTests/    Mapping + HTML-stripping unit tests
```

## Building

Requires Xcode 16+ (developed against Xcode 26.5 / Swift 6.3). Open
`FastSM.xcodeproj` and pick a scheme, or from the command line:

```bash
# Run the core unit tests
xcodebuild test -scheme FastSMCore -destination 'platform=macOS'

# Build the macOS app
xcodebuild build -scheme FastSM-macOS -destination 'platform=macOS'

# Build the iOS app
xcodebuild build -scheme FastSM-iOS -destination 'generic/platform=iOS Simulator'
```

The apps register the `fastsm://` URL scheme for the Mastodon OAuth redirect
(`fastsm://oauth`). The macOS target ships sandboxed with the network-client
entitlement; both targets ad-hoc sign for local builds (set a Development Team in
the target settings for distribution).

### Bluesky app passwords

Bluesky sign-in uses an **app password**, not your main password — create one in
Bluesky → Settings → App Passwords.
