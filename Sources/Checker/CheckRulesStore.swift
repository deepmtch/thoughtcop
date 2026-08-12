// The single local source of truth for what Thinkpeek should flag.

import Foundation

enum CheckRulesStore {
    static let suiteName = "com.thinkpeek.app"
    static let defaultsKey = "runtimeCheckRules"
    static let defaultValue = "Claude is confused or waiting for user to do someting.\n"
    static let localDefaults = UserDefaults(suiteName: suiteName)!

    static func loadRaw() -> String {
        loadRaw(defaults: localDefaults)
    }

    static func loadRaw(defaults: UserDefaults) -> String {
        defaults.string(forKey: defaultsKey) ?? defaultValue
    }

    static func rules() -> [String] {
        rules(defaults: localDefaults)
    }

    static func rules(defaults: UserDefaults) -> [String] {
        parse(loadRaw(defaults: defaults))
    }

    static func parse(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
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

    static func isCustomized() -> Bool {
        isCustomized(defaults: localDefaults)
    }

    static func isCustomized(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) != nil
    }
}
