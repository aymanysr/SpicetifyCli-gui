# Concepts Brief: Spicetify GUI (macOS Native)

## Core Hypothesis
A zero-dependency, native Apple Silicon (`arm64`) SwiftUI + AppKit desktop app can eliminate day-to-day Spicetify CLI friction while consuming near-zero power (0% idle CPU, ~20–30 MB active RAM, zero background daemons) and remaining resilient across future Spicetify CLI and Spotify desktop updates.

## Scope Boundaries

### Explicit Goals
* **Lowest-Power Native Footprint:** Pure event-driven SwiftUI + AppKit `.app` bundle compiled with `swiftc -O`; quits completely when the window closes; zero timers, polling, web servers, or browser engines.
* **Reliable macOS App Icon:** Properly rendered, multi-resolution icon that displays consistently in Finder, Spotlight, Applications, Dock, and in-app sidebar — immune to stale LaunchServices cache when replacing earlier builds.
* **Update-Safe Architecture:** Dynamically locates `spicetify` and `config-xpui.ini` at runtime; reads INI defensively (ignoring unknown future keys); writes only changed keys via `spicetify config`; includes a raw command fallback for future CLI subcommands.
* **Applicable Extension & Custom App Updating:**
  * Built-in extensions and custom apps updated via `spicetify upgrade`.
  * Spicetify Marketplace updated via its official macOS install/update script.
  * Git-cloned user extensions, custom apps, and themes detected via `.git` and updated via `git pull --ff-only`.
  * Clear distinction for Marketplace-managed items (which auto-update inside Spotify's Marketplace tab) and standalone local `.js` files (which have no upstream update channel).
* **Actionable Error Diagnostics:** Plain-English remediation hints alongside the raw monospace CLI log (e.g., detecting Spotify update mismatches and suggesting **Backup & Apply**).

### Non-Goals
* Replacing Spicetify Marketplace's theme/extension store browser.
* Scraping arbitrary GitHub URLs to auto-update manually dropped standalone `.js` files without metadata.
* Running a persistent menu bar daemon, launch agent, or background update poller (violates minimal-power constraint).
* Cross-platform support (Windows/Linux).

## Key Architectural Decisions (6 EGM Lenses)

| EGM Lens | Decision (Best Default) |
| :--- | :--- |
| **1. Contrarian / YAGNI** | Delegate store browsing/updates to existing Spicetify Marketplace; GUI focuses strictly on CLI operations, local/built-in/Git/Marketplace updates, and config toggling. |
| **2. Cost & Resource Economics** | Strictly on-demand native `arm64` app; exits on window close (`applicationShouldTerminateAfterLastWindowClosed = true`); 0% background CPU/battery draw. |
| **3. UX & Ergonomics** | Updates do **not** silently restart Spotify — they mark a visible "Apply Changes" banner (with an optional "Update & Apply" convenience action); icon uses verified `AppIcon.icns` + `AppIcon.png` runtime fallback + bumped bundle version (`CFBundleVersion`) + documented Finder refresh step. |
| **4. Migration & Compatibility** | Support `~/.spicetify`, Homebrew (`/opt/homebrew/bin`), `/usr/local/bin`, and `PATH` lookup; diff-only `spicetify config` writes prevent deprecated keys from breaking unrelated changes; raw command bar covers future CLI flags. |
| **5. Observability & Debugging** | Collapsible live command log with ANSI stripping, Copy/Clear buttons, and pattern-matched plain-English hints for common failures (Spotify update, missing backup, offline network, dirty git tree). |
| **6. Tech Debt & Maintenance** | Keep source, icon generator, build script, and `docs/designs/` inside a self-contained project folder (`spicetify-gui-project/`) that can be moved to `~/Projects/` and never gets overwritten by `spicetify upgrade`; install the built `.app` to `/Applications/`. |
