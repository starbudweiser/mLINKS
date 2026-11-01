# mLINKS

[Français](README.fr.md)

Your apps, folders, files and web addresses one click away, from the macOS menu bar or with a global keyboard shortcut.

## Features

- **Menu bar menu**: your groups as submenus, with icons. Hold ⌥ to reveal an item in Finder instead of opening it.
- **Links to anything**: apps, folders, files and web addresses. A missing target (unplugged disk) is flagged "Not found"; a sleeping external disk never freezes the menu.
- **Global shortcuts**: one per link, no Accessibility permission needed.
- **Manager window**: create, rename and reorder groups, drag and drop from Finder, hide links from the menu.
- **Import from QuickLinks**: reads the QuickLinks (Appyogi) database or a `.CSV` export, never modifies them, and never creates duplicates when re-imported.
- **Automatic updates**: checks GitHub releases once a day (can be turned off), verifies the Developer ID signature and notarization, then replaces and relaunches the app from the menu.
- **Four languages** (French, English, Spanish, Italian), picked from the system language.
- Dark, flat interface; no Dock icon; optional launch at login.

## Build

Requires macOS 14+ and Xcode (Swift 6).

```bash
swift test          # unit tests
./build_app.sh      # builds mLINKS.app, signs it and installs it
```

`NO_INSTALL=1 ./build_app.sh` builds `./mLINKS.app` without installing it. Without a local signing identity, the app is signed ad hoc. Links are stored in `~/Library/Application Support/mLINKS/links.json`.

Offscreen checks, without opening any window: `mLINKS --capture out.png`, `--capture-about out.png`, `--import file`.

## About

mLINKS is a personal, from-scratch re-creation of the idea behind [QuickLinks](https://appyogi.com/webapps/index.php?product_id=40&source=com.appyogi.quicklinks&ref=about) by Appyogi. It is not affiliated with Appyogi and shares none of its code or assets.

Authors: Starbudweiser & Claude Code (Anthropic). MIT License, © 2026 Starbudweiser. Provided as is, without warranty.
