// One-time carry-over of settings and data from the app's previous
// identifiers to the current ones (ThoughtCop).

import Foundation

enum LegacyMigration {
    /// Oldest first; a newer legacy domain wins over an older one because the
    /// copy fills only keys the target does not have yet.
    static let legacyRulesSuites = ["com.thinkpeek.app", "com.thoughtcrime.app", "com.doublethink.app"]
    static let legacyDesktopSuites = ["com.thinkpeek.desktop", "com.thoughtcrime.desktop", "com.doublethink.desktop"]
    static let legacyDataDirectories = ["Thinkpeek", "Thoughtcrime", "Doublethink"].map {
        ("~/Library/Application Support/" + $0 as NSString).expandingTildeInPath
    }
    static let currentDataDirectory =
        ("~/Library/Application Support/ThoughtCop" as NSString).expandingTildeInPath

    /// Copies every key of each legacy preferences domain that the current
    /// domain does not have yet, and moves the newest legacy data folder when
    /// the current one does not exist. Existing current values always win, so
    /// a second run changes nothing.
    static func run(fileManager: FileManager = .default) {
        for suite in legacyRulesSuites.reversed() {
            copyDefaults(from: suite, to: UserDefaults(suiteName: CheckRulesStore.suiteName)!)
        }
        for suite in legacyDesktopSuites.reversed() {
            copyDefaults(from: suite, to: .standard)
        }
        for legacy in legacyDataDirectories.reversed() {
            moveDataDirectory(fileManager: fileManager, legacy: legacy, current: currentDataDirectory)
        }
    }

    static func copyDefaults(from legacySuite: String, to target: UserDefaults) {
        guard let legacy = UserDefaults(suiteName: legacySuite) else { return }
        for (key, value) in legacy.persistentDomain(forName: legacySuite) ?? [:] {
            if target.object(forKey: key) == nil {
                target.set(value, forKey: key)
            }
        }
    }

    static func moveDataDirectory(fileManager: FileManager = .default,
                                  legacy: String, current: String = currentDataDirectory) {
        guard fileManager.fileExists(atPath: legacy),
              !fileManager.fileExists(atPath: current) else { return }
        try? fileManager.moveItem(atPath: legacy, toPath: current)
    }
}
