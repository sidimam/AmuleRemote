# Changelog

All notable changes to aMule Remote. The same notes appear in the [GitHub Releases](https://github.com/sidimam/AmuleRemote/releases), in the App Store "What's New" of every platform, in the [wiki → Features](https://github.com/sidimam/AmuleRemote/wiki/Features) and in the [Homebrew tap](https://github.com/sidimam/homebrew-tap).

## 1.4.1 (build 21) — 2026-09-11

Same feature set as 1.4, republished on every platform with the fixes found on a real Apple TV. A new version number was needed because Apple had already approved 1.4 (build 19) on Apple TV and Apple Vision Pro before the fixed build could replace it; build 20 was never published on the stores.

- **Apple TV: iCloud sync now actually works** — the tvOS builds of 1.3 and 1.4 (build 19) were archived without code signing and therefore shipped **without the iCloud Key-Value Storage and keychain entitlements**: the walkthrough could never find a backup and *Sync profiles with iCloud* did nothing. The tvOS archive is now signed with the App Store profile at archive time and the entitlements are verified before upload.
- **Walkthrough: more patient iCloud backup search** on every platform — iCloud delivers the Key-Value store asynchronously after a first install or a reinstall; the search now waits up to about 30 seconds, reacts to the store's change notification and offers **Search again** with a hint about using the same iCloud account.
- **Apple TV: App color picker** shows each option with a dot of its own color (they were drawn in the text color).
- **Walkthrough presentation** deferred by one run-loop turn, so it cannot be dropped at launch when data is already present in the Keychain or on iCloud (reinstall).

## 1.4 (build 19) — 2026-09-11

### New
- **Guided introduction (walkthrough)** on every platform (iPhone/iPad, Mac, Apple Vision Pro, Apple TV): features, quick actions of the platform, demo mode, then an **iCloud sync** page and a **notifications** page. Replayable from *About → Show the introduction again*.
- **iCloud backup restore** from the walkthrough: an existing backup of the server profiles (one for all platforms) is found and restored on the new device, passwords included (iCloud Keychain).
- **Notifications without in-app toggles**: a single *Notifications ›* row asks the system consent or opens the system Settings (immediate or Scheduled Summary on iOS). Alerts: download started, download completed, server unreachable / reachable again, connection lost, eD2k / Kad drops and reconnections.
- **App color**: the former *Icon color* now tints buttons, links, toggles and the selected tab on every platform, Apple TV included (own picker); the icon still changes on iPhone, iPad and Vision Pro, the Dock icon on the Mac.
- **Shortcuts and Siri** on iOS/iPadOS, macOS (Mac App Store build), visionOS and tvOS, with new actions: download / upload speed, queue count, status / pause / resume / priority of a single download, remove completed, add one or more eD2k links, search, eD2k connect / disconnect, Kad start / stop. Six App Shortcuts out of the box.
- **Clipboard**: the *Add eD2k link* sheet extracts several `ed2k://` links from any pasted text, with a native **Paste** button; on the Mac it pre-fills from the clipboard and the Dock / Transfers menus gain *Add links from the Clipboard* (⇧⌘L). **Share eD2k link** from a download's context menu and from the selection bar.

### Fixes and changes
- **Apple TV keyboard**: typing with the Siri Remote or the iPhone *Apple TV Keyboard* no longer replaces the previous character or bounces the cursor (native text fields for host, port, password, link and search; the search bar became a field with a *Search* button).
- **Apple TV legibility**: the action buttons at the top of Transfers and Servers keep a readable label with the tinted look.
- Notification checks now run on fixed intervals: every 5 minutes in the foreground, about every 15 minutes in the background on iOS.
- 124 new localized strings in English, Italian, Spanish, French, German, Simplified Chinese and Arabic.
- Known limitation: the Developer ID DMG / Homebrew build is compiled with SwiftPM, which does not export App Intents metadata, so the Shortcuts actions on the Mac are available in the Mac App Store build.

## 1.3 (build 18) — 2026-09-09

### New
- **Offline mode with local cache**: after the idle period (*Go offline after inactivity*) or when the app goes to the background the connection is closed, the last data stays on screen under an *Offline* banner and the connection resumes by itself (tap, foreground, *Reconnect*, launch).
- **iCloud sync of server profiles** (opt-in): profiles via iCloud Key-Value Storage, passwords via the iCloud Keychain; *Restore N profiles from iCloud* on a new device. The DMG ships with an iCloud provisioning profile.
- **Quick actions**: app-icon menu on iPhone/iPad; Dock menu and *Transfers* menu (⌘L, ⌥⌘P, ⌥⌘R) on the Mac.
- **Apple TV app** (tvOS 17+): transfers, search, servers, statistics and settings for the Siri Remote.
- **About section** everywhere with the MIT license, wiki, *Report a problem*, source and privacy links; Mac *About* panel and Help menu.
- The project is released under the **MIT License**.

### Fixes and changes
- The "Disconnected for inactivity" bounce to the login screen is gone.
- Returning from the background no longer triggers a "Server stopped" error.
- 45 new localized strings.

## 1.2 (build 17) — 2026-09-08

- **Notifications redesigned**: master switch with permission request and test notification, toggles for completed downloads, eD2k/Kad disconnections and checks while disconnected, configurable interval; background checks on iOS.
- **Apple Vision Pro** app.
- **7 app icon colors** (light/dark/tinted) on iPhone, iPad and Vision Pro, matching Dock icon on the Mac.
- Mac app aligned with iOS/iPad (toolbars, action bar, layouts, settings rows).
- Transfers: single ✓ button with *Select* and *Remove completed*.
- Show/hide password in every password field.
- Fixes: Mac theme stuck in dark mode; searches that did not start on the first try.
- English README, wiki and store listing; more countries.

## 1.1 (build 16) — 2026-09-08

- Light / dark / system theme.
- 7 languages (English, Italian, Spanish, French, German, Simplified Chinese, Arabic with RTL layout) with an in-app selector.
- Server profiles with a default profile and quick switching.
- Face ID / Touch ID lock.
- Apple Watch app.
- Siri and Shortcuts (iOS): status, pause / resume downloads, add eD2k link.
- Clickable `ed2k://` links from Safari, Mail and other apps.
- Adaptive icon (dark and tinted variants).

## 1.0 (builds up to 15)

- First releases: transfers (queue, pause / resume / stop / delete, priority, categories, eD2k links), local and global search with filters, servers (list, connect, `server.met` update, eD2k / Kad controls), shared files and the remote `amule.conf` editor on the Mac, statistics and server log, connection test on iOS, demo mode, Keychain storage.
- From build 15 the macOS app in the Releases is Developer ID signed and notarized; Homebrew cask `sidimam/tap/amule-remote`.
