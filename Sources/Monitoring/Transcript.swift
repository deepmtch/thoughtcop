// Reading and tailing Claude Code / Codex JSONL transcripts into Blocks.

import Foundation

/// The only record eligible for automatic external evaluation: readable reasoning.
struct EvaluationRecord {
    let content: String
    let eventType = "reasoning_summary"

    var json: [String: Any] {
        ["event_type": eventType, "content": content, "record_complete": true]
    }
}

struct Block {
    enum Kind { case activity, thinking }
    let ts: String
    let text: String
    let sealed: Bool
    let signatureChars: Int
    let kind: Kind
    var backfilled: Bool

    init(ts: String, text: String, sealed: Bool, signatureChars: Int,
         kind: Kind, backfilled: Bool = false) {
        self.ts = ts
        self.text = text
        self.sealed = sealed
        self.signatureChars = signatureChars
        self.kind = kind
        self.backfilled = backfilled
    }

    var evaluationRecord: EvaluationRecord {
        EvaluationRecord(content: text)
    }
}

/// Stable presentation API shared by the AppKit window and headless tests.
/// If this payload is correct, the window receives the exact same text/kind.
struct UIEvent {
    let timestamp: String
    let kind: String
    let text: String
    let readableAnalysis: Bool

    var json: [String: Any] {
        ["timestamp": timestamp, "kind": kind, "text": text,
         "readableAnalysis": readableAnalysis]
    }
}

func uiEvent(for block: Block) -> UIEvent {
    if block.kind == .activity {
        return UIEvent(timestamp: block.ts, kind: "activity",
                       text: "● \(block.text)",
                       readableAnalysis: false)
    }
    if block.sealed {
        let received = block.signatureChars > 0
            ? "\(block.signatureChars)-character encrypted signature received"
            : "no readable text received"
        return UIEvent(timestamp: block.ts, kind: "omitted-analysis",
                       text: "⟨No readable analysis summary — \(received)⟩",
                       readableAnalysis: false)
    }
    return UIEvent(timestamp: block.ts, kind: "analysis", text: block.text,
                   readableAnalysis: true)
}

/// The transcript Claude Code wrote most recently, including nested sub-agents.
func transcriptFiles(under root: String) -> [String] {
    let fm = FileManager.default
    guard let files = fm.enumerator(atPath: root) else { return [] }
    var result: [String] = []
    for case let relative as String in files where relative.hasSuffix(".jsonl") {
        result.append(root + "/" + relative)
    }
    return result
}

func allTranscriptFiles() -> [String] {
    transcriptFiles(under: CLAUDE_PROJECTS) + transcriptFiles(under: CODEX_SESSIONS)
}

func newestTranscript() -> String? {
    let fm = FileManager.default
    var best: (path: String, when: Date)?
    for path in allTranscriptFiles() {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let when = attrs[.modificationDate] as? Date else { continue }
        if best == nil || when > best!.when { best = (path, when) }
    }
    return best?.path
}

/// Reasoning blocks carried by one JSONL record. Unparseable lines yield nothing.
func blocks(in line: String) -> [Block] {
    guard let data = line.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return [] }
    let ts = obj["timestamp"] as? String ?? ""
    if obj["type"] as? String == "queue-operation",
       obj["operation"] as? String == "dequeue" {
        return [Block(ts: ts, text: "Claude operation started", sealed: false,
                      signatureChars: 0, kind: .activity)]
    }
    if obj["type"] as? String == "event_msg",
       let payload = obj["payload"] as? [String: Any] {
        if payload["type"] as? String == "task_started" {
            return [Block(ts: ts, text: "Codex operation started", sealed: false,
                          signatureChars: 0, kind: .activity)]
        }
        if payload["type"] as? String == "agent_reasoning" {
            // Codex repeats these individual entries in the following
            // response_item.reasoning.summary array. That array is the complete,
            // ordered reasoning item and is the sole readable source below.
            return []
        }
    }
    if obj["type"] as? String == "response_item",
       let payload = obj["payload"] as? [String: Any] {
        if payload["type"] as? String == "custom_tool_call" ||
           payload["type"] as? String == "custom_tool_call_output" {
            return []
        }
    }
    if obj["type"] as? String == "response_item",
       let payload = obj["payload"] as? [String: Any],
       payload["type"] as? String == "reasoning" {
        let summaries = (payload["summary"] as? [[String: Any]] ?? []).compactMap {
            ($0["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let encryptedChars = (payload["encrypted_content"] as? String)?.count ?? 0
        if !summaries.isEmpty {
            return [Block(ts: ts, text: summaries.joined(separator: "\n\n"),
                          sealed: false, signatureChars: encryptedChars,
                          kind: .thinking)]
        }
        if encryptedChars > 0 {
            return [Block(ts: ts, text: "", sealed: true,
                          signatureChars: encryptedChars, kind: .thinking)]
        }
        return []
    }
    guard let message = obj["message"] as? [String: Any],
          let content = message["content"] as? [[String: Any]] else { return [] }
    return content.compactMap { block in
        switch block["type"] as? String {
        case "thinking":
            let text = ((block["thinking"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let signatureChars = (block["signature"] as? String)?.count ?? 0
            return Block(ts: ts, text: text, sealed: text.isEmpty,
                         signatureChars: signatureChars, kind: .thinking)
        case "tool_use", "tool_result":
            return nil
        default:
            return nil
        }
    }
}

/// Follows one JSONL file by byte offset, tolerating partial writes and truncation.
final class Tailer {
    let path: String
    let session: String
    private var offset: UInt64 = 0
    private var buf = ""
    private var pending: [Block] = []

    /// Safe byte position for recreating this tailer. If the last JSONL record
    /// is still partial, rewind over the buffer so it will be joined correctly.
    var resumeOffset: UInt64 {
        let buffered = UInt64(buf.utf8.count)
        return buffered < offset ? offset - buffered : 0
    }

    init(path: String, backfill: Int = BACKFILL, startOffset: UInt64? = nil) {
        self.path = path
        self.session = String((path as NSString).lastPathComponent.prefix(8))
        let size = fileSize() ?? 0
        if let startOffset {
            // A smaller file was truncated/rotated while it was not actively
            // monitored. Start from zero; seeking to its new EOF would drop it.
            offset = size < startOffset ? 0 : startOffset
            return
        }
        offset = size
        guard backfill > 0 else { return }
        let all = backfillBlocks(limit: backfill)
        pending = Array(all.suffix(backfill)).map {
            Block(ts: $0.ts, text: $0.text, sealed: $0.sealed,
                  signatureChars: $0.signatureChars, kind: $0.kind, backfilled: true)
        }
    }

    /// Read backwards in bounded chunks until enough visible history is found.
    /// This avoids loading multi-megabyte rollout files just to show three cards.
    private func backfillBlocks(limit: Int) -> [Block] {
        guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let chunkSize: UInt64 = 262_144
        var start = size
        var accumulated = Data()
        var found: [Block] = []
        repeat {
            let next = limit == Int.max ? 0 : (start > chunkSize ? start - chunkSize : 0)
            try? fh.seek(toOffset: next)
            var chunk = fh.readData(ofLength: Int(start - next))
            chunk.append(accumulated)
            accumulated = chunk
            start = next
            var text = String(data: accumulated, encoding: .utf8) ?? ""
            if start > 0, let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            }
            found = text.components(separatedBy: "\n").flatMap { blocks(in: $0) }
                .filter { $0.kind == .thinking && (SHOW_ENCRYPTED || !$0.sealed) }
        } while start > 0 && found.count < limit
        return found
    }

    private func fileSize() -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.size] as? NSNumber)?.uint64Value
    }

    func drain() -> [Block] {
        var out = pending
        pending = []
        guard let size = fileSize() else { return out }
        if size < offset { offset = 0; buf = "" }   // truncated or rotated
        guard size > offset, let fh = FileHandle(forReadingAtPath: path) else { return out }
        defer { try? fh.close() }
        try? fh.seek(toOffset: offset)
        let data = fh.readDataToEndOfFile()
        offset += UInt64(data.count)
        buf += String(data: data, encoding: .utf8) ?? ""
        var lines = buf.components(separatedBy: "\n")
        buf = lines.removeLast()                     // trailing partial line
        for line in lines {
            PrivacyAudit.shared.recordTranscriptLine(line, sourcePath: path)
            out += blocks(in: line)
        }
        return out
    }
}
