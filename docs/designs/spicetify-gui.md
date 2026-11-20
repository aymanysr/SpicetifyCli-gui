# Design Specification: Spicetify GUI (macOS Native v1.2)

Status: **Approved (v1.2 — Goldfish Review Fixes Applied)**  
Target Platform: macOS 14+ (Apple Silicon `arm64`)  
Project Root: `spicetify-gui-project/` (portable — place anywhere, e.g. `~/Developer/spicetify-gui-project`)

---

## Zone 1: Feature Range (High-Level Architecture)

### 1.1 Problem Statement
Spicetify CLI requires memorizing terminal subcommands (`backup apply`, `upgrade`, `config extensions foo.js-`, `restore`) and manually troubleshooting post-Spotify-update breakages. Existing third-party GUIs either rely on heavy web runtimes (Electron/browser) or lack macOS support and update resilience. Additionally, the v1.1 prototype had two gaps:
1. The app icon failed to render in Finder after replacing an earlier build in `/Applications` due to macOS `.icns` chunk/cache quirks and sandboxed LaunchServices registration.
2. Users need a clear, safe way to update extensions and custom apps where an upstream update mechanism exists.

### 1.2 Core User Journeys
1. **Post-Spotify-Update Recovery:** User opens `Spicetify GUI` from `/Applications` -> clicks **Backup & Apply** -> views live progress and success status -> closes window (app terminates, 0% idle power).
2. **Updating Extensions & Custom Apps:** User opens **Extensions** or **Custom Apps** tab -> sees source badges (`Built-in`, `Marketplace`, `Git Repo`, `Local`) -> clicks **Update** on an eligible item or **Update All Applicable** -> reviews log -> clicks **Apply Now** on the pending banner.
3. **Theme & Flag Tweaking:** User opens **Appearance** -> picks a theme and auto-parsed color scheme -> clicks **Save & Apply** -> only modified keys are passed to `spicetify config`, followed by `spicetify apply`.
4. **Future CLI Command Execution:** After a future Spicetify CLI release adds a new flag, user runs it directly from the **Run Any Spicetify Command** input without waiting for a GUI update.

### 1.3 System Architecture & Boundaries
```text
┌──────────────────────────────────────────────────────────┐
│                 SpicetifyGUI.app (arm64)                 │
│  SwiftUI Views  <──>  @MainActor SpicetifyManager        │
│                          │                               │
│         ┌────────────────┼────────────────┐              │
│         ▼                ▼                ▼              │
│  Read-Only Scanner   CommandRunner   DiagnosticMapper    │
│  (config-xpui.ini,   (Process async  (maps stderr/exit   │
│   Themes/Ext/Apps,    merged Pipe)    codes to hints)    │
│   .git detection)        │                               │
└──────────────────────────┼───────────────────────────────┘
                           ▼
      ┌───────────────────────────────────────────┐
      │   External Binaries (User Environment)    │
      │  • spicetify (dynamic PATH resolution)    │
      │  • git (for .git-managed add-ons)         │
      │  • sh + curl (official Marketplace script)│
      └───────────────────────────────────────────┘
```

### 1.4 Sequence Flow: Update All Applicable
```text
User -> UI: Click "Update All Applicable"
UI -> SpicetifyManager: updateAllApplicable(items, category)
SpicetifyManager -> CommandRunner: if has(.builtIn) -> `spicetify upgrade`
SpicetifyManager -> CommandRunner: if has(.marketplace) -> official install.sh
SpicetifyManager -> CommandRunner: for unique gitRoot in .gitRepo -> `git -C <root> pull --ff-only`
CommandRunner -> SpicetifyManager: (exitCode, cleanedOutput) per step
SpicetifyManager -> DiagnosticMapper: diagnose(command, exitCode, output)
SpicetifyManager -> UI: update statusText, diagnosticHint, logOutput, hasPendingChanges = true
```

### 1.5 Alternatives Considered & Trade-Offs
| Option | Memory / Idle Power | Update Resilience | Decision |
| :--- | :--- | :--- | :--- |
| **Native SwiftUI + AppKit (`swiftc`)** | ~25 MB active / 0% idle | High (thin CLI wrapper) | **Selected** |
| Electron / Tauri | 150–400 MB active | High | Rejected (too heavy) |
| Local Python Web UI | ~40 MB + browser tab | Medium (server stays running) | Rejected (higher power + browser dependency) |
| Scraping GitHub for standalone `.js` updates | Low | Low (fragile heuristics, no canonical upstream) | Rejected (YAGNI; delegate to Marketplace or Git) |

---

## Zone 2: Detailed Range (Implementation Blueprint)

### 2.1 File Layout
All source and build files live inside `spicetify-gui-project/`:
* `spicetify-gui-project/concepts_brief.md` — Phase 1 brief (created).
* `spicetify-gui-project/docs/designs/spicetify-gui.md` — This specification.
* `spicetify-gui-project/src/SpicetifyGUI.swift` — Single-file macro-free SwiftUI + AppKit application source.
* `spicetify-gui-project/scripts/make_icon.swift` — CoreGraphics vector renderer generating all 10 Retina `.iconset` PNGs with explicit 72/144 DPI pixel metadata.
* `spicetify-gui-project/scripts/build.sh` — Reproducible build script that renders the icon, builds `AppIcon.icns`, compiles `SpicetifyGUI` (`swiftc -O -parse-as-library`), writes `Info.plist`, signs with `codesign --force --deep --sign -`, and verifies `NSImage` + `codesign --verify`.
* Output bundle: `build/SpicetifyGUI.app` by default (customizable via `--out`; copy to `/Applications/SpicetifyGUI.app`).

### 2.2 Icon Packaging Root-Cause Fix (Why Finder Showed a Generic Icon)
Two issues caused the missing Finder icon:
1. **ICNS Chunk Compatibility:** Packing `icp4`/`icp5` PNG chunks manually works for `NSImage`, but macOS Finder `IconServices` on newer macOS versions strictly expects standard `ic07` (128px), `ic08` (256px), `ic09` (512px), `ic10` (1024px), `ic11` (32px), `ic12` (64px), `ic13` (256px), `ic14` (512px) OR `iconutil` output (which failed earlier only because `NSBitmapImageRep` lacked explicit size/DPI alignment and sandbox `TMPDIR` was `/var/folders/...`).
2. **LaunchServices Cache Collision:** Replacing `/Applications/SpicetifyGUI.app` with an app sharing the same `CFBundleIdentifier` (`com.local.spicetify-gui`) often retains the cached generic icon until `CFBundleVersion` increments AND Finder/IconServices refreshes.

**Concrete Fix:**
* Omit `icp4`/`icp5` from the `.icns` container and include only the 8 standard PNG-native Apple OSTypes (`ic11`, `ic12`, `ic07`, `ic13`, `ic08`, `ic14`, `ic09`, `ic10`), OR use `sips`/`iconutil` when `TMPDIR=/tmp` succeeds — verify with both `file` and `NSWorkspace.shared.icon(forFile:)` in `build.sh`.
* Set `CFBundleIconFile` = `AppIcon` (no `.icns` suffix, per Apple Info.plist convention) and bump `CFBundleVersion` to `3` (`CFBundleShortVersionString` = `1.2`).
* Keep `AppIcon.png` in `Contents/Resources/` and set `NSApp.applicationIconImage` in `AppDelegate.applicationDidFinishLaunching` so the Dock and Cmd+Tab switcher always show the icon even before Finder's cache refreshes.
* Provide a one-line user command (`touch /Applications/SpicetifyGUI.app && killall Finder`) if Finder still displays a stale cached icon after dragging to `/Applications`.

### 2.3 Core Data Structures & Typed Signatures
```swift
enum ItemSource: String, Hashable, Sendable {
    case builtIn = "Built-in"       // Under ~/.spicetify/{Extensions,CustomApps} -> updated via `spicetify upgrade`
    case marketplace = "Marketplace"// CustomApp named "marketplace" -> official install.sh
    case gitRepo = "Git Repo"       // Contains .git directory -> `git -C <root> pull --ff-only`
    case local = "Local"            // Standalone file/folder with no upstream tracker
}

struct ManagedItem: Identifiable, Hashable, Sendable {
    let name: String
    let path: String?
    let source: ItemSource
    var id: String { name }
}

struct DiagnosticHint: Equatable, Sendable {
    let title: String
    let guidance: String
    let suggestedAction: SuggestedFix?
}

enum SuggestedFix: Equatable, Sendable {
    case backupApply
    case upgradeCLI
    case retry
}

struct CommandResult: Sendable {
    let exitCode: Int32
    let output: String
    let durationMs: Int
}
```

Key `SpicetifyManager` (`@MainActor`) method signatures:
* `func reloadAll() async` — Resolves binary path, queries `--version` and `-c`, parses `config-xpui.ini`, scans themes/extensions/custom apps.
* `func runCommand(_ args: [String], label: String, clearsPending: Bool = false, reloadAfter: Bool = false) async -> CommandResult`
* `func updateItem(_ item: ManagedItem) async` — Dispatches update strategy by `item.source`.
* `func updateAllApplicable(items: [ManagedItem], categoryLabel: String) async` — Deduplicates `spicetify upgrade`, `updateMarketplace()`, and unique `gitRoot` pulls; aggregates per-step outcomes into a clear summary status.
* `func diagnose(args: [String], result: CommandResult) -> DiagnosticHint?` — Matches common failure patterns in stderr/stdout.
* `func parseArguments(_ rawInput: String) -> [String]` — Shell-like quote-aware tokenizer for the Custom Command bar (handles quoted paths/values instead of naive whitespace splitting).

### 2.4 Error Handling, Fallbacks & Edge Cases
| Failure / Edge Case | Handling Strategy |
| :--- | :--- |
| **`spicetify` binary missing or moved after reinstall** | Re-resolve across `~/.spicetify/spicetify`, `/opt/homebrew/bin/spicetify`, `/usr/local/bin/spicetify`, and `/usr/bin/which spicetify` before every command. If still missing, disable CLI buttons and show clear install/path hint. |
| **Spotify updated and broke Spicetify patch** | `DiagnosticMapper` detects keywords (`backup`, `version mismatch`, `cannot find`, `outdated`) and surfaces an inline banner: *"Spotify may have updated — click Backup & Apply."* |
| **Offline / network failure during `upgrade`, `curl`, or `git pull`** | Show non-zero exit code + plain-English hint (*"Network request failed — check your internet connection"*) without corrupting local config. |
| **Dirty working tree in a Git-cloned add-on** | `git pull --ff-only` fails safely without overwriting user edits; `DiagnosticMapper` flags *"Local changes in `<name>` prevented fast-forward pull."* |
| **Process hangs or times out** | Enforce a 120-second watchdog timeout on child processes (`Process.terminate()`) so the UI can never lock permanently. |
| **Quoted arguments in Custom Command bar** | Quote-aware parser splits `"my theme"` as a single argument rather than two broken tokens. |
| **Special characters in Git paths** | Execute `/usr/bin/git` directly via `Process` with `arguments: ["-C", gitRoot, "pull", "--ff-only"]` (NO `/bin/sh -c` string interpolation — prevents shell injection / quoting bugs). |
| **Future deprecated config keys** | `saveAppearanceAndApply` computes a diff against `savedConfig` and passes only changed keys to `spicetify config`. |

### 2.5 Verification & Testing Strategy
1. **Build & Signature Verification (`build.sh`):**
   * `swiftc -O -parse-as-library` exits 0 with zero warnings.
   * `plutil -lint Contents/Info.plist` returns `OK`.
   * `codesign --verify --verbose=2 SpicetifyGUI.app` passes (`valid on disk`).
2. **Icon Verification:**
   * Swift verification check confirms `AppIcon.icns` decodes via `NSImage` with 8+ representations AND `NSWorkspace.shared.icon(forFile: appPath)` returns a non-generic custom icon image.
3. **Functional & Logic Tests (headless Swift test harness in `scripts/test_logic.swift`):**
   * INI parser ignores unknown future sections/keys and accurately parses `extensions` / `custom_apps` pipe lists.
   * Quote-aware argument parser handles single/double quotes and strips leading `spicetify`.
   * `DiagnosticMapper` accurately classifies Spotify mismatch, network error, and dirty git tree outputs.
   * `git` updater invokes `git` with array arguments (never shell interpolation).
4. **Power Verification:**
   * Confirm zero `Timer`, `DispatchSourceTimer`, or background `Task` loops exist in `SpicetifyGUI.swift`, and `applicationShouldTerminateAfterLastWindowClosed` returns `true`.

### 2.6 Goldfish Review Resolutions & Open-Source Portability (Approved)
1. **Non-Hanging Subprocesses & Marketplace Labeling:** Every child `Process` attaches `FileHandle.nullDevice` to `standardInput` so interactive prompts never hang, and enforces a 120-second watchdog timeout. **Update Marketplace** is explicitly labeled *"Updates Marketplace and restarts Spotify."*
2. **Native Apple Icon Pipeline:** `scripts/make_icon.swift` sets explicit point vs. pixel dimensions (`144 DPI` on `@2x` PNGs) so Apple's `iconutil` produces a strictly valid `AppIcon.icns`. `CFBundleVersion` bumps to `3` (`1.2`), `CFBundleIconFile` is `AppIcon`, and `AppDelegate` sets `NSApp.applicationIconImage` from `AppIcon.png` for guaranteed Dock/Cmd+Tab rendering.
3. **Aggregated Batch Update Reporting (`UpdateBatchResult`):**
   ```swift
   struct UpdateBatchResult: Sendable {
       var succeeded: [String] = []
       var failed: [String] = []
       var hasFailures: Bool { !failed.isEmpty }
   }
   ```
   `updateAllApplicable` tracks every step in `UpdateBatchResult` so an earlier failure is never masked by a later success.
4. **Dynamic `git` Resolution:** Resolve `git` via `PATH` (`/opt/homebrew/bin/git`, `/usr/local/bin/git`, `/usr/bin/git`, `which git`); if unavailable, disable Git Update actions with a clear tooltip.
5. **Open-Source Portability (Works for Everyone):**
   * Zero hardcoded user paths or usernames anywhere in source, scripts, or docs (`NSHomeDirectory()`, `SPICETIFY_INSTALL`, Homebrew Apple Silicon & Intel paths, and `PATH`).
   * Repository includes `README.md`, `LICENSE` (MIT), `.gitignore`, `src/SpicetifyGUI.swift`, `scripts/make_icon.swift`, `scripts/build.sh` (auto-detects `arm64`/`x86_64`, supports `--out <path>`), and `scripts/test_logic.swift`.
   * Works cleanly on both Apple Silicon and Intel Macs running macOS 14+.

