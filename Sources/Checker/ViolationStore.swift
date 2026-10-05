// Persistent local record of evaluator violations.

import Foundation

func violationHistoryMenuTitle(recorded: Int, unreviewed: Int,
                               storageUnavailable: Bool) -> String {
    if storageUnavailable { return "Open Violation History (Unavailable)…" }
    if unreviewed > 0 { return "Open Violation History (\(unreviewed) New)…" }
    if recorded > 0 { return "Open Violation History (\(recorded) Reviewed)…" }
    return "Open Violation History…"
}

func violationStatusBadgeTitle(unreviewed: Int) -> String {
    unreviewed == 0 ? "" : " \(unreviewed)"
}

let VIOLATIONS_PATH = ProcessInfo.processInfo.environment["THINKPEEK_VIOLATIONS_PATH"]
    ?? ("~/Library/Application Support/Thinkpeek/violations.json" as NSString)
        .expandingTildeInPath

struct ViolationRecord: Codable, Equatable {
    let id: String
    let timestamp: String
    let source: String
    let content: String
    let reason: String
    let evidence: String
    let provider: String
    let latencyMs: Int
    let checkPrompt: String
    var reviewedAt: String?
    /// One plain sentence from a separate request after the violation was
    /// recorded; nil until it arrives, or when that request failed.
    var summary: String?

    init(id: String = UUID().uuidString, timestamp: String, source: String,
         content: String, reason: String, evidence: String, provider: String,
         latencyMs: Int, checkPrompt: String, reviewedAt: String? = nil,
         summary: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.content = content
        self.reason = reason
        self.evidence = evidence
        self.provider = provider
        self.latencyMs = latencyMs
        self.checkPrompt = checkPrompt
        self.reviewedAt = reviewedAt
        self.summary = summary
    }

    var json: [String: Any] {
        var value: [String: Any] = [
            "id": id, "timestamp": timestamp, "source": source,
            "content": content, "reason": reason, "evidence": evidence,
            "provider": provider, "latencyMs": latencyMs,
            "checkPrompt": checkPrompt,
        ]
        if let reviewedAt { value["reviewedAt"] = reviewedAt }
        if let summary { value["summary"] = summary }
        return value
    }
}

/// How many violations the history keeps, chosen by the user. The newest
/// records are kept; older ones are deleted from disk.
enum ViolationHistoryPreference {
    static let defaultsKey = "violationHistoryLimit"
    static let choices = [10, 25, 50, 100, 250, 500]
    static let defaultLimit = 50

    static func load(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: defaultsKey)
        return choices.contains(stored) ? stored : defaultLimit
    }

    static func save(_ limit: Int, defaults: UserDefaults = .standard) {
        guard choices.contains(limit) else { return }
        defaults.set(limit, forKey: defaultsKey)
    }
}

final class ViolationStore {
    /// The largest selectable history limit.
    static let maximumRecords = ViolationHistoryPreference.choices.max()!

    let path: String
    private(set) var lastError: String?
    private(set) var limit: Int
    private let lock = NSLock()

    init(path: String = VIOLATIONS_PATH,
         limit: Int = ViolationHistoryPreference.load()) {
        self.path = path
        self.limit = limit
    }

    /// Applies a history limit to the stored file: keeps the newest `limit`
    /// records and deletes the rest. An unreadable file is left untouched.
    @discardableResult
    func setLimit(_ newLimit: Int) -> [ViolationRecord] {
        lock.lock()
        defer { lock.unlock() }
        limit = newLimit
        let records = loadUnlocked()
        guard lastError == nil else { return records }
        guard records.count > limit else { return records }
        let kept = Array(records.suffix(limit))
        saveUnlocked(kept)
        return kept
    }

    func load() -> [ViolationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    @discardableResult
    func append(_ record: ViolationRecord) -> [ViolationRecord] {
        lock.lock()
        defer { lock.unlock() }
        var records = loadUnlocked()
        guard lastError == nil else {
            // Preserve the unreadable file for recovery instead of silently
            // replacing it with a new one. Keep the live record visible in
            // this process while the UI reports that persistence is unavailable.
            records.append(record)
            return records
        }
        records.append(record)
        records = Array(records.suffix(limit))
        saveUnlocked(records)
        return records
    }

    @discardableResult
    func markReviewed(id: String, at timestamp: String = ISO8601DateFormatter()
        .string(from: Date())) -> [ViolationRecord] {
        lock.lock()
        defer { lock.unlock() }
        var records = loadUnlocked()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return records }
        records[index].reviewedAt = timestamp
        saveUnlocked(records)
        return records
    }

    func setSummary(id: String, summary: String) -> [ViolationRecord] {
        lock.lock()
        defer { lock.unlock() }
        var records = loadUnlocked()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return records }
        records[index].summary = summary
        saveUnlocked(records)
        return records
    }

    private func loadUnlocked() -> [ViolationRecord] {
        guard FileManager.default.fileExists(atPath: path) else {
            lastError = nil
            return []
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            lastError = "The violation history file could not be read."
            return []
        }
        do {
            let records = try JSONDecoder().decode([ViolationRecord].self, from: data)
            lastError = nil
            return records
        } catch {
            lastError = "The violation history file is damaged or incompatible."
            return []
        }
    }

    private func saveUnlocked(_ records: [ViolationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else {
            lastError = "Violation history could not be encoded."
            return
        }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: path)
            lastError = nil
        } catch {
            lastError = "Violation history could not be saved."
        }
    }
}
