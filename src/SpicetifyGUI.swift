import SwiftUI
import AppKit

// MARK: - Models

struct SpicetifyConfig: Equatable, Sendable {
    var currentTheme: String = ""
    var colorScheme: String = ""
    var injectCSS: Bool = true
    var injectThemeJS: Bool = true
    var replaceColors: Bool = true
    var overwriteAssets: Bool = false
    var sidebarConfig: Bool = true
    var homeConfig: Bool = true
    var enabledExtensions: Set<String> = []
    var enabledCustomApps: Set<String> = []
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case actions = "Quick Actions"
    case appearance = "Appearance"
    case extensions = "Extensions"
    case customApps = "Custom Apps"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .actions: return "bolt.fill"
        case .appearance: return "paintbrush.fill"
        case .extensions: return "puzzlepiece.extension.fill"
        case .customApps: return "square.grid.2x2.fill"
        }
    }
}

struct ThemeItem: Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let colorSchemes: [String]
    var id: String { name }
}

enum ItemSource: String, Hashable, Sendable {
    case builtIn = "Built-in"
    case marketplace = "Marketplace"
    case gitRepo = "Git Repo"
    case local = "Local"
}

struct ManagedItem: Identifiable, Hashable, Sendable {
    let name: String
    let path: String?
    let source: ItemSource
    var id: String { name }
}

struct CommandResult: Sendable {
    let exitCode: Int32
    let output: String
    let timedOut: Bool
}

enum SuggestedFix: Equatable, Sendable {
    case backupApply
    case restoreBackupApply
    case upgradeCLI
    case openAppManagement
}

struct DiagnosticHint: Equatable, Sendable {
    let title: String
    let guidance: String
    let suggestedFix: SuggestedFix?
}

struct UpdateBatchResult: Sendable {
    var succeeded: [String] = []
    var failed: [String] = []
    var hasFailures: Bool { !failed.isEmpty }
}

// MARK: - Pure Helpers (Testable & Portable)

enum SpicetifyHelpers {
    static func parseConfigINI(_ content: String) -> SpicetifyConfig {
        var parsed = SpicetifyConfig()
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") || line.hasPrefix("[") {
                continue
            }
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "current_theme":
                parsed.currentTheme = value
            case "color_scheme":
                parsed.colorScheme = value
            case "inject_css":
                parsed.injectCSS = (value == "1" || value.lowercased() == "true")
            case "inject_theme_js":
                parsed.injectThemeJS = (value == "1" || value.lowercased() == "true")
            case "replace_colors":
                parsed.replaceColors = (value == "1" || value.lowercased() == "true")
            case "overwrite_assets":
                parsed.overwriteAssets = (value == "1" || value.lowercased() == "true")
            case "sidebar_config":
                parsed.sidebarConfig = (value == "1" || value.lowercased() == "true")
            case "home_config":
                parsed.homeConfig = (value == "1" || value.lowercased() == "true")
            case "extensions":
                let items = value.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                parsed.enabledExtensions = Set(items)
            case "custom_apps":
                let items = value.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                parsed.enabledCustomApps = Set(items)
            default:
                break // Safely ignore unknown keys from future Spicetify versions
            }
        }
        return parsed
    }

    static func parseArguments(_ rawInput: String) -> [String] {
        var args: [String] = []
        var current = ""
        var activeQuote: Character? = nil
        var escaping = false

        for ch in rawInput {
            if escaping {
                current.append(ch)
                escaping = false
                continue
            }
            if ch == "\\" && activeQuote != "'" {
                escaping = true
                continue
            }
            if let quote = activeQuote {
                if ch == quote {
                    activeQuote = nil
                } else {
                    current.append(ch)
                }
            } else {
                if ch == "\"" || ch == "'" {
                    activeQuote = ch
                } else if ch.isWhitespace {
                    if !current.isEmpty {
                        args.append(current)
                        current = ""
                    }
                } else {
                    current.append(ch)
                }
            }
        }
        if !current.isEmpty {
            args.append(current)
        }
        if args.first == "spicetify" {
            return Array(args.dropFirst())
        }
        return args
    }

    static func diagnose(result: CommandResult) -> DiagnosticHint? {
        let lower = result.output.lowercased()

        // Check warning-level existing-backup message even if Spicetify exits 0.
        if lower.contains("restore first then backup") || lower.contains("spicetify restore backup") {
            return DiagnosticHint(
                title: "A backup already exists",
                guidance: "Run Restore, Backup & Apply for a clean re-backup, or use Apply for normal changes.",
                suggestedFix: .restoreBackupApply
            )
        }

        guard result.exitCode != 0 else { return nil }
        if result.timedOut {
            return DiagnosticHint(
                title: "Command timed out",
                guidance: "The process did not finish within 120 seconds and was stopped safely.",
                suggestedFix: nil
            )
        }
        if lower.contains("app management") || lower.contains("cannot write to spotify") || lower.contains("operation not permitted") {
            return DiagnosticHint(
                title: "macOS App Management permission required",
                guidance: "Allow Spicetify GUI in System Settings → Privacy & Security → App Management, then quit and reopen this app.",
                suggestedFix: .openAppManagement
            )
        }
        if lower.contains("backup") || (lower.contains("version") && lower.contains("mismatch")) || lower.contains("spotify has been updated") || lower.contains("cannot apply") {
            return DiagnosticHint(
                title: "Spotify may have updated",
                guidance: "Run Backup & Apply to re-sync Spicetify with your current Spotify version.",
                suggestedFix: .backupApply
            )
        }
        if lower.contains("could not resolve host") || lower.contains("failed to connect") || lower.contains("network is unreachable") || lower.contains("no such host") {
            return DiagnosticHint(
                title: "Network error",
                guidance: "Check your internet connection and try again.",
                suggestedFix: nil
            )
        }
        if lower.contains("not possible to fast-forward") || lower.contains("local changes") || lower.contains("overwritten by merge") {
            return DiagnosticHint(
                title: "Local Git edits blocked update",
                guidance: "Fast-forward pull stopped safely so your local edits were not overwritten.",
                suggestedFix: nil
            )
        }
        if lower.contains("outdated") || lower.contains("upgrade") {
            return DiagnosticHint(
                title: "Spicetify CLI may be outdated",
                guidance: "Try upgrading Spicetify CLI, then run Backup & Apply.",
                suggestedFix: .upgradeCLI
            )
        }
        return nil
    }

    static func stripANSI(_ string: String) -> String {
        string.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}

// MARK: - App Delegate (0% idle power on close + guaranteed Dock icon)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let pngPath = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let icon = NSImage(contentsOfFile: pngPath) {
            NSApp.applicationIconImage = icon
        } else if let icnsPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
                  let icon = NSImage(contentsOfFile: icnsPath) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Spicetify Controller

@MainActor
final class SpicetifyManager: ObservableObject {
    @Published var binaryPath: String = ""
    @Published var gitBinaryPath: String? = nil
    @Published var configPath: String = ""
    @Published var cliVersion: String = "Checking..."
    @Published var cliFound: Bool = true
    @Published var config = SpicetifyConfig()
    @Published var availableThemes: [ThemeItem] = []
    @Published var availableExtensions: [ManagedItem] = []
    @Published var availableCustomApps: [ManagedItem] = []
    @Published var isRunning: Bool = false
    @Published var hasPendingChanges: Bool = false
    @Published var statusText: String = "Ready"
    @Published var statusIsError: Bool = false
    @Published var diagnosticHint: DiagnosticHint? = nil
    @Published var logOutput: String = ""

    // UI State
    @Published var selectedTab: SidebarTab = .actions
    @Published var showLog: Bool = true
    @Published var extensionSearchText: String = ""
    @Published var customCommandText: String = ""

    private var savedConfig = SpicetifyConfig()
    private let homeDir: String = NSHomeDirectory()

    init() {
        binaryPath = resolveBinaryPath()
        gitBinaryPath = resolveGitBinaryPath()
        Task {
            await reloadAll()
        }
    }

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var extraPaths = [
            "\(homeDir)/.spicetify",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        if let customInstall = env["SPICETIFY_INSTALL"], !customInstall.isEmpty {
            extraPaths.insert(customInstall, at: 0)
        }
        let existing = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + (existing.isEmpty ? [] : [existing])).joined(separator: ":")
        env["HOME"] = homeDir
        return env
    }

    private func resolveBinaryPath() -> String {
        let env = buildEnvironment()
        var candidates: [String] = []
        if let customInstall = env["SPICETIFY_INSTALL"], !customInstall.isEmpty {
            candidates.append((customInstall as NSString).appendingPathComponent("spicetify"))
        }
        candidates += [
            "\(homeDir)/.spicetify/spicetify",
            "/opt/homebrew/bin/spicetify",
            "/usr/local/bin/spicetify"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let res = Self.executeProcess(
            executable: "/usr/bin/which",
            arguments: ["spicetify"],
            environment: env,
            timeoutSeconds: 10
        )
        let resolved = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if res.exitCode == 0, !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) {
            return resolved
        }
        return "\(homeDir)/.spicetify/spicetify"
    }

    private func resolveGitBinaryPath() -> String? {
        let env = buildEnvironment()
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let res = Self.executeProcess(
            executable: "/usr/bin/which",
            arguments: ["git"],
            environment: env,
            timeoutSeconds: 10
        )
        let resolved = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if res.exitCode == 0, !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) {
            return resolved
        }
        return nil
    }

    nonisolated private static func executeProcess(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: Double = 120
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice // Prevents interactive prompts from hanging

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, output: "Failed to launch \(executable): \(error.localizedDescription)", timedOut: false)
        }

        let timedOutLock = NSLock()
        var didTimeout = false
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler {
            if process.isRunning {
                timedOutLock.lock()
                didTimeout = true
                timedOutLock.unlock()
                process.terminate()
            }
        }
        timer.resume()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()

        timedOutLock.lock()
        let wasTimeout = didTimeout
        timedOutLock.unlock()

        let text = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(exitCode: wasTimeout ? -2 : process.terminationStatus, output: text, timedOut: wasTimeout)
    }

    func reloadAll() async {
        binaryPath = resolveBinaryPath()
        gitBinaryPath = resolveGitBinaryPath()
        let bin = binaryPath
        let env = buildEnvironment()

        guard FileManager.default.isExecutableFile(atPath: bin) else {
            cliFound = false
            cliVersion = "Not found"
            statusText = "Spicetify CLI not found"
            statusIsError = true
            diagnosticHint = DiagnosticHint(
                title: "Spicetify CLI not detected",
                guidance: "Install Spicetify CLI from spicetify.app (via official script or Homebrew), then click Refresh.",
                suggestedFix: nil
            )
            return
        }

        cliFound = true
        let verRes = await Task.detached {
            Self.executeProcess(executable: bin, arguments: ["--version"], environment: env, timeoutSeconds: 15)
        }.value
        let cleanedVer = SpicetifyHelpers.stripANSI(verRes.output).trimmingCharacters(in: .whitespacesAndNewlines)
        cliVersion = (verRes.exitCode == 0 && !cleanedVer.isEmpty) ? cleanedVer : "Unknown"

        let cfgRes = await Task.detached {
            Self.executeProcess(executable: bin, arguments: ["-c"], environment: env, timeoutSeconds: 15)
        }.value
        let candidateCfg = SpicetifyHelpers.stripANSI(cfgRes.output).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackCfg = "\(homeDir)/.config/spicetify/config-xpui.ini"
        let resolvedCfg = (cfgRes.exitCode == 0 && !candidateCfg.isEmpty && FileManager.default.fileExists(atPath: candidateCfg))
            ? candidateCfg
            : fallbackCfg
        configPath = resolvedCfg

        parseConfigFile(at: resolvedCfg)
        scanInstalledItems()
        statusText = "Ready"
        statusIsError = false
        diagnosticHint = nil
    }

    private func parseConfigFile(at path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let parsed = SpicetifyHelpers.parseConfigINI(content)
        config = parsed
        savedConfig = parsed
    }

    private func findGitRoot(startingAt path: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        let dir = isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent(".git")) {
            return dir
        }
        return nil
    }

    private func scanInstalledItems() {
        let fm = FileManager.default
        let configDir = (configPath as NSString).deletingLastPathComponent
        let binDir = (binaryPath as NSString).deletingLastPathComponent
        let userDirs = Array(Set([configDir, "\(homeDir)/.config/spicetify"]))
        let builtInDirs = Array(Set([binDir, "\(homeDir)/.spicetify"]))
        let allBaseDirs = Array(Set(userDirs + builtInDirs))

        // Themes
        var themeMap: [String: ThemeItem] = [:]
        for base in allBaseDirs {
            let themesDir = (base as NSString).appendingPathComponent("Themes")
            guard let entries = try? fm.contentsOfDirectory(atPath: themesDir) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let fullPath = (themesDir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    let schemes = parseColorSchemes(inThemeDir: fullPath)
                    if themeMap[entry] == nil || !schemes.isEmpty {
                        themeMap[entry] = ThemeItem(name: entry, path: fullPath, colorSchemes: schemes)
                    }
                }
            }
        }
        availableThemes = themeMap.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Extensions
        var extMap: [String: ManagedItem] = [:]
        for base in builtInDirs {
            let extDir = (base as NSString).appendingPathComponent("Extensions")
            guard let entries = try? fm.contentsOfDirectory(atPath: extDir) else { continue }
            for entry in entries where entry.hasSuffix(".js") && !entry.hasPrefix(".") {
                let fullPath = (extDir as NSString).appendingPathComponent(entry)
                extMap[entry] = ManagedItem(name: entry, path: fullPath, source: .builtIn)
            }
        }
        for base in userDirs {
            let extDir = (base as NSString).appendingPathComponent("Extensions")
            guard let entries = try? fm.contentsOfDirectory(atPath: extDir) else { continue }
            for entry in entries where entry.hasSuffix(".js") && !entry.hasPrefix(".") {
                let fullPath = (extDir as NSString).appendingPathComponent(entry)
                let src: ItemSource = (findGitRoot(startingAt: fullPath) != nil) ? .gitRepo : .local
                extMap[entry] = ManagedItem(name: entry, path: fullPath, source: src)
            }
        }
        for enabled in config.enabledExtensions where extMap[enabled] == nil {
            extMap[enabled] = ManagedItem(name: enabled, path: nil, source: .local)
        }
        availableExtensions = extMap.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Custom Apps
        var appMap: [String: ManagedItem] = [:]
        for base in builtInDirs {
            let appDir = (base as NSString).appendingPathComponent("CustomApps")
            guard let entries = try? fm.contentsOfDirectory(atPath: appDir) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let fullPath = (appDir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    appMap[entry] = ManagedItem(name: entry, path: fullPath, source: .builtIn)
                }
            }
        }
        for base in userDirs {
            let appDir = (base as NSString).appendingPathComponent("CustomApps")
            guard let entries = try? fm.contentsOfDirectory(atPath: appDir) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let fullPath = (appDir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    let src: ItemSource
                    if entry.lowercased() == "marketplace" {
                        src = .marketplace
                    } else if findGitRoot(startingAt: fullPath) != nil {
                        src = .gitRepo
                    } else {
                        src = .local
                    }
                    appMap[entry] = ManagedItem(name: entry, path: fullPath, source: src)
                }
            }
        }
        for enabled in config.enabledCustomApps where appMap[enabled] == nil {
            let src: ItemSource = enabled.lowercased() == "marketplace" ? .marketplace : .local
            appMap[enabled] = ManagedItem(name: enabled, path: nil, source: src)
        }
        availableCustomApps = appMap.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseColorSchemes(inThemeDir dir: String) -> [String] {
        let colorIni = (dir as NSString).appendingPathComponent("color.ini")
        guard let content = try? String(contentsOfFile: colorIni, encoding: .utf8) else { return [] }
        var schemes: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") && line.count > 2 {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    schemes.append(name)
                }
            }
        }
        return schemes
    }

    func schemesForSelectedTheme() -> [String] {
        availableThemes.first(where: { $0.name == config.currentTheme })?.colorSchemes ?? []
    }

    @discardableResult
    func runCommand(_ args: [String], label: String, clearsPending: Bool = false, reloadAfter: Bool = false) async -> CommandResult {
        guard !isRunning else {
            return CommandResult(exitCode: -1, output: "Another command is already running.", timedOut: false)
        }
        binaryPath = resolveBinaryPath()
        let bin = binaryPath
        let env = buildEnvironment()

        isRunning = true
        statusText = "\(label)..."
        statusIsError = false
        diagnosticHint = nil
        appendLog("$ spicetify \(args.joined(separator: " "))")

        let result = await Task.detached {
            Self.executeProcess(executable: bin, arguments: args, environment: env)
        }.value

        let cleaned = SpicetifyHelpers.stripANSI(result.output).trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            appendLog(cleaned)
        }

        isRunning = false
        let detectedHint = SpicetifyHelpers.diagnose(result: result)
        if result.exitCode == 0 {
            statusText = detectedHint != nil ? "\(label) completed with a warning" : "\(label) succeeded"
            statusIsError = false
            diagnosticHint = detectedHint
            if clearsPending && detectedHint == nil {
                hasPendingChanges = false
            }
        } else {
            statusText = result.timedOut ? "\(label) timed out" : "\(label) failed (exit \(result.exitCode))"
            statusIsError = true
            diagnosticHint = detectedHint
        }

        if reloadAfter {
            await reloadAll()
        } else {
            parseConfigFile(at: configPath)
            scanInstalledItems()
        }
        return result
    }

    @discardableResult
    private func runExecutable(_ executable: String, args: [String], displayCommand: String, label: String, reloadAfter: Bool = false) async -> CommandResult {
        guard !isRunning else {
            return CommandResult(exitCode: -1, output: "Another command is already running.", timedOut: false)
        }
        let env = buildEnvironment()

        isRunning = true
        statusText = "\(label)..."
        statusIsError = false
        diagnosticHint = nil
        appendLog("$ \(displayCommand)")

        let result = await Task.detached {
            Self.executeProcess(executable: executable, arguments: args, environment: env)
        }.value

        let cleaned = SpicetifyHelpers.stripANSI(result.output).trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            appendLog(cleaned)
        }

        isRunning = false
        if result.exitCode == 0 {
            statusText = "\(label) succeeded"
            statusIsError = false
            diagnosticHint = nil
        } else {
            statusText = result.timedOut ? "\(label) timed out" : "\(label) failed (exit \(result.exitCode))"
            statusIsError = true
            diagnosticHint = SpicetifyHelpers.diagnose(result: result)
        }

        if reloadAfter {
            await reloadAll()
        }
        return result
    }

    @discardableResult
    func updateMarketplace(reloadAfter: Bool = true) async -> CommandResult {
        let cmd = "curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh"
        return await runExecutable("/bin/sh", args: ["-c", cmd], displayCommand: cmd, label: "Update Marketplace", reloadAfter: reloadAfter)
    }

    @discardableResult
    private func runGitPull(gitRoot: String, itemName: String, reloadAfter: Bool) async -> CommandResult {
        guard let gitBin = gitBinaryPath ?? resolveGitBinaryPath() else {
            let res = CommandResult(exitCode: -1, output: "git executable not found in PATH.", timedOut: false)
            statusText = "Git not found"
            statusIsError = true
            appendLog(res.output)
            return res
        }
        return await runExecutable(
            gitBin,
            args: ["-C", gitRoot, "pull", "--ff-only"],
            displayCommand: "git -C \"\(gitRoot)\" pull --ff-only",
            label: "Update \(itemName)",
            reloadAfter: reloadAfter
        )
    }

    func updateItem(_ item: ManagedItem) async {
        switch item.source {
        case .builtIn:
            let res = await runCommand(["upgrade"], label: "Upgrade CLI & Built-ins", reloadAfter: true)
            if res.exitCode == 0 { hasPendingChanges = true }
        case .marketplace:
            _ = await updateMarketplace(reloadAfter: true)
        case .gitRepo:
            guard let path = item.path, let gitRoot = findGitRoot(startingAt: path) else { return }
            let res = await runGitPull(gitRoot: gitRoot, itemName: item.name, reloadAfter: true)
            if res.exitCode == 0 { hasPendingChanges = true }
        case .local:
            break
        }
    }

    func updateAllApplicable(items: [ManagedItem], categoryLabel: String) async {
        guard !isRunning else { return }
        var batch = UpdateBatchResult()

        if items.contains(where: { $0.source == .builtIn }) {
            let res = await runCommand(["upgrade"], label: "Upgrade CLI & Built-in \(categoryLabel)", reloadAfter: false)
            if res.exitCode == 0 { batch.succeeded.append("Built-in \(categoryLabel)") } else { batch.failed.append("Built-in \(categoryLabel)") }
        }

        if items.contains(where: { $0.source == .marketplace }) {
            let res = await updateMarketplace(reloadAfter: false)
            if res.exitCode == 0 { batch.succeeded.append("Marketplace") } else { batch.failed.append("Marketplace") }
        }

        let gitItems = items.filter { $0.source == .gitRepo }
        var pulledRoots: Set<String> = []
        for item in gitItems {
            if let path = item.path, let root = findGitRoot(startingAt: path), !pulledRoots.contains(root) {
                pulledRoots.insert(root)
                let res = await runGitPull(gitRoot: root, itemName: item.name, reloadAfter: false)
                if res.exitCode == 0 { batch.succeeded.append(item.name) } else { batch.failed.append(item.name) }
            }
        }

        if !batch.succeeded.isEmpty {
            hasPendingChanges = true
        }
        parseConfigFile(at: configPath)
        scanInstalledItems()

        // Preserve aggregated batch status so an earlier failure is never masked by a later success.
        if batch.hasFailures {
            statusIsError = true
            statusText = "Update finished with failures: \(batch.failed.joined(separator: ", "))"
        } else if !batch.succeeded.isEmpty {
            statusIsError = false
            statusText = "Updated: \(batch.succeeded.joined(separator: ", "))"
        } else {
            statusIsError = false
            statusText = "No updatable \(categoryLabel.lowercased()) found"
        }
    }

    func runCustomCommand() async {
        let args = SpicetifyHelpers.parseArguments(customCommandText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !args.isEmpty else { return }
        _ = await runCommand(args, label: "Custom Command", reloadAfter: true)
    }

    func saveAppearanceAndApply(applyAfter: Bool) async {
        var pairs: [(String, String)] = []
        if config.currentTheme != savedConfig.currentTheme {
            pairs.append(("current_theme", config.currentTheme))
        }
        if config.colorScheme != savedConfig.colorScheme {
            pairs.append(("color_scheme", config.colorScheme))
        }
        if config.injectCSS != savedConfig.injectCSS {
            pairs.append(("inject_css", config.injectCSS ? "1" : "0"))
        }
        if config.injectThemeJS != savedConfig.injectThemeJS {
            pairs.append(("inject_theme_js", config.injectThemeJS ? "1" : "0"))
        }
        if config.replaceColors != savedConfig.replaceColors {
            pairs.append(("replace_colors", config.replaceColors ? "1" : "0"))
        }
        if config.overwriteAssets != savedConfig.overwriteAssets {
            pairs.append(("overwrite_assets", config.overwriteAssets ? "1" : "0"))
        }
        if config.sidebarConfig != savedConfig.sidebarConfig {
            pairs.append(("sidebar_config", config.sidebarConfig ? "1" : "0"))
        }
        if config.homeConfig != savedConfig.homeConfig {
            pairs.append(("home_config", config.homeConfig ? "1" : "0"))
        }

        if !pairs.isEmpty {
            var args: [String] = ["config"]
            for (k, v) in pairs {
                args.append(k)
                args.append(v)
            }
            let res = await runCommand(args, label: "Save Appearance")
            if res.exitCode == 0 {
                hasPendingChanges = true
            } else {
                return
            }
        }

        if applyAfter {
            _ = await runCommand(["apply"], label: "Apply Changes", clearsPending: true)
        }
    }

    func toggleExtension(_ name: String, enabled: Bool) async {
        let arg = enabled ? name : "\(name)-"
        let res = await runCommand(["config", "extensions", arg], label: enabled ? "Enable \(name)" : "Disable \(name)")
        if res.exitCode == 0 { hasPendingChanges = true }
    }

    func toggleCustomApp(_ name: String, enabled: Bool) async {
        let arg = enabled ? name : "\(name)-"
        let res = await runCommand(["config", "custom_apps", arg], label: enabled ? "Enable \(name)" : "Disable \(name)")
        if res.exitCode == 0 { hasPendingChanges = true }
    }

    func openConfigFolder() {
        let dir = (configPath as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    func openAppManagementSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
            NSWorkspace.shared.open(url)
        }
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logOutput, forType: .string)
    }

    func clearLog() {
        logOutput = ""
    }

    private func appendLog(_ text: String) {
        if logOutput.isEmpty {
            logOutput = text
        } else {
            logOutput += "\n" + text
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @ObservedObject var manager: SpicetifyManager

    private var appIconImage: NSImage? {
        if let pngPath = Bundle.main.path(forResource: "AppIcon", ofType: "png") {
            return NSImage(contentsOfFile: pngPath)
        }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarTab.allCases, selection: $manager.selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 175, ideal: 195, max: 225)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    if let img = appIconImage {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Text("Spicetify GUI")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("Spicetify v\(manager.cliVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Config Folder") {
                        manager.openConfigFolder()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                if let hint = manager.diagnosticHint {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hint.title)
                                .font(.callout.bold())
                            Text(hint.guidance)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        switch hint.suggestedFix {
                        case .openAppManagement:
                            Button("Open App Management Settings") {
                                manager.openAppManagementSettings()
                            }
                            .buttonStyle(.borderedProminent)
                        case .restoreBackupApply:
                            Button("Restore, Backup & Apply") {
                                Task { await manager.runCommand(["restore", "backup", "apply"], label: "Restore, Backup & Apply", clearsPending: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manager.isRunning)
                        case .backupApply:
                            Button("Backup & Apply") {
                                Task { await manager.runCommand(["backup", "apply"], label: "Backup & Apply", clearsPending: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manager.isRunning)
                        case .upgradeCLI:
                            Button("Upgrade CLI") {
                                Task { await manager.runCommand(["upgrade"], label: "Upgrade CLI", reloadAfter: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manager.isRunning)
                        case nil:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.10))
                    Divider()
                } else if manager.hasPendingChanges {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("You have updated or changed items that are not applied to Spotify yet.")
                            .font(.callout)
                        Spacer()
                        Button("Apply Now") {
                            Task { await manager.runCommand(["apply"], label: "Apply Changes", clearsPending: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.isRunning)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.12))
                    Divider()
                }

                Group {
                    switch manager.selectedTab {
                    case .actions:
                        QuickActionsView(manager: manager)
                    case .appearance:
                        AppearanceView(manager: manager)
                    case .extensions:
                        ExtensionsView(manager: manager)
                    case .customApps:
                        CustomAppsView(manager: manager)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        if manager.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Circle()
                                .fill(manager.statusIsError ? Color.red : Color.green)
                                .frame(width: 8, height: 8)
                        }
                        Text(manager.statusText)
                            .font(.caption)
                            .foregroundStyle(manager.statusIsError ? .red : .secondary)
                            .lineLimit(1)
                        Spacer()
                        if manager.showLog && !manager.logOutput.isEmpty {
                            Button("Copy") { manager.copyLog() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            Button("Clear") { manager.clearLog() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        Button(manager.showLog ? "Hide Log" : "Show Log") {
                            manager.showLog.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.bar)

                    if manager.showLog {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(manager.logOutput.isEmpty ? "Command output will appear here." : manager.logOutput)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(manager.logOutput.isEmpty ? .tertiary : .primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .id("logBottom")
                            }
                            .frame(height: 135)
                            .background(Color(nsColor: .textBackgroundColor))
                            .onChange(of: manager.logOutput) {
                                proxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await manager.reloadAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isRunning)
                .help("Reload config and installed items")
            }
        }
    }
}

struct QuickActionsView: View {
    @ObservedObject var manager: SpicetifyManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Actions")
                        .font(.title2.bold())
                    Text("Run common Spicetify commands with one click.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ActionCard(
                        title: "Apply",
                        subtitle: "Apply your current theme, extensions, and apps to Spotify.",
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        disabled: manager.isRunning || !manager.cliFound
                    ) {
                        Task { await manager.runCommand(["apply"], label: "Apply", clearsPending: true) }
                    }

                    ActionCard(
                        title: "Backup & Apply",
                        subtitle: "Initial backup and apply, or after a Spotify update.",
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        tint: .blue,
                        disabled: manager.isRunning || !manager.cliFound
                    ) {
                        Task { await manager.runCommand(["backup", "apply"], label: "Backup & Apply", clearsPending: true) }
                    }

                    ActionCard(
                        title: "Restore, Backup & Apply",
                        subtitle: "Clean reset when a backup already exists.",
                        icon: "arrow.clockwise.circle.fill",
                        tint: .indigo,
                        disabled: manager.isRunning || !manager.cliFound
                    ) {
                        Task { await manager.runCommand(["restore", "backup", "apply"], label: "Restore, Backup & Apply", clearsPending: true) }
                    }

                    ActionCard(
                        title: "Upgrade CLI & Built-ins",
                        subtitle: "Update Spicetify CLI plus built-in extensions and apps.",
                        icon: "arrow.up.circle.fill",
                        tint: .purple,
                        disabled: manager.isRunning || !manager.cliFound
                    ) {
                        Task { await manager.runCommand(["upgrade"], label: "Upgrade CLI", reloadAfter: true) }
                    }

                    ActionCard(
                        title: "Update Marketplace",
                        subtitle: "Updates Marketplace and restarts Spotify.",
                        icon: "bag.circle.fill",
                        tint: .pink,
                        disabled: manager.isRunning || !manager.cliFound
                    ) {
                        Task { await manager.updateMarketplace() }
                    }

                    ActionCard(
                        title: "Restart Spotify",
                        subtitle: "Relaunch Spotify to reload customizations.",
                        icon: "play.circle.fill",
                        tint: .teal,
                        disabled: manager.isRunning || !manager.cliFound
                    ) {
                        Task { await manager.runCommand(["restart"], label: "Restart Spotify") }
                    }

                    ActionCard(
                        title: "Restore Stock Spotify",
                        subtitle: "Undo Spicetify patches and restore original Spotify.",
                        icon: "arrow.uturn.backward.circle.fill",
                        tint: .orange,
                        disabled: manager.isRunning || !manager.cliFound
                    ) {
                        Task { await manager.runCommand(["restore"], label: "Restore Spotify") }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Run Any Spicetify Command")
                        .font(.headline)
                    Text("Future-proof fallback for any new CLI flags added in later Spicetify updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. enable-devtools  or  config current_theme \"My Theme\"", text: $manager.customCommandText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await manager.runCustomCommand() }
                            }
                        Button("Run") {
                            Task { await manager.runCustomCommand() }
                        }
                        .disabled(manager.isRunning || !manager.cliFound || manager.customCommandText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(20)
        }
    }
}

struct ActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1.0)
    }
}

struct AppearanceView: View {
    @ObservedObject var manager: SpicetifyManager

    var body: some View {
        Form {
            Section("Theme & Colors") {
                Picker("Theme", selection: $manager.config.currentTheme) {
                    Text("None (Default / Marketplace)").tag("")
                    ForEach(manager.availableThemes) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                .onChange(of: manager.config.currentTheme) {
                    let schemes = manager.schemesForSelectedTheme()
                    if !schemes.contains(manager.config.colorScheme) {
                        manager.config.colorScheme = schemes.first ?? ""
                    }
                }

                let schemes = manager.schemesForSelectedTheme()
                if !schemes.isEmpty {
                    Picker("Color Scheme", selection: $manager.config.colorScheme) {
                        Text("Default").tag("")
                        ForEach(schemes, id: \.self) { scheme in
                            Text(scheme).tag(scheme)
                        }
                    }
                } else {
                    TextField("Color Scheme (optional)", text: $manager.config.colorScheme)
                }
            }

            Section("Rendering Options") {
                Toggle("Inject CSS", isOn: $manager.config.injectCSS)
                Toggle("Inject Theme JS", isOn: $manager.config.injectThemeJS)
                Toggle("Replace Colors", isOn: $manager.config.replaceColors)
                Toggle("Overwrite Assets", isOn: $manager.config.overwriteAssets)
                Toggle("Custom Sidebar Config", isOn: $manager.config.sidebarConfig)
                Toggle("Custom Home Config", isOn: $manager.config.homeConfig)
            }

            Section {
                HStack {
                    Button("Save Config Only") {
                        Task { await manager.saveAppearanceAndApply(applyAfter: false) }
                    }
                    .disabled(manager.isRunning || !manager.cliFound)

                    Button("Save & Apply") {
                        Task { await manager.saveAppearanceAndApply(applyAfter: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isRunning || !manager.cliFound)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SourceBadge: View {
    let source: ItemSource

    private var tint: Color {
        switch source {
        case .builtIn: return .blue
        case .marketplace: return .pink
        case .gitRepo: return .purple
        case .local: return .secondary
        }
    }

    var body: some View {
        Text(source.rawValue)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

struct ExtensionsView: View {
    @ObservedObject var manager: SpicetifyManager

    private var filtered: [ManagedItem] {
        if manager.extensionSearchText.isEmpty { return manager.availableExtensions }
        return manager.availableExtensions.filter { $0.name.localizedCaseInsensitiveContains(manager.extensionSearchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extensions")
                        .font(.title2.bold())
                    Text("Built-in extensions update via CLI upgrade; Git repos pull directly; Marketplace items update inside Spotify.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Update Applicable") {
                    Task { await manager.updateAllApplicable(items: manager.availableExtensions, categoryLabel: "Extensions") }
                }
                .disabled(manager.isRunning || !manager.cliFound)
                TextField("Filter...", text: $manager.extensionSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
            .padding(16)

            Divider()

            List(filtered) { item in
                HStack(spacing: 10) {
                    Text(item.name)
                        .font(.body)
                    SourceBadge(source: item.source)
                    Spacer()
                    if item.source == .gitRepo {
                        Button("Update") {
                            Task { await manager.updateItem(item) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(manager.isRunning || manager.gitBinaryPath == nil)
                        .help(manager.gitBinaryPath == nil ? "Git is not installed" : "Run git pull --ff-only")
                    }
                    Toggle("", isOn: Binding(
                        get: { manager.config.enabledExtensions.contains(item.name) },
                        set: { newValue in
                            Task { await manager.toggleExtension(item.name, enabled: newValue) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(manager.isRunning || !manager.cliFound)
                }
            }
        }
    }
}

struct CustomAppsView: View {
    @ObservedObject var manager: SpicetifyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom Apps")
                        .font(.title2.bold())
                    Text("Toggle and update Marketplace, Git-cloned, and built-in Spotify sidebar apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Update All Applicable") {
                    Task { await manager.updateAllApplicable(items: manager.availableCustomApps, categoryLabel: "Custom Apps") }
                }
                .disabled(manager.isRunning || !manager.cliFound)
            }
            .padding(16)

            Divider()

            List(manager.availableCustomApps) { item in
                HStack(spacing: 10) {
                    Text(item.name)
                        .font(.body)
                    SourceBadge(source: item.source)
                    Spacer()
                    if item.source == .marketplace {
                        Button("Update") {
                            Task { await manager.updateItem(item) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(manager.isRunning || !manager.cliFound)
                        .help("Updates Marketplace and restarts Spotify")
                    } else if item.source == .gitRepo {
                        Button("Update") {
                            Task { await manager.updateItem(item) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(manager.isRunning || manager.gitBinaryPath == nil)
                        .help(manager.gitBinaryPath == nil ? "Git is not installed" : "Run git pull --ff-only")
                    }
                    Toggle("", isOn: Binding(
                        get: { manager.config.enabledCustomApps.contains(item.name) },
                        set: { newValue in
                            Task { await manager.toggleCustomApp(item.name, enabled: newValue) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(manager.isRunning || !manager.cliFound)
                }
            }
        }
    }
}

// MARK: - App Entry Point

@main
struct SpicetifyGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let manager = SpicetifyManager()

    var body: some Scene {
        WindowGroup("Spicetify GUI") {
            ContentView(manager: manager)
                .frame(minWidth: 700, minHeight: 520)
        }
        .defaultSize(width: 820, height: 620)
    }
}
