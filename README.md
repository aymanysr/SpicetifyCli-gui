# Spicetify GUI (macOS)

A lightweight, native SwiftUI + AppKit graphical interface for [Spicetify CLI](https://spicetify.app/) on macOS (Apple Silicon & Intel).

## Features
* **Minimal power usage:** Compiled native macOS binary (~650 KB) with zero Electron, browser engine, or background daemon. Quits completely when you close the window (0% idle CPU).
* **One-click Quick Actions:** Apply, Backup & Apply (after Spotify updates), Upgrade CLI & Built-ins, Update Marketplace, Restart Spotify, and Restore Stock Spotify.
* **Appearance Manager:** Pick installed themes and auto-parsed color schemes from `color.ini`, toggle CSS/JS/color flags, and write only changed keys via `spicetify config`.
* **Extensions & Custom Apps Updater:**
  * **Built-in** items update via `spicetify upgrade`.
  * **Marketplace** updates via the official Spicetify Marketplace script.
  * **Git-cloned** custom apps and extensions are detected automatically (`.git`) and updated safely via `git pull --ff-only`.
  * **Marketplace-installed** extensions continue to auto-update inside Spotify's Marketplace tab.
* **Update-resilient:** Dynamically resolves `spicetify` (`SPICETIFY_INSTALL`, `~/.spicetify`, Homebrew Apple Silicon/Intel, and `PATH`), reads `config-xpui.ini` defensively (ignoring unknown future keys), and includes a quote-aware **Run Any Spicetify Command** bar for future CLI flags.
* **Actionable error hints:** Surfaces plain-English recovery tips (such as suggesting **Backup & Apply** after a Spotify update) alongside the live command log.

## Requirements
* macOS 14.0 or later (Apple Silicon or Intel)
* Xcode Command Line Tools (`xcode-select --install`) to build from source
* [Spicetify CLI](https://spicetify.app/docs/getting-started) installed

## Build & Install
```bash
chmod +x scripts/build.sh
./scripts/build.sh
cp -R build/SpicetifyGUI.app /Applications/
```

If macOS prompts on first launch (because the app is ad-hoc signed locally), right-click **SpicetifyGUI.app** in `/Applications` and click **Open**.

### First-Time macOS Permission (App Management)
Because Spicetify patches `/Applications/Spotify.app`, macOS requires **App Management** permission for **Spicetify GUI**:
1. Open **System Settings → Privacy & Security → App Management** (or click the in-app **Open App Management Settings** button if a permission banner appears).
2. Enable **Spicetify GUI** (click **+** to add it from `/Applications` if not listed).
3. Quit and reopen **Spicetify GUI**.

### Refreshing the Finder icon after upgrading from an earlier build
macOS Finder caches app icons aggressively when replacing an existing `.app`. If Finder still shows an older icon after copying into `/Applications`, run:
```bash
touch /Applications/SpicetifyGUI.app && killall Finder
```

## Run Verification Checks
```bash
swift scripts/test_logic.swift src/SpicetifyGUI.swift
```

## Architecture & Design Docs
This project was designed using the Elephant-Goldfish Model (EGM). See [`concepts_brief.md`](concepts_brief.md) and [`docs/designs/spicetify-gui.md`](docs/designs/spicetify-gui.md).

## License
MIT License — see [`LICENSE`](LICENSE).
