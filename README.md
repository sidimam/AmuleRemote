# aMule Remote

Native **macOS, iOS, iPadOS and visionOS** app (SwiftUI, with an **Apple Watch** companion) to remotely control an **amuled** server — for example the aMule container on your Unraid box, a NAS or a Raspberry Pi — over the **EC (External Connections)** protocol, the same one used by aMuleGUI and amulecmd. EC protocol 0x0204, compatible with aMule 2.3.x.

> 📖 Detailed guides in the **[Wiki](https://github.com/sidimam/AmuleRemote/wiki)** · 🔒 [Privacy policy](https://sidimam.github.io/AmuleRemote/)

<p align="center">
  <a href="https://github.com/sidimam/AmuleRemote/releases/latest/download/aMuleRemote-macOS.dmg">
    <img src="https://img.shields.io/badge/macOS-Download_the_DMG_(latest)-0071e3?style=for-the-badge&logo=apple&logoColor=white" alt="Download the macOS DMG" height="44">
  </a>
  &nbsp;&nbsp;
  <a href="https://apps.apple.com/app/amule-remote/id6800020841">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download on the App Store (iPhone, iPad, Mac, Apple Vision Pro)" height="44">
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
</p>

## Download

- **iPhone / iPad**: **[App Store](https://apps.apple.com/app/amule-remote/id6800020841)** (free). The Apple Watch app is bundled. You can also build it yourself with Xcode (see *Building*).
- **Mac**, three options:
  - **DMG** — download **`aMuleRemote-macOS.dmg`** from the latest **[Release](https://github.com/sidimam/AmuleRemote/releases/latest)**, open it and drag **aMule Remote** onto the **Applications** folder next to it. The app is signed with a **Developer ID** and **notarized by Apple**: it opens right away, with no Gatekeeper warnings and no keychain prompts. *(A `.zip` with the same app is attached to every release too.)*
  - **Homebrew** — `brew install --cask sidimam/tap/amule-remote` (same notarized DMG, updated with `brew upgrade`). Cask source: [sidimam/homebrew-tap](https://github.com/sidimam/homebrew-tap).
  - **Mac App Store** — the sandboxed build lives on the [same App Store page](https://apps.apple.com/app/amule-remote/id6800020841) as the iOS app (universal purchase).
- **Apple Vision Pro**: on the App Store in the countries where Vision Pro is sold.

## Features

- **Transfers**: download queue with progress, speed, sources, ETA, status and **download age** (days in queue); pause / resume / stop / delete; priority (low/normal/high/auto); category assignment; add `ed2k://` links; multi-selection with an action bar; "Remove completed"; active uploads panel (Mac).
- **Search**: **local** and **global (server)**, tabbed (several searches at once), with filters (file type, extension, min/max size, availability) and an automatic 120 s timeout. Double-click / tap a result to download it. Results already in your transfers are highlighted in **red**, files you already downloaded in **green**.
- **Servers**: server list with users/files/ping, connect (double-click / tap), disconnect, add, remove, update the list from a `server.met` URL; **eD2k** and **Kad** network controls.
- **Shared files** *(Mac)*: list with requests/uploads, share priority, reload shared folders, copy ed2k link.
- **Statistics** and the server **log** in real time; **connection test** (EC port and optional web server) on iOS.
- **aMule preferences** *(Mac)*: the full remote `amule.conf` editor — General, Connection, Servers, Files, Security, Message filters, Tweaks (core + Kademlia), Remote control (web server).
- **Server profiles**: several named amuled servers, one **default** proposed at launch, quick switching; passwords always in the Keychain.
- **Notifications** *(1.2)*: a single master switch that asks for permission and sends a test notification; separate toggles for **completed downloads**, **eD2k/Kad disconnections** and **checks while disconnected**, with a **configurable interval** (1 min – 1 h). Checks keep running after the idle disconnect on every platform; on iOS they also run in the background (Background App Refresh, never more often than every 15 minutes). eD2k/Kad drops are reported only when the server's auto-reconnect is off. Notifications also reach Apple Watch.
- **Appearance**: light / dark / system theme; **7 app icon colors** *(1.2)* on iPhone, iPad and Vision Pro (with dark and tinted variants) and a matching Dock icon on the Mac.
- **Face ID / Touch ID lock** (optional) and **auto-disconnect after inactivity** (configurable) on every platform.
- **Apple Watch app**: speeds, eD2k/Kad status and the download queue, mirrored from the iPhone.
- **Siri and Shortcuts** *(iOS)*: "aMule status", "Pause / Resume downloads", "Add eD2k link" — they work even when the app is closed.
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

Targets: `AmuleRemoteiOS` (iPhone/iPad), `AmuleRemoteWatch`, `AmuleRemoteVision` (Apple Vision Pro) and `AmuleRemoteMac` (sandboxed Mac App Store build). Shared sources in `Sources/AmuleRemote` are listed one by one in `project.yml`: a new shared file must be added there to be compiled into the iOS and visionOS apps. See **[Wiki → Building and signing](https://github.com/sidimam/AmuleRemote/wiki/Building-and-signing)**.

## Signing and distribution

Since build 15 the macOS app published in the Releases is signed with a **Developer ID Application** certificate and **notarized by Apple** (stapled): it installs and opens on any Mac without security warnings and without keychain prompts.

Reference process:

```bash
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" "aMule Remote.app"
ditto -c -k --keepParent "aMule Remote.app" notarize.zip
xcrun notarytool submit notarize.zip --key AuthKey.p8 --key-id KEYID --issuer ISSUER --wait
xcrun stapler staple "aMule Remote.app"
# DMG: folder with the app + a symlink to /Applications, Finder layout,
# hdiutil convert UDZO, then codesign + notarytool + stapler on the DMG too.
```

## Versioning

Marketing version and build number are kept aligned across all platforms. Current: **1.2 (build 17)**. Release tags follow the pattern `v1.2-build17`.

## Protocol verification

The EC implementation (MD5-salted handshake, framing, nested tags, every operation) was tested end-to-end against a real amuled 2.3.x: authentication, statistics, server add/remove, ed2k links, download queue, pause/priority/delete, shared files, search, preferences get/set, log, wrong-password rejection. Details in **[Wiki → EC protocol](https://github.com/sidimam/AmuleRemote/wiki/EC-protocol)**.

## Privacy

aMule Remote collects no data at all: it only talks to the amuled server you configure. Server address and password are stored in the device Keychain. Full text: [Privacy policy](https://sidimam.github.io/AmuleRemote/).
