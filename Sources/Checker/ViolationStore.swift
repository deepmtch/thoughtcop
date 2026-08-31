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

    init(id: String = UUID().uuidString, timestamp: String, source: String,
         content: String, reason: String, evidence: String, provider: String,
         latencyMs: Int, checkPrompt: String) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.content = content
        self.reason = reason
        self.evidence = evidence
        self.provider = provider
        self.latencyMs = latencyMs
        self.checkPrompt = checkPrompt
    }

    var json: [String: Any] {
        [
            "id": id, "timestamp": timestamp, "source": source,
            "content": content, "reason": reason, "evidence": evidence,
            "provider": provider, "latencyMs": latencyMs,
            "checkPrompt": checkPrompt,
        ]
    }
}

final class ViolationStore {
    static let maximumRecords = 500

    let path: String
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
        records.append(record)
        records = Array(records.suffix(Self.maximumRecords))
        saveUnlocked(records)
        return records
    }

    private func loadUnlocked() -> [ViolationRecord] {
        guard let data = FileManager.default.contents(atPath: path),
              let records = try? JSONDecoder().decode([ViolationRecord].self, from: data)
        else { return [] }
        return records
    }

    private func saveUnlocked(_ records: [ViolationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: path)
        } catch {}
    }
}
