// Persistent local record of evaluator violations.

import Foundation

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

    init(id: String = UUID().uuidString, timestamp: String, source: String,
         content: String, reason: String, evidence: String, provider: String,
         latencyMs: Int, checkPrompt: String, reviewedAt: String? = nil) {
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
    }

    var json: [String: Any] {
        var value: [String: Any] = [
            "id": id, "timestamp": timestamp, "source": source,
            "content": content, "reason": reason, "evidence": evidence,
            "provider": provider, "latencyMs": latencyMs,
            "checkPrompt": checkPrompt,
        ]
        if let reviewedAt { value["reviewedAt"] = reviewedAt }
        return value
    }
}

final class ViolationStore {
    static let maximumRecords = 500

    let path: String
    private(set) var lastError: String?
    private let lock = NSLock()

    init(path: String = VIOLATIONS_PATH) { self.path = path }

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
        records = Array(records.suffix(Self.maximumRecords))
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
