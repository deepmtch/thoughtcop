// Reading and tailing Claude Code / Codex JSONL transcripts into Blocks.

import Foundation

/// One complete, provider-authored record eligible for external evaluation.
struct EvaluationRecord {
    let content: String
    let eventType: String

    init(content: String, eventType: String = "reasoning_summary") {
        self.content = content
        self.eventType = eventType
    }

    var json: [String: Any] {
        ["event_type": eventType, "content": content, "record_complete": true]
    }
}

struct Block {
    enum Kind { case activity, thinking, response }
    enum ActivityPhase: Equatable { case started, updated, waiting, finished }
    let ts: String
    let text: String
    let sealed: Bool
    let signatureChars: Int
    let kind: Kind
    let evaluationText: String
    let evaluationEventType: String
    let externallyEvaluable: Bool
    let activityPhase: ActivityPhase?
    var backfilled: Bool

    init(ts: String, text: String, sealed: Bool, signatureChars: Int,
         kind: Kind, evaluationText: String? = nil,
         evaluationEventType: String = "reasoning_summary",
         externallyEvaluable: Bool = true,
         activityPhase: ActivityPhase? = nil, backfilled: Bool = false) {
        self.ts = ts
        self.text = text
        self.sealed = sealed
        self.signatureChars = signatureChars
        self.kind = kind
        self.evaluationText = evaluationText ?? text
        self.evaluationEventType = evaluationEventType
        self.externallyEvaluable = externallyEvaluable
        self.activityPhase = activityPhase
        self.backfilled = backfilled
    }

    var evaluationRecord: EvaluationRecord {
        EvaluationRecord(content: evaluationText, eventType: evaluationEventType)
    }
}

private func activityBlock(ts: String, phase: Block.ActivityPhase) -> Block {
    Block(ts: ts, text: "Provider activity", sealed: false,
          signatureChars: 0, kind: .activity, externallyEvaluable: false,
          activityPhase: phase)
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
        return UIEvent(timestamp: block.ts, kind: "omitted-analysis",
                       text: "⟨Original reasoning unavailable — the provider record " +
                             "contains no plaintext reasoning⟩",
                       readableAnalysis: false)
    }
    if block.kind == .response {
        return UIEvent(timestamp: block.ts, kind: "response", text: block.text,
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
    if obj["type"] as? String == "system",
       obj["subtype"] as? String == "turn_duration" {
        // Claude writes this explicit terminal record after a completed turn,
        // including turns whose last assistant record was a tool invocation.
        return [activityBlock(ts: ts, phase: .finished)]
    }
    if obj["type"] as? String == "queue-operation" {
        let operation = obj["operation"] as? String
        let phase: Block.ActivityPhase = operation == "dequeue" ? .started : .updated
        return [activityBlock(ts: ts, phase: phase)]
    }
    if obj["type"] as? String == "event_msg",
       let payload = obj["payload"] as? [String: Any] {
        if payload["type"] as? String == "task_started" {
            return [activityBlock(ts: ts, phase: .started)]
        }
        if payload["type"] as? String == "task_complete" {
            return [activityBlock(ts: ts, phase: .finished)]
        }
        if payload["type"] as? String == "turn_aborted" {
            return [activityBlock(ts: ts, phase: .finished)]
        }
        if payload["type"] as? String == "agent_reasoning" {
            // This is provider-generated summary text, not original reasoning.
            return [activityBlock(ts: ts, phase: .updated)]
        }
    }
    if obj["type"] as? String == "response_item",
       let payload = obj["payload"] as? [String: Any] {
        if payload["type"] as? String == "custom_tool_call" ||
           payload["type"] as? String == "custom_tool_call_output" {
            return [activityBlock(ts: ts, phase: .updated)]
        }
    }
    if obj["type"] as? String == "response_item",
       let payload = obj["payload"] as? [String: Any],
       payload["type"] as? String == "message",
       payload["role"] as? String == "assistant" {
        let texts = (payload["content"] as? [[String: Any]] ?? []).compactMap {
            item -> String? in
            guard item["type"] as? String == "output_text",
                  let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return text
        }
        let phase: Block.ActivityPhase = payload["phase"] as? String == "final_answer"
            ? .finished : .updated
        guard !texts.isEmpty else { return [activityBlock(ts: ts, phase: phase)] }
        let response = texts.joined(separator: "\n\n")
        return [activityBlock(ts: ts, phase: phase),
                Block(ts: ts, text: response, sealed: false,
                      signatureChars: 0, kind: .response,
                      evaluationText: response,
                      evaluationEventType: "assistant_response",
                      externallyEvaluable: true)]
    }
    if obj["type"] as? String == "response_item",
       let payload = obj["payload"] as? [String: Any],
       payload["type"] as? String == "reasoning" {
        let reasoningTexts: [String] =
            (payload["content"] as? [[String: Any]] ?? []).compactMap { item -> String? in
            guard item["type"] as? String == "reasoning_text" else { return nil }
            guard let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return text
        }
        let encryptedChars = (payload["encrypted_content"] as? String)?.count ?? 0
        if !reasoningTexts.isEmpty {
            let reasoningText = reasoningTexts.joined(separator: "\n\n")
            return [activityBlock(ts: ts, phase: .updated),
                    Block(ts: ts, text: reasoningText,
                          sealed: false, signatureChars: encryptedChars,
                          kind: .thinking, evaluationText: reasoningText,
                          evaluationEventType: "reasoning_text",
                          externallyEvaluable: true)]
        }
        let summaryTexts: [String] =
            (payload["summary"] as? [[String: Any]] ?? []).compactMap { item -> String? in
            guard item["type"] as? String == "summary_text",
                  let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return text
        }
        if !summaryTexts.isEmpty {
            let summaryText = summaryTexts.joined(separator: "\n\n")
            // Codex commonly persists only this readable provider summary. It
            // is useful local status, but is not original reasoning and must
            // never enter the external checker.
            return [activityBlock(ts: ts, phase: .updated),
                    Block(ts: ts, text: summaryText,
                          sealed: false, signatureChars: encryptedChars,
                          kind: .thinking, evaluationText: summaryText,
                          evaluationEventType: "reasoning_summary",
                          externallyEvaluable: false)]
        }
        if encryptedChars > 0 {
            return [activityBlock(ts: ts, phase: .updated)]
        }
        return [activityBlock(ts: ts, phase: .updated)]
    }
    guard obj["type"] as? String == "assistant",
          let message = obj["message"] as? [String: Any],
          let content = message["content"] as? [[String: Any]] else {
        // Unknown metadata, user messages, attachments and snapshots do not
        // establish provider activity. Only explicit lifecycle/provider output
        // records may mutate the working state.
        return []
    }
    let hasToolUse = content.contains { ($0["type"] as? String) == "tool_use" }
    let isWaitingForUser = content.contains {
        ($0["type"] as? String) == "tool_use" &&
        ($0["name"] as? String) == "AskUserQuestion"
    }
    let hasText = content.contains { ($0["type"] as? String) == "text" }
    let phase: Block.ActivityPhase = isWaitingForUser
        ? .waiting : (hasText && !hasToolUse ? .finished : .updated)
    var evaluable = content.compactMap { block -> Block? in
        switch block["type"] as? String {
        case "thinking":
            let text = (block["thinking"] as? String) ?? ""
            let signatureChars = (block["signature"] as? String)?.count ?? 0
            let readable = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard readable else { return nil }
            return Block(ts: ts, text: text, sealed: !readable,
                         signatureChars: signatureChars, kind: .thinking,
                         evaluationText: text,
                         evaluationEventType: "thinking",
                         externallyEvaluable: true)
        case "tool_use", "tool_result":
            return nil
        default:
            return nil
        }
    }
    if obj["isApiErrorMessage"] as? Bool != true {
        let responseTexts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text",
                  let text = block["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return text
        }
        if !responseTexts.isEmpty {
            let response = responseTexts.joined(separator: "\n\n")
            evaluable.append(Block(ts: ts, text: response, sealed: false,
                                   signatureChars: 0, kind: .response,
                                   evaluationText: response,
                                   evaluationEventType: "assistant_response",
                                   externallyEvaluable: true))
        }
    }
    return [activityBlock(ts: ts, phase: phase)] + evaluable
}

/// Follows one JSONL file by byte offset, tolerating partial writes and truncation.
let MAX_BOUNDED_BACKFILL_BYTES: UInt64 = 2_097_152

func backfillFloor(fileSize: UInt64, limit: Int) -> UInt64 {
    guard limit != Int.max else { return 0 }
    return fileSize > MAX_BOUNDED_BACKFILL_BYTES
        ? fileSize - MAX_BOUNDED_BACKFILL_BYTES : 0
}

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
                  signatureChars: $0.signatureChars, kind: $0.kind,
                  evaluationText: $0.evaluationText,
                  evaluationEventType: $0.evaluationEventType,
                  externallyEvaluable: $0.externallyEvaluable,
                  activityPhase: $0.activityPhase,
                  backfilled: true)
        }
    }

    /// Read backwards in bounded chunks until enough visible history is found.
    /// This avoids loading multi-megabyte rollout files just to show three cards.
    private func backfillBlocks(limit: Int) -> [Block] {
        guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let chunkSize: UInt64 = 262_144
        let floor = backfillFloor(fileSize: size, limit: limit)
        var start = size
        var accumulated = Data()
        var found: [Block] = []
        repeat {
            let next = max(floor, start > chunkSize ? start - chunkSize : 0)
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
                .filter { $0.kind == .thinking }
        } while start > floor && found.count < limit
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

/// Owns every Tailer on one utility queue. AppKit submits desired paths and
/// receives parsed blocks; it never opens, stats, seeks, or parses transcript
/// files itself.
final class TranscriptMonitorWorker {
    typealias TailerFactory = (String, Int, UInt64?) -> Tailer

    private let queue: DispatchQueue
    private let tailerFactory: TailerFactory
    private let stateLock = NSLock()
    private var updateInFlight = false
    private var pollInFlight = false
    private var tailers: [String: Tailer] = [:]
    private var knownOffsets: [String: UInt64] = [:]
    private var launchOffsetsCaptured = false
    private var monitorsReady = false

    init(queue: DispatchQueue = DispatchQueue(
            label: "thinkpeek.transcript-monitor", qos: .utility),
         tailerFactory: @escaping TailerFactory = {
            Tailer(path: $0, backfill: $1, startOffset: $2)
         }) {
        self.queue = queue
        self.tailerFactory = tailerFactory
    }

    @discardableResult
    func update(discoveredPaths: [String], launchSizes: [String: UInt64],
                pinned: String?, completion: @escaping () -> Void) -> Bool {
        stateLock.lock()
        guard !updateInFlight else {
            stateLock.unlock()
            return false
        }
        updateInFlight = true
        stateLock.unlock()

        queue.async { [self] in
            if !launchOffsetsCaptured {
                knownOffsets = launchSizes
                launchOffsetsCaptured = true
            }
            var wanted = discoveredPaths
            if let pinned {
                wanted = wanted.filter {
                    sameTranscript(rootSessionPath(for: $0), pinned)
                }
                if !wanted.contains(where: { sameTranscript($0, pinned) }) {
                    wanted.append(pinned)
                }
            }
            let wantedSet = Set(wanted)
            for path in tailers.keys.filter({ !wantedSet.contains($0) }) {
                knownOffsets[path] = tailers[path]?.resumeOffset
                tailers.removeValue(forKey: path)
            }
            for path in wanted where tailers[path] == nil {
                if !monitorsReady {
                    let scanLimit = BACKFILL == Int.max ? Int.max
                        : (BACKFILL >= 13 ? 100 : BACKFILL * 8)
                    tailers[path] = tailerFactory(path, scanLimit, nil)
                } else {
                    tailers[path] = tailerFactory(path, 0, knownOffsets[path] ?? 0)
                }
            }
            monitorsReady = true
            stateLock.lock()
            updateInFlight = false
            stateLock.unlock()
            DispatchQueue.main.async(execute: completion)
        }
        return true
    }

    func reset(pinned: String?, completion: @escaping () -> Void) {
        queue.async { [self] in
            for (path, tailer) in tailers { knownOffsets[path] = tailer.resumeOffset }
            tailers.removeAll()
            monitorsReady = pinned != nil
            if let pinned {
                tailers[pinned] = tailerFactory(pinned, BACKFILL, nil)
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    @discardableResult
    func poll(completion: @escaping ([(path: String, block: Block)]) -> Void) -> Bool {
        stateLock.lock()
        guard !pollInFlight else {
            stateLock.unlock()
            return false
        }
        pollInFlight = true
        stateLock.unlock()

        queue.async { [self] in
            var arrived: [(path: String, block: Block)] = []
            for (path, tailer) in tailers {
                arrived += tailer.drain().map { (path: path, block: $0) }
            }
            stateLock.lock()
            pollInFlight = false
            stateLock.unlock()
            DispatchQueue.main.async { completion(arrived) }
        }
        return true
    }
}
