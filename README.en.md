<div align="center">
  <img src="Assets/MacGamingUncleIcon.png" width="144" alt="Mac Gaming Uncle icon">
  <h1>Mac Gaming Uncle</h1>
  <p><strong>Run Windows games you own on Apple Silicon Macs.</strong></p>
  <p>Native SwiftUI · Wine · Apple D3DMetal · MetalFX · DXVK</p>
  <p><a href="https://github.com/enginefuture/mac-gaming-uncle/releases/download/v0.2.1/Mac-Gaming-Uncle-0.2.1-macOS-arm64.dmg">Download the 0.2.1 DMG</a> · <a href="https://github.com/enginefuture/mac-gaming-uncle/releases/tag/v0.2.1">Release notes</a></p>
  <p>English · <a href="README.md">简体中文</a></p>
</div>

<p align="center">
  <img src="Assets/MacGamingUncleHero.png" width="100%" alt="Uncle was not wrong—he was simply early.">
</p>

> [!IMPORTANT]
> Mac Gaming Uncle is an open-source compatibility research project, not a virtual machine. The app bundle contains no Windows, Steam, games, or Apple D3DMetal. Onboarding downloads the original GPTK image separately through our R2 channel and verifies it before local import. Apple's original license and noncommercial distribution terms still apply. See [GPTK distribution](docs/GPTK_DISTRIBUTION.md).

## Beginner installation guide

You can install the DMG directly. No programming, Xcode, or source build is required.

### 1. Check your Mac

Open ** → About This Mac**. You need an Apple Silicon (M-series) Mac with **macOS 15 or later**; Intel Macs are not supported. Have an Internet connection, your Steam account, and enough free disk space for the components and games you plan to install.

### 2. Download the installer

Select **[Download Mac Gaming Uncle 0.2.1 (DMG)](https://github.com/enginefuture/mac-gaming-uncle/releases/download/v0.2.1/Mac-Gaming-Uncle-0.2.1-macOS-arm64.dmg)**.

Alternatively, open the [Release page](https://github.com/enginefuture/mac-gaming-uncle/releases/tag/v0.2.1) and choose `Mac-Gaming-Uncle-0.2.1-macOS-arm64.dmg` under **Assets**. `Source code`, `.sha256`, and the Wine `.tar.xz` are source archives, checksums, and a runtime that the app downloads automatically—not the app installer.

### 3. Install and open the app

1. In Finder's Downloads folder, double-click the downloaded `.dmg`.
2. Drag **Mac Gaming Uncle** onto the **Applications** folder icon and wait for copying to finish.
3. Open **Mac Gaming Uncle** from Finder's Applications folder, rather than running it from the mounted DMG.
4. Eject the installer disk from Finder's sidebar when finished.

This research preview is not notarized. If macOS cannot verify the developer, check that the download came from the official repository linked above. If you decide to trust it, after attempting to open the app, go to **System Settings → Privacy & Security → Security → Open Anyway** and follow the prompts. See [Apple's instructions](https://support.apple.com/en-us/102445). If macOS reports malware or a damaged file, stop, download again, and report the issue rather than disabling system protection.

### 4. Let setup finish and sign in to Steam

The first launch automatically displays two setup steps:

1. **Install the game environment**: the app checks and installs Rosetta, Wine, controller support, and graphics components. Keep it open while setup runs. If a step fails, read the error and select **Retry and continue**; completed components are retained.
2. **Sign in to Steam**: the app installs and updates Windows Steam, then opens its official login window. Scan the QR code using the Steam mobile app, or enter your Steam credentials and any required verification code. A separate Steam window is expected.

The initial Steam update can take several minutes. After signing in, return to Mac Gaming Uncle; library synchronization is automatic. Being signed in to the native macOS Steam app does not sign you in to this Windows Steam installation.

### 5. Install and play a game

Open **Library**, select a game you own, and choose **Install**. Follow Steam's prompts and wait for the download to finish, then choose **Start Game**. Browsing a title in the Store does not grant ownership; obtain the appropriate license through Steam first.

Start with default settings. Open **Game Settings** when you need to adjust resolution, HUD, or controller options. Pair a controller with macOS first, then inspect it using the controller shortcut in the top bar. The first game launch may take longer while graphics caches are built. A library listing does not mean a game has been verified compatible.

### Troubleshooting and updates

| Symptom | What to do |
| --- | --- |
| Signed in, but the library is empty | Wait for Steam to write its account cache, then choose **Sync Library** on Home or **Refresh** in Library. Check that you signed in to the Windows Steam opened by this app. The list depends on local Steam caches and may not include every owned title. |
| Component installation fails | Check the error, network connection, and free disk space, then retry. |
| A game fails to launch or renders incorrectly | Report its name, error, and renderer in [Issues](https://github.com/enginefuture/mac-gaming-uncle/issues). Do not include passwords, verification codes, or login files. |
| Updating the app | Exit your game and Mac Gaming Uncle, download the new DMG, and replace the app in Applications. Keep the application data directory to retain components and games. |

Closing Mac Gaming Uncle also shuts down its managed Steam. Save and exit your game before closing the app.

## Why this project exists

For years, “gaming on a Mac” was treated as a punchline. We want it to become ordinary and simple: install the app, sign in to Steam, download a game, and press Play. People should not need to learn Wine, bottles, graphics translation, and launch flags before they can enjoy games they already own.

Mac Gaming Uncle's long-term goal is to provide a SteamOS-like experience on the Mac: the system absorbs compatibility complexity while game installation, configuration, updates, and launching become as automatic as possible. It is not a SteamOS port and is not affiliated with Valve; the inspiration is SteamOS's product principle of hiding difficult technology behind a simple experience.

### Permanent noncommercial commitment

The official Mac Gaming Uncle project and its official releases will remain permanently noncommercial: no paid edition, subscriptions, advertising, paid compatibility lists, game commissions, or sale of user data. Compatibility recipes, issue records, and core implementation remain public. Success means helping more Mac users play games they legally own—not generating revenue.

> This commitment governs the official project's operation. The source remains under Apache License 2.0, which permits third-party use and redistribution under its terms; the official project will not use “noncommercial” branding to restrict ordinary open-source collaboration.

## Project status

Mac Gaming Uncle is currently a `0.2.1` research preview for Apple Silicon and macOS 15 or later. It now provides a Steam-client shell, native Store and Library, per-game settings, a reusable global Steam session, and an SDL/XInput controller launch path.

Hardware validation: Apple M3 Max, macOS 26.6.2, GPTK 4.0 beta 2, and Mac Gaming Uncle Wine 11.0.2. `Grim Dawn 1.3.0.8 (x64)` has been validated with its complete Chinese UI, Steam integration, XInput controller support, and Apple's in-game Metal HUD (D3D11, approximately 114 FPS); `Ruins of Dawn` reaches its main menu.

## Screenshots

These screenshots were captured from Mac Gaming Uncle 0.2.0 running on real hardware.

<table>
  <tr>
    <td width="50%"><strong>Home and recently played</strong><br><a href="docs/screenshots/0.2.0/home.png"><img src="docs/screenshots/0.2.0/home.png" width="100%" alt="Mac Gaming Uncle Home"></a></td>
    <td width="50%"><strong>Native Steam Store</strong><br><a href="docs/screenshots/0.2.0/store.png"><img src="docs/screenshots/0.2.0/store.png" width="100%" alt="Mac Gaming Uncle native Steam Store"></a></td>
  </tr>
  <tr>
    <td width="50%"><strong>Account Library and game details</strong><br><a href="docs/screenshots/0.2.0/library.png"><img src="docs/screenshots/0.2.0/library.png" width="100%" alt="Mac Gaming Uncle Library"></a></td>
    <td width="50%"><strong>Per-game settings entry</strong><br><a href="docs/screenshots/0.2.0/library-settings-entry.png"><img src="docs/screenshots/0.2.0/library-settings-entry.png" width="100%" alt="Mac Gaming Uncle settings entry"></a></td>
  </tr>
  <tr>
    <td width="50%"><strong>Per-game configuration</strong><br><a href="docs/screenshots/0.2.0/per-game-settings.png"><img src="docs/screenshots/0.2.0/per-game-settings.png" width="100%" alt="Mac Gaming Uncle per-game settings"></a></td>
    <td width="50%"><strong>Controller Center</strong><br><a href="docs/screenshots/0.2.0/controller-center.png"><img src="docs/screenshots/0.2.0/controller-center.png" width="100%" alt="Mac Gaming Uncle Controller Center"></a></td>
  </tr>
</table>

## Features

- Native SwiftUI/AppKit interface with a guided Chinese onboarding flow.
- Pixel-game brand art: a tired mustached uncle app icon, a whole-apple controller mark, and a transparent pixel apple for launch buttons, with no bite or play triangle.
- Top-level navigation focuses on Home, Store, and Library; controllers, downloads, and runtime setup remain supporting tools without a separate Community channel.
- A focused Steam-client shell with a native Store home/categories/search experience, account library, artwork, details, install, and launch actions.
- Public Store browsing requires no web login; wishlist, purchase, and account actions open a clearly labeled `store.steampowered.com` secure page without copying Steam CEF's encrypted session cookies.
- Reads AppIDs, playtime, and recent activity from the local Steam `localconfig.vdf` without reading or uploading authentication tokens, and caches official Store metadata locally.
- Downloads the Windows Steam installer from Valve's official CDN.
- Downloads the original GPTK 4 image through the project's Cloudflare R2 channel, verifying size, SHA-256, DMG integrity and Apple signature.
- Imports the complete D3DMetal framework, Wine PE bridge and Unix bridge while retaining the original image and license separately.
- Builds and installs Mac Gaming Uncle Wine 11 from corresponding public source, with GCC 15 MinGW, new WoW64, MSync, SDL2 winebus/XInput, Steam CEF fixes, and a native D3DMetal bridge path.
- Repairs Steam CEF compatibility and installs CJK fonts with DirectWrite font linking.
- Resolves the x64/`*-Win64-Shipping.exe` target, then lets Steam create it through `-applaunch` so SteamAPI, renderer, and HUD state are inherited intact.
- Keeps a global signed-in Steam session and reuses it whenever launch environments are compatible; it restarts only for conflicting renderer, HUD, synchronization, or virtual-desktop settings.
- Installs native D3DMetal PE bridges into the bottle with versioned backups, and automatically repairs the CEF wrapper after a Steam update replaces it.
- Invalidates shader caches when the GPTK version, source hash, MetalFX, DXR, Metal 4, macOS version, or compatibility arguments change.
- Auditable game recipes matched by Steam AppID and executable name.
- Static PE architecture, DirectX import, and anti-cheat inspection; kernel anti-cheat is blocked before launch.
- Apple Metal Performance HUD in the same Mac Gaming Uncle Wine 11 process that runs the game.
- Per-game settings for virtual-desktop resolution, renderer, synchronization, Metal HUD, MetalFX, Metal 4, and launch arguments; settings survive Steam rescans.
- A dedicated Controller Center for Bluetooth discovery, device/battery/capability status, player assignment, live input and rumble tests, plus per-game SDL HIDAPI compatibility.
- SQLite state, isolated Wine bottles, recoverable backups, CLI diagnostics, and automated tests.

## How it works

```text
Windows game
     │
     ├─ Win32 / Win64 APIs ──────────────→ Wine
     ├─ x86_64 instructions ─────────────→ Rosetta 2
     └─ Direct3D 11 / 12 ─→ D3DMetal ───→ Metal
                           └→ DXVK/MoltenVK (fallback)

Steam AppManifest → discovery → game recipe → immutable LaunchPlan → isolated bottle
```

Mac Gaming Uncle composes, verifies, and launches these layers. It does not modify game content or bypass DRM, licensing, or anti-cheat systems.

## Quick start

### Requirements

- Apple Silicon Mac
- macOS 15 or later
- Network access to the component download servers
- A Steam account and games you legally own

### Build from source

For developers only: this requires Xcode 26 or a compatible full Swift 6 toolchain. Other users should follow the Beginner installation guide above.

If you do not need a development environment, download the mount-verified [Mac Gaming Uncle 0.2.1 DMG](https://github.com/enginefuture/mac-gaming-uncle/releases/download/v0.2.1/Mac-Gaming-Uncle-0.2.1-macOS-arm64.dmg) and verify it with the adjacent [SHA-256 file](https://github.com/enginefuture/mac-gaming-uncle/releases/download/v0.2.1/Mac-Gaming-Uncle-0.2.1-macOS-arm64.dmg.sha256).

```bash
git clone https://github.com/enginefuture/mac-gaming-uncle.git
cd mac-gaming-uncle
scripts/build-app.sh
open "dist/Mac Gaming Uncle.app"
```

Build and mount-verify a distributable DMG:

```bash
scripts/build-dmg.sh
```

The current open-source research preview is ad-hoc signed and not notarized. If Gatekeeper blocks a verified GitHub Release download, remove quarantine after reviewing its source:

```bash
xattr -dr com.apple.quarantine "/Applications/Mac Gaming Uncle.app"
```

Development builds are ad-hoc signed. Set a Developer ID for distribution:

```bash
MAC_GAMING_UNCLE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  scripts/build-app.sh
```

### Game settings

MetalFX/DLSS mapping is experimental and disabled by default. It can only help games that already implement DLSS, and recipes can explicitly disable it. `Grim Dawn` does not use DLSS, so Mac Gaming Uncle ignores the global MetalFX toggle for that title to prevent the NVNGX GPU-spoof path from dropping its UI.

“Prefer Metal 4” is enabled by default, but Mac Gaming Uncle first queries the active `MTLDevice` for hardware and OS support. Unsupported systems fall back automatically, and the option can be disabled for a title that regresses. The D3DMetal release, the game's Direct3D API, and the Metal submission path are separate dimensions; a HUD reading `Game Porting Toolkit 4.0b2 · D3D11` is expected.

“Show Apple Metal HUD” relays Apple's HUD environment through Steam to the target game. It does not switch to Apple Evaluation Wine or bypass Steam. The HUD appears only with D3DMetal or DXMT. The `Grim Dawn 1.3` recipe selects the x64 executable and D3DMetal 4, matches the game resolution to the Mac display's logical-point dimensions, and backs up `options.txt` before enabling the classic HUD and native gamepad support. It also disables MSync and Steam Overlay for this title to avoid missing UI and displaced pointer hit regions.

## Development and testing

```bash
swift test
swift build -c release
swift run macgamingunclectl --json doctor
scripts/check.sh
scripts/build-indie-wine11.sh
```

Useful CLI commands:

```text
macgamingunclectl doctor
macgamingunclectl pe <game.exe>
macgamingunclectl steam-scan <steamapps-directory>
macgamingunclectl recipes validate <recipes-directory>
macgamingunclectl gptk import <apple-gptk.dmg|mounted-directory>
macgamingunclectl wine latest
macgamingunclectl wine gaming-install
macgamingunclectl wine local-install <runtime-root>
macgamingunclectl dxvk install <bottle-root>
macgamingunclectl dxmt install
macgamingunclectl steam repair <bottle-root> [wrapper.exe]
macgamingunclectl fonts repair <bottle-root> <runtime-root>
```

Further reading:

- [Architecture](docs/ARCHITECTURE.md)
- [Runtime supply chain](docs/RUNTIME_SUPPLY_CHAIN.md)
- [Testing guide](docs/TESTING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Compatibility boundaries

- Wine is a compatibility layer, not a security sandbox. Windows processes still run with the current macOS user's permissions.
- Kernel anti-cheat, Windows drivers, UWP, some DRM systems, and software requiring AVX-512 generally do not work.
- Compatibility for 32-bit titles, D3D9/10/11, launchers, and video playback varies by game.
- D3DMetal, Steam, and games remain subject to their own terms. This repository does not provide those binaries.
- Mac Gaming Uncle is not affiliated with Apple, Valve, CodeWeavers, or any game publisher.

## Contributing

Reproducible compatibility reports, game recipes, tests, and code improvements are welcome. Issues should include the Mac model, macOS version, GPTK/D3DMetal version, Steam AppID, launch arguments, and relevant logs with personal information removed.

Do not submit game files, account credentials, Apple download media, D3DMetal binaries, or material intended to bypass DRM or anti-cheat systems.

## License

Mac Gaming Uncle source code is licensed under the [Apache License 2.0](LICENSE). Third-party components remain under their own licenses or terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
