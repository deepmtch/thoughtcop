// Paths, tunables, and .env-derived settings shared across the app.

import AppKit
import Foundation

let CLAUDE_PROJECTS = ("~/.claude/projects" as NSString).expandingTildeInPath
let CODEX_SESSIONS = ("~/.codex/sessions" as NSString).expandingTildeInPath
let CODEX_INDEX = ("~/.codex/session_index.jsonl" as NSString).expandingTildeInPath
let POLL = 0.2          // seconds between drains of active files
let RESCAN = 0.5        // seconds between discovering newly active sessions
let ACTIVE_HOURS = 12.0 // auto mode watches every transcript touched in this window
let API_PORT = UInt16(ProcessInfo.processInfo.environment["THINKPEEK_API_PORT"] ?? "17321") ?? 17321
let LOCAL_ONLY = CommandLine.arguments.contains("--local-only")
let INITIAL_TRANSCRIPT: String? = {
    guard let i = CommandLine.arguments.firstIndex(of: "--transcript"),
          i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}()

let BG = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
let FG = NSColor(srgbRed: 0.84, green: 0.86, blue: 0.89, alpha: 1)
let DIM = NSColor(srgbRed: 0.42, green: 0.45, blue: 0.52, alpha: 1)
let ACCENT = NSColor(srgbRed: 0.79, green: 0.64, blue: 0.15, alpha: 1)
let SEALED = NSColor(srgbRed: 0.48, green: 0.36, blue: 0.62, alpha: 1)
let ALERT = NSColor(srgbRed: 0.95, green: 0.33, blue: 0.31, alpha: 1)

/// Resolve the repository root for both supported launch artifacts:
/// `.build/thinkpeek` and `.build/Thinkpeek.app/Contents/MacOS/thinkpeek`.
func projectRoot(executablePath: String, appBundlePath: String?) -> String {
    if let appBundlePath,
       (appBundlePath as NSString).pathExtension == "app" {
        let buildDirectory = (appBundlePath as NSString).deletingLastPathComponent
        if (buildDirectory as NSString).lastPathComponent == ".build" {
            return (buildDirectory as NSString).deletingLastPathComponent
        }
    }
    let executableDirectory = ((executablePath as NSString).resolvingSymlinksInPath as NSString)
        .deletingLastPathComponent
    if (executableDirectory as NSString).lastPathComponent == ".build" {
        return (executableDirectory as NSString).deletingLastPathComponent
    }
    return executableDirectory
}

let PROJECT_ROOT: String = {
    let argv0 = CommandLine.arguments[0]
    let executablePath = Bundle.main.executablePath
        ?? (argv0.hasPrefix("/") ? argv0
            : FileManager.default.currentDirectoryPath + "/" + argv0)
    let appBundlePath = Bundle.main.bundleURL.pathExtension == "app"
        ? Bundle.main.bundlePath : nil
    return projectRoot(executablePath: executablePath,
                       appBundlePath: appBundlePath)
}()
let ENV_FILE = PROJECT_ROOT + "/.env"

/// Read one dotenv value without mutating the process environment. Existing
/// environment variables take precedence; otherwise use the repository `.env`.
func dotenv(_ name: String) -> String? {
    if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
        return value
    }
    guard let text = try? String(contentsOfFile: ENV_FILE, encoding: .utf8) else { return nil }
    for raw in text.components(separatedBy: .newlines) {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        if line.hasPrefix("export ") {
            line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard let equals = line.firstIndex(of: "=") else { continue }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard key == name else { continue }
        var value = String(line[line.index(after: equals)...])
            .trimmingCharacters(in: .whitespaces)
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"") ||
            value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst(); value.removeLast()
        }
        return value.isEmpty ? nil : value
    }
    return nil
}

let BACKFILL: Int = {
    guard let raw = dotenv("THINKPEEK_HISTORY_COUNT")?.lowercased() else { return 3 }
    if ["all", "unlimited", "infinite"].contains(raw) { return Int.max }
    return max(0, Int(raw) ?? 3)
}()
