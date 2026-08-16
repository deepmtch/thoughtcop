// Content-free audit trail for the reasoning-only monitoring boundary.

import Foundation

let PRIVACY_AUDIT_PATH = ProcessInfo.processInfo.environment["THINKPEEK_PRIVACY_AUDIT_PATH"]
    ?? ("~/Library/Logs/Thinkpeek/privacy-audit.jsonl" as NSString).expandingTildeInPath

func auditMetadata(in line: String) -> [[String: Any]] {
    guard let data = line.data(using: .utf8),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return [] }

    let rootType = root["type"] as? String ?? "unknown"
    if let payload = root["payload"] as? [String: Any],
       let payloadType = payload["type"] as? String {
        switch (rootType, payloadType) {
        case ("event_msg", "agent_reasoning"):
            return [["record_type": "codex.agent_reasoning",
                     "action": "duplicate_reasoning_discarded"]]
        case ("response_item", "reasoning"):
            let summaryCount = (payload["summary"] as? [[String: Any]] ?? []).compactMap {
                ($0["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }.count
            let plaintextCount = (payload["content"] as? [[String: Any]] ?? []).filter {
                $0["type"] as? String == "reasoning_text" &&
                !(($0["text"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            let action: String
            if plaintextCount > 0 {
                action = "reasoning_selected"
            } else if summaryCount > 0 {
                action = "provider_summary_not_sent"
            } else {
                action = "encrypted_reasoning_not_sent"
            }
            return [["record_type": "codex.reasoning",
                     "action": action,
                     "plaintext_reasoning_count": plaintextCount,
                     "provider_summary_count": summaryCount]]
        case ("response_item", "custom_tool_call"):
            return [["record_type": "codex.tool_call",
                     "action": "tool_record_discarded"]]
        case ("response_item", "custom_tool_call_output"):
            return [["record_type": "codex.tool_result",
                     "action": "tool_record_discarded"]]
        case ("event_msg", "task_started"):
            return [["record_type": "codex.activity", "action": "display_only"]]
        default:
            break
        }
    }

    guard let message = root["message"] as? [String: Any],
          let content = message["content"] as? [[String: Any]] else { return [] }
    return content.compactMap { item in
        switch item["type"] as? String {
        case "thinking":
            let readable = !((item["thinking"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return ["record_type": "claude.reasoning",
                    "action": readable ? "reasoning_selected" :
                        "encrypted_reasoning_not_sent"]
        case "tool_use":
            return ["record_type": "claude.tool_call",
                    "action": "tool_record_discarded"]
        case "tool_result":
            return ["record_type": "claude.tool_result",
                    "action": "tool_record_discarded"]
        default:
            return nil
        }
    }
}

final class PrivacyAudit {
    static let shared = PrivacyAudit(path: PRIVACY_AUDIT_PATH)

    let path: String
    private let lock = NSLock()
    private let runID = UUID().uuidString

    init(path: String) { self.path = path }

    func start(reset: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory,
                                                  withIntermediateDirectories: true)
        if reset {
            FileManager.default.createFile(atPath: path, contents: Data(),
                attributes: [.posixPermissions: 0o600])
        }
        appendLocked(["action": "app_started", "scope": "reasoning_only",
                      "pid": ProcessInfo.processInfo.processIdentifier])
    }

    func recordTranscriptLine(_ line: String, sourcePath: String) {
        let bytes = line.utf8.count
        for metadata in auditMetadata(in: line) {
            var event = metadata
            event["source_file"] = (sourcePath as NSString).lastPathComponent
            event["record_bytes"] = bytes
            append(event)
        }
    }

    func recordExternalRequest(source: String, destination: String,
                               recordType: String, envelopeBytes: Int,
                               requestID: String) {
        append(["action": "external_reasoning_request",
                "record_type": recordType, "source": source,
                "destination": destination, "envelope_bytes": envelopeBytes,
                "request_id": requestID])
    }

    /// Content-free completion record paired to `recordExternalRequest`.
    func recordExternalResult(source: String, destination: String,
                              recordType: String, requestID: String,
                              status: String, alert: Bool? = nil,
                              latencyMs: Int) {
        var event: [String: Any] = [
            "action": "external_reasoning_result",
            "record_type": recordType,
            "source": source,
            "destination": destination,
            "request_id": requestID,
            "status": status,
            "latency_ms": latencyMs,
        ]
        if let alert { event["alert"] = alert }
        append(event)
    }

    private func append(_ event: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        appendLocked(event)
    }

    private func appendLocked(_ event: [String: Any]) {
        var record = event
        record["timestamp"] = ISO8601DateFormatter().string(from: Date())
        record["run_id"] = runID
        guard let data = try? JSONSerialization.data(withJSONObject: record,
                                                       options: [.sortedKeys]),
              let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            handle.write(data)
            handle.write(Data([0x0A]))
        } catch {}
    }
}
