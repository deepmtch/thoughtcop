// One-time carry-over of settings and data from the pre-rename app
// identifiers (Thinkpeek) to the current ones (Thoughtcrime).

import Foundation

enum LegacyMigration {
    static let legacyRulesSuite = "com.thinkpeek.app"
    static let legacyDesktopSuite = "com.thinkpeek.desktop"
    static let legacyDataDirectory =
        ("~/Library/Application Support/Thinkpeek" as NSString).expandingTildeInPath
    static let currentDataDirectory =
        ("~/Library/Application Support/Thoughtcrime" as NSString).expandingTildeInPath

    /// Copies every key of the legacy preferences domain that the current
    /// domain does not have yet, and moves the legacy data folder when the
    /// current one does not exist. Existing current values always win, so a
    /// second run changes nothing.
    static func run(fileManager: FileManager = .default) {
        copyDefaults(from: legacyRulesSuite, to: UserDefaults(suiteName: CheckRulesStore.suiteName)!)
        copyDefaults(from: legacyDesktopSuite, to: .standard)
        moveDataDirectory(fileManager: fileManager)
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
                                  legacy: String = legacyDataDirectory,
                                  current: String = currentDataDirectory) {
        guard fileManager.fileExists(atPath: legacy),
              !fileManager.fileExists(atPath: current) else { return }
        try? fileManager.moveItem(atPath: legacy, toPath: current)
    }
}
