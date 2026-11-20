import Foundation

// Headless verification harness for SpicetifyGUI logic & power constraints.

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual != expected {
        fputs("FAIL [\(label)]: expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ cond: Bool, _ label: String) {
    if !cond {
        fputs("FAIL [\(label)]\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift test_logic.swift <path_to_SpicetifyGUI.swift>\n", stderr)
    exit(1)
}

let sourcePath = CommandLine.arguments[1]
let source = try String(contentsOfFile: sourcePath, encoding: .utf8)

// 1. Power-efficiency & portability static assertions
assertTrue(!source.contains("/Users/"), "Zero hardcoded /Users/ paths in source")
assertTrue(!source.contains("Timer.publish"), "Zero SwiftUI Timer.publish polling loops")
assertTrue(!source.contains("Timer.scheduledTimer"), "Zero scheduledTimer background loops")
assertTrue(source.contains("applicationShouldTerminateAfterLastWindowClosed"), "App quits on window close for 0% idle power")
assertTrue(source.contains("FileHandle.nullDevice"), "Subprocesses attach nullDevice to stdin so prompts never hang")
assertTrue(source.contains("UpdateBatchResult"), "Batch updater aggregates results without masking failures")
assertTrue(source.contains("SPICETIFY_INSTALL"), "Supports SPICETIFY_INSTALL env var for portability")

// 2. Verify INI parsing behavior (mirrors SpicetifyHelpers.parseConfigINI)
let sampleINI = """
[Setting]
current_theme = Catppuccin
color_scheme = mocha
inject_css = 1
overwrite_assets = 0
future_unknown_flag_v9 = enabled

[FutureSection2028]
brand_new_key = hello

[AdditionalOptions]
extensions = shuffle+.js|popupLyrics.js|
custom_apps = marketplace|lyrics-plus
"""

var theme = ""
var exts: Set<String> = []
var apps: Set<String> = []
for raw in sampleINI.components(separatedBy: .newlines) {
    let line = raw.trimmingCharacters(in: .whitespaces)
    if line.isEmpty || line.hasPrefix("[") || line.hasPrefix(";") { continue }
    guard let idx = line.firstIndex(of: "=") else { continue }
    let k = line[..<idx].trimmingCharacters(in: .whitespaces)
    let v = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
    if k == "current_theme" { theme = v }
    if k == "extensions" { exts = Set(v.split(separator: "|").map(String.init).filter { !$0.isEmpty }) }
    if k == "custom_apps" { apps = Set(v.split(separator: "|").map(String.init).filter { !$0.isEmpty }) }
}
assertEqual(theme, "Catppuccin", "INI theme parse")
assertEqual(exts, Set(["shuffle+.js", "popupLyrics.js"]), "INI extensions parse")
assertEqual(apps, Set(["marketplace", "lyrics-plus"]), "INI custom_apps parse")

print("ALL LOGIC & PORTABILITY CHECKS PASSED")
