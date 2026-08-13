// The single local source of truth for the user's evaluation instruction.

import Foundation

enum CheckInstructionMode: String, CaseIterable {
    case wholeText
    case eachLine

    var title: String {
        switch self {
        case .wholeText: return "Whole text is one instruction"
        case .eachLine: return "Each non-empty line is independent"
        }
    }
}

enum CheckRulesStore {
    static let suiteName = "com.thinkpeek.app"
    static let defaultsKey = "runtimeCheckRules"
    static let modeKey = "runtimeCheckInstructionMode"
    static let defaultValue = "Claude is confused or waiting for user to do someting.\n"
    static let localDefaults = UserDefaults(suiteName: suiteName)!

    static func loadRaw() -> String {
        loadRaw(defaults: localDefaults)
    }

    static func loadRaw(defaults: UserDefaults) -> String {
        defaults.string(forKey: defaultsKey) ?? defaultValue
    }

    static func instruction() -> String {
        instruction(defaults: localDefaults)
    }

    static func instruction(defaults: UserDefaults) -> String {
        loadRaw(defaults: defaults)
    }

    static func mode() -> CheckInstructionMode {
        mode(defaults: localDefaults)
    }

    static func mode(defaults: UserDefaults) -> CheckInstructionMode {
        guard let raw = defaults.string(forKey: modeKey),
              let saved = CheckInstructionMode(rawValue: raw) else {
            // Existing text was authored under the previous editor's explicit
            // “one rule per line” contract.
            return .eachLine
        }
        return saved
    }

    static func instructions() -> [String] {
        instructions(defaults: localDefaults)
    }

    static func instructions(defaults: UserDefaults) -> [String] {
        let raw = instruction(defaults: defaults)
        switch mode(defaults: defaults) {
        case .wholeText:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [raw]
        case .eachLine:
            return raw.components(separatedBy: .newlines).filter {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    static func saveRaw(_ text: String) {
        saveRaw(text, defaults: localDefaults)
    }

    static func saveRaw(_ text: String, defaults: UserDefaults) {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if !normalized.isEmpty && !normalized.hasSuffix("\n") { normalized += "\n" }
        defaults.set(normalized, forKey: defaultsKey)
    }

    static func saveMode(_ mode: CheckInstructionMode) {
        saveMode(mode, defaults: localDefaults)
    }

    static func saveMode(_ mode: CheckInstructionMode, defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }

    static func isCustomized() -> Bool {
        isCustomized(defaults: localDefaults)
    }

    static func isCustomized(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) != nil
    }
}
