# aMule Remote

Native **macOS, iOS, iPadOS, visionOS and tvOS** app (SwiftUI, with an **Apple Watch** companion) to remotely control an **amuled** server — for example the aMule container on your Unraid box, a NAS or a Raspberry Pi — over the **EC (External Connections)** protocol, the same one used by aMuleGUI and amulecmd. EC protocol 0x0204, compatible with aMule 2.3.x.

> 📖 Detailed guides in the **[Wiki](https://github.com/sidimam/AmuleRemote/wiki)** · 🔒 [Privacy policy](https://sidimam.github.io/AmuleRemote/)

<p align="center">
  <a href="https://github.com/sidimam/AmuleRemote/releases/latest/download/aMuleRemote-macOS.dmg">
    <img src="https://img.shields.io/badge/macOS-Download_the_DMG_(latest)-0071e3?style=for-the-badge&logo=apple&logoColor=white" alt="Download the macOS DMG" height="44">
  </a>
  &nbsp;&nbsp;
  <a href="https://apps.apple.com/app/amule-remote/id6800020841">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download on the App Store (iPhone, iPad, Mac, Apple Vision Pro, Apple TV)" height="44">
  </a>
</p>
<p align="center">
  <a href="https://github.com/sidimam/AmuleRemote/releases/latest">
    <img src="https://img.shields.io/github/v/release/sidimam/AmuleRemote?label=latest%20release&style=flat-square" alt="Latest release">
  </a>
  &nbsp;
  <a href="https://github.com/sidimam/homebrew-tap">
    <img src="https://img.shields.io/badge/Homebrew-sidimam%2Ftap%2Famule--remote-fbb040?style=flat-square&logo=homebrew&logoColor=white" alt="Homebrew cask">
  </a>
  &nbsp;
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  </a>
</p>

## Download

- **iPhone / iPad**: **[App Store](https://apps.apple.com/app/amule-remote/id6800020841)** (free). The Apple Watch app is bundled. You can also build it yourself with Xcode (see *Building*).
- **Mac**, three options:
  - **DMG** — download **`aMuleRemote-macOS.dmg`** from the latest **[Release](https://github.com/sidimam/AmuleRemote/releases/latest)**, open it and drag **aMule Remote** onto the **Applications** folder next to it. The app is signed with a **Developer ID** and **notarized by Apple**: it opens right away, with no Gatekeeper warnings and no keychain prompts. *(A `.zip` with the same app is attached to every release too.)*
  - **Homebrew** — `brew install --cask sidimam/tap/amule-remote` (same notarized DMG, updated with `brew upgrade`). Cask source: [sidimam/homebrew-tap](https://github.com/sidimam/homebrew-tap).
  - **Mac App Store** — the sandboxed build lives on the [same App Store page](https://apps.apple.com/app/amule-remote/id6800020841) as the iOS app (universal purchase).
- **Apple Vision Pro**: on the App Store in the countries where Vision Pro is sold.
- **Apple TV** *(1.3)*: on the App Store (same universal purchase), for tvOS 17 or later.

## Features

### New in 1.4 / 1.4.1 (build 21)

> 1.4.1 (build 21) replaces 1.4 on every platform, same day: it fixes the Apple TV build, which shipped without the iCloud entitlements (sync and backup restore never worked on tvOS), makes the walkthrough's iCloud backup search more patient with a *Search again* button, and draws real color dots in the Apple TV color picker. See [CHANGELOG.md](CHANGELOG.md).

- **Guided introduction (walkthrough)** on every platform — iPhone, iPad, Mac, Apple Vision Pro and Apple TV — at the first launch after the update: what the app does, transfers and search, server profiles and Offline mode, the platform's quick actions, the demo mode, then **iCloud sync** and **notifications**. It can be replayed at any time from *About → Show the introduction again*.
- **iCloud backup restore from the walkthrough** — the app looks for an existing backup in your iCloud account and offers to restore the server profiles (and their passwords, via the iCloud Keychain) on the new device. The backup is **one for all your platforms**: iPhone, iPad, Mac (DMG, Homebrew and Mac App Store), Vision Pro and Apple TV. Skipped it? You can turn sync on later from the app settings.
- **Notifications, simplified** — no more toggles inside the app: the walkthrough (or the single **Notifications ›** row in the settings) asks for the system consent, and from then on you decide *how* to receive them in the system Settings (on iPhone/iPad also in the *Scheduled Summary*). The app sends every useful alert: **download started**, **download completed**, **aMule server unreachable / reachable again**, **connection to the server lost**, **eD2k and Kad drops and reconnections** (drops only when the server's auto-reconnect is off). Checks run every 5 minutes in the foreground and about every 15 minutes in the background on iOS.
- **App color** — the icon color setting is now called *App color* and also tints buttons, links, toggles and the selected tab on **every** platform (Apple TV included, which gets its own color picker); the icon still changes on iPhone, iPad and Vision Pro, plus the Dock icon on the Mac.
- **Shortcuts and Siri everywhere** — the App Intents now ship on iOS/iPadOS, macOS (Mac App Store build; the SwiftPM-built DMG cannot export them), visionOS and tvOS: aMule status, **download / upload speed** and **queue count** as numbers, **status / pause / resume / priority of a single download** (by name), remove completed, **add one or more eD2k links**, **search** (returns the result names), connect / disconnect the eD2k server, start / stop Kad. Six ready-made App Shortcuts appear in the Shortcuts app.
- **Clipboard integration** — the *Add link* sheet accepts several `ed2k://` links at once (one per line, or any text that contains them, e.g. a page copied from a browser or a Notes entry) with a native **Paste** button; on the Mac the sheet pre-fills from the clipboard and the Dock menu gets *Add links from the Clipboard*. Downloads can be **shared** as eD2k links (context menu and selection bar) to Notes, Messages, Mail or any other app.
- **Apple TV keyboard fixed** — typing with the Siri Remote or the iPhone "Apple TV Keyboard" no longer replaces the previous character or makes the cursor jump: the connection form and the search field use a native text field that commits the text only when editing ends.
- **iPhone Duo** — layouts are adaptive (no fixed frames) and were checked on iPhone, iPad and every simulator available in Xcode 26.6; no dedicated iPhone Duo simulator exists yet, so nothing device-specific was added.

### New in 1.3 (build 18)

- **Offline mode with local cache** — after the chosen idle period (or when the app goes to the background) the connection is closed, but the last data stays on screen with an *Offline · data updated at HH:MM* banner; the connection **resumes by itself** at the first tap/click, when the app returns to the foreground or when it is reopened (the cached snapshot appears instantly while reconnecting). No more "Disconnected for inactivity" bounce to the login screen. The setting is now called **"Go offline after inactivity"** and works on the Mac too (off by default there).
- **iCloud sync of server profiles** *(opt-in)* — profiles are shared between your devices through iCloud Key-Value Storage and their passwords through the **iCloud Keychain**; a new device offers to *Restore N profiles from iCloud* on the connection screen. Works on every build: iPhone, iPad, Mac (DMG/Homebrew and Mac App Store), Vision Pro and Apple TV — the Developer ID DMG ships with an iCloud provisioning profile.
- **Quick actions** — long-press the app icon on iPhone/iPad (Add eD2k link, Pause all, Resume all, Search); on the Mac the same actions live in the **Dock menu** and in a new **Transfers** menu with shortcuts (⌘L, ⌥⌘P, ⌥⌘R). visionOS and tvOS have no icon menu: Siri and Shortcuts remain available there.
- **Apple TV app** — new `AmuleRemoteTV` target designed for the remote and the big screen: large rows, every row is a button that opens an action sheet, Play/Pause on the Siri Remote pauses/resumes the highlighted download, native tvOS search bar (dictation and the iPhone "Apple TV Keyboard" work out of the box), single-column connection screen, iCloud profile restore so you never type on the TV.
- **About section** on every platform (More → About, Settings ⌘, About panel, TV Settings): version, author, **MIT license** text, links to the **wiki**, **report a problem** (pre-filled GitHub issue), source code and privacy policy. The Mac Help menu links to the same pages.
- **Project license**: the repository is now under the [MIT License](LICENSE); GitHub issue templates added.

- **Transfers**: download queue with progress, speed, sources, ETA, status and **download age** (days in queue); pause / resume / stop / delete; priority (low/normal/high/auto); category assignment; add `ed2k://` links; multi-selection with an action bar; "Remove completed"; active uploads panel (Mac).
- **Search**: **local** and **global (server)**, tabbed (several searches at once), with filters (file type, extension, min/max size, availability) and an automatic 120 s timeout. Double-click / tap a result to download it. Results already in your transfers are highlighted in **red**, files you already downloaded in **green**.
- **Servers**: server list with users/files/ping, connect (double-click / tap), disconnect, add, remove, update the list from a `server.met` URL; **eD2k** and **Kad** network controls.
- **Shared files** *(Mac)*: list with requests/uploads, share priority, reload shared folders, copy ed2k link.
- **Statistics** and the server **log** in real time; **connection test** (EC port and optional web server) on iOS.
- **aMule preferences** *(Mac)*: the full remote `amule.conf` editor — General, Connection, Servers, Files, Security, Message filters, Tweaks (core + Kademlia), Remote control (web server).
- **Server profiles**: several named amuled servers, one **default** proposed at launch, quick switching; passwords always in the Keychain.
- **Notifications** *(reworked in 1.4)*: consent asked by the walkthrough or by the **Notifications ›** row, everything else is decided in the system Settings (immediate or Scheduled Summary on iOS). Alerts for **download started / completed**, **server unreachable / reachable again**, **connection lost**, **eD2k / Kad drops and reconnections** (drops only when the server's auto-reconnect is off). Checks every 5 minutes in the foreground and about every 15 minutes in the background on iOS (Background App Refresh). Notifications also reach Apple Watch.
- **Appearance**: light / dark / system theme; **7 app colors** *(1.2, extended in 1.4)* that tint the whole interface on every platform and change the icon on iPhone, iPad and Vision Pro (with dark and tinted variants) plus the Dock icon on the Mac.
- **Face ID / Touch ID lock** (optional) and **offline after inactivity** (configurable, with cached data and automatic reconnection) on every platform.
- **Apple Watch app**: speeds, eD2k/Kad status and the download queue, mirrored from the iPhone.
- **Apple TV app** *(1.3)*: transfers, search, servers, statistics and settings on the big screen, driven by the Siri Remote (typing from the iPhone keyboard fixed in 1.4).
- **iCloud sync** *(1.3, optional)*: server profiles and passwords shared between your devices.
- **Quick actions** *(1.3)*: app-icon menu on iPhone/iPad, Dock menu and Transfers menu on the Mac; **clipboard** paste of several eD2k links and **share** of eD2k links *(1.4)*.
- **Guided introduction** *(1.4)*: a walkthrough on every platform that presents the features, offers the iCloud backup restore and asks the notification consent; replayable from About.
- **Siri and Shortcuts** *(iOS, macOS, visionOS, tvOS)*: status, speeds, queue count, single-download status / pause / resume / priority, pause / resume all, remove completed, add eD2k links, search, eD2k connect / disconnect, Kad start / stop — they work even when the app is closed.
- **`ed2k://` links from the system**: the app is registered as the handler for the `ed2k` scheme — a click in Safari or Mail opens the app and queues the download after confirmation.
- **7 languages**: English, Italian, Spanish, French, German, Simplified Chinese and Arabic (RTL), with an in-app selector and a "System" option.
- **Demo mode**: explore the whole app with sample data and no server ("Try the demo mode" on the connection screen, or `DEMO` as host and password).
- If the aMule server stops, the app **disconnects automatically** and shows a "Server stopped" banner instead of a network error.

## Server-side setup (Unraid / Docker)

In the container's `amule.conf` (usually under `/config/amule/` or similar):

```ini
[ExternalConnect]
AcceptExternalConnections=1
ECPort=4712
ECPassword=<MD5 of your password>
```

Generate the MD5 hash with: `echo -n "mypassword" | md5sum`.
Expose/forward the container's **4712/TCP** port and restart the container after editing.
Full guide: **[Wiki → Server setup](https://github.com/sidimam/AmuleRemote/wiki/Server-setup)**.

> ⚠️ EC traffic is not encrypted. For access from outside your home use a VPN (WireGuard/Tailscale) instead of exposing port 4712 to the Internet.

## Building

### macOS (Swift Package)

Requires the Xcode Command Line Tools (Swift 5.9+):

```bash
cd aMuleRemote
swift build -c release
cp .build/release/AmuleRemote "aMule Remote.app/Contents/MacOS/aMule Remote"
xcrun xcstringstool compile Localizable.xcstrings --output-directory "aMule Remote.app/Contents/Resources"
codesign --force --deep --sign - "aMule Remote.app"   # ad-hoc signature for local use
```

### iOS / iPadOS, watchOS, visionOS and Mac App Store

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
```

Targets: `AmuleRemoteiOS` (iPhone/iPad), `AmuleRemoteWatch`, `AmuleRemoteVision` (Apple Vision Pro), `AmuleRemoteTV` (Apple TV) and `AmuleRemoteMac` (sandboxed Mac App Store build). Every target carries the iCloud Key-Value Storage entitlement and a shared keychain access group (profile sync); the DMG build gets the same entitlements at signing time (`SupportFiles/MacDirect.entitlements` + a Developer ID provisioning profile embedded in the bundle). Shared sources in `Sources/AmuleRemote` are listed one by one in `project.yml`: a new shared file must be added there to be compiled into the iOS, visionOS and tvOS apps. See **[Wiki → Building and signing](https://github.com/sidimam/AmuleRemote/wiki/Building-and-signing)**.

## Signing and distribution

> App Store exports (`xcodebuild -exportArchive`, automatic signing) need an Apple Account signed in to Xcode, or an App Store Connect API key with the *Access to Cloud Managed Distribution Certificate* permission; otherwise use manual signing with a local Apple Distribution certificate and App Store profiles. Details in the wiki page above.

Since build 15 the macOS app published in the Releases is signed with a **Developer ID Application** certificate and **notarized by Apple** (stapled): it installs and opens on any Mac without security warnings and without keychain prompts. Before signing, strip the extended attributes that cloud-synced folders add to the bundle (`xattr -cr "aMule Remote.app"`), otherwise codesign refuses the bundle. The tvOS archive must be **signed at archive time** (manual signing with the App Store profile: no registered Apple TV is needed), otherwise the exported app loses the iCloud entitlements — check every export with `codesign -d --entitlements :- <app>` before uploading.

Reference process:

```bash
cp YourDeveloperID.provisionprofile "aMule Remote.app/Contents/embedded.provisionprofile"   # iCloud sync
codesign --force --deep --options runtime --timestamp \
  --entitlements SupportFiles/MacDirect.entitlements \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" "aMule Remote.app"
ditto -c -k --keepParent "aMule Remote.app" notarize.zip
xcrun notarytool submit notarize.zip --key AuthKey.p8 --key-id KEYID --issuer ISSUER --wait
xcrun stapler staple "aMule Remote.app"
# DMG: folder with the app + a symlink to /Applications, Finder layout,
# hdiutil convert UDZO, then codesign + notarytool + stapler on the DMG too.
```

## Versioning

Marketing version and build number are kept aligned across all platforms. Current: **1.4.1 (build 21)**. Release tags follow the pattern `v1.4.1-build21`. Every release has the same *What's new* in [CHANGELOG.md](CHANGELOG.md), in the GitHub release notes, in the App Store listing of every platform, in the [wiki](https://github.com/sidimam/AmuleRemote/wiki/Features) and in the Homebrew tap README.

## Protocol verification

The EC implementation (MD5-salted handshake, framing, nested tags, every operation) was tested end-to-end against a real amuled 2.3.x: authentication, statistics, server add/remove, ed2k links, download queue, pause/priority/delete, shared files, search, preferences get/set, log, wrong-password rejection. Details in **[Wiki → EC protocol](https://github.com/sidimam/AmuleRemote/wiki/EC-protocol)**.

## Privacy

aMule Remote collects no data at all: it only talks to the amuled server you configure. Server address and password are stored in the device Keychain; with the optional iCloud sync they travel only through your own iCloud account (Key-Value Storage and iCloud Keychain). Full text: [Privacy policy](https://sidimam.github.io/AmuleRemote/).

## Support

- 📖 [Wiki](https://github.com/sidimam/AmuleRemote/wiki) — setup guides, features, FAQ.
- 🐞 [Report a problem](https://github.com/sidimam/AmuleRemote/issues/new/choose) — the in-app *Report a problem* link pre-fills version, build and platform.

## License

aMule Remote is free software released under the **[MIT License](LICENSE)** — Copyright © 2026 Simone Di Mambro. The EC (External Connections) protocol belongs to the [aMule project](https://amule-org.github.io).
