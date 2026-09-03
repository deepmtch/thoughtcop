// Reading Claude Desktop's structured conversation responses from its Chromium
// cache. Explicit plaintext `thinking` is displayed and evaluated. Assistant
// `text` responses are evaluated without being presented as thinking. User
// messages, tools, summaries, and empty/encrypted records are not emitted.

import Foundation

struct ClaudeDesktopConversationEvent {
    let identifier: String
    let source: String
    let block: Block
}

private let zstdFrameMagic = Data([0x28, 0xb5, 0x2f, 0xfd])

func isClaudeDesktopConversationCache(_ data: Data) -> Bool {
    let prefix = data.prefix(min(data.count, 4096))
    guard let header = String(data: prefix, encoding: .isoLatin1) else { return false }
    return header.contains("/api/organizations/") &&
        header.contains("/chat_conversations/") &&
        header.contains("tree=True")
}

func claudeDesktopConversationEvents(in jsonData: Data)
    -> [ClaudeDesktopConversationEvent] {
    guard let conversation = (try? JSONSerialization.jsonObject(with: jsonData))
            as? [String: Any],
          let conversationID = conversation["uuid"] as? String,
          !conversationID.isEmpty,
          let title = conversation["name"] as? String,
          !title.isEmpty,
          let messages = conversation["chat_messages"] as? [[String: Any]]
    else { return [] }

    let source = "Claude · \(title)"
    var events: [ClaudeDesktopConversationEvent] = []
    for message in messages {
        guard message["sender"] as? String == "assistant",
              let messageID = message["uuid"] as? String,
              !messageID.isEmpty,
              let content = message["content"] as? [[String: Any]] else { continue }
        let messageTimestamp = message["updated_at"] as? String ??
            message["created_at"] as? String ?? ""
        for (index, item) in content.enumerated() {
            let type = item["type"] as? String
            let text: String
            let kind: Block.Kind
            let eventType: String
            if type == "thinking", let thinking = item["thinking"] as? String {
                text = thinking
                kind = .thinking
                eventType = "thinking"
            } else if type == "text", let response = item["text"] as? String {
                text = response
                kind = .response
                eventType = "assistant_response"
            } else {
                continue
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let timestamp = item["stop_timestamp"] as? String ??
                item["start_timestamp"] as? String ?? messageTimestamp
            let identifier = conversationID + "|" + messageID + "|" + String(index)
            events.append(ClaudeDesktopConversationEvent(
                identifier: identifier,
                source: source,
                block: Block(ts: timestamp, text: text, sealed: false,
                             signatureChars: 0, kind: kind,
                             evaluationText: text,
                             evaluationEventType: eventType,
                             externallyEvaluable: true)))
        }
    }
    return events
}

func zstdFrame(in cacheData: Data) -> Data? {
    guard let range = cacheData.range(of: zstdFrameMagic) else { return nil }
    return cacheData.subdata(in: range.lowerBound..<cacheData.endIndex)
}

private func zstdExecutable() -> String? {
    let candidates = [
        "/opt/homebrew/bin/zstd",
        "/usr/local/bin/zstd",
        "/usr/bin/zstd",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func decompressZstd(_ data: Data) -> Data? {
    guard let executable = zstdExecutable() else { return nil }
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["--decompress", "--stdout", "--quiet"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    do {
        try process.run()
        input.fileHandleForWriting.write(data)
        try input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // Chromium appends cache bookkeeping bytes after the zstd frame. The
        // decoder emits the complete frame before reporting the trailing bytes
        // as an unsupported second frame. JSON decoding below is the integrity
        // check, so retain that complete output even when the trailer makes the
        // process status nonzero.
        return result.isEmpty ? nil : result
    } catch {
        return nil
    }
}

func claudeDesktopConversationEvents(inCacheData cacheData: Data)
    -> [ClaudeDesktopConversationEvent] {
    guard isClaudeDesktopConversationCache(cacheData),
          let frame = zstdFrame(in: cacheData),
          let jsonData = decompressZstd(frame) else { return [] }
    return claudeDesktopConversationEvents(in: jsonData)
}

final class ClaudeDesktopConversationMonitor {
    private struct FileStamp: Equatable {
        let size: UInt64
        let modified: Date
    }

    private let queue = DispatchQueue(label: "thinkpeek.claude-desktop-conversation",
                                      qos: .utility)
    private let directory: String
    private var discoveryIndex = ClaudeCacheDiscoveryIndex()
    private var conversationNames: Set<String> = []
    private var incompleteNames: Set<String> = []
    private var inspectedFiles: [String: FileStamp] = [:]
    private var emittedIdentifiers = Set<String>()
    private var initialized = false
    private var directoryModified: ExactFileStamp?
    private let lock = NSLock()
    private var pollInFlight = false

    init(directory: String? = nil) {
        self.directory = directory ?? ProcessInfo.processInfo.environment[
            "THINKPEEK_CLAUDE_DESKTOP_CACHE"] ?? NSString(
                string: "~/Library/Application Support/Claude/Cache/Cache_Data")
                .expandingTildeInPath
    }

    @discardableResult
    func poll(completion: @escaping ([ClaudeDesktopConversationEvent]) -> Void) -> Bool {
        lock.lock()
        guard !pollInFlight else { lock.unlock(); return false }
        pollInFlight = true
        lock.unlock()

        queue.async { [self] in
            let events = inspectChangedFiles()
            lock.lock()
            pollInFlight = false
            lock.unlock()
            DispatchQueue.main.async { completion(events) }
        }
        return true
    }

    private func inspectChangedFiles() -> [ClaudeDesktopConversationEvent] {
        if claudeCacheDirectoryChanged(directory,
                                       previous: &directoryModified) {
            discoverConversationFiles()
        }
        var changed: [(path: String, stamp: FileStamp)] = []
        for name in conversationNames {
            let path = directory + "/" + name
            guard let file = exactFileStamp(path) else { continue }
            let stamp = FileStamp(size: file.size, modified: file.modified)
            if inspectedFiles[path] != stamp { changed.append((path, stamp)) }
        }

        // A desktop conversation can already be actively thinking when
        // ThinkPeek launches. Surface the configured history count as local
        // history, then retain exact identifiers so later cache writes appear
        // once only. No content or timestamp inference decides eligibility.
        if !initialized {
            var initialEvents: [ClaudeDesktopConversationEvent] = []
            for item in changed {
                inspectedFiles[item.path] = item.stamp
                guard item.stamp.size > 0,
                      item.stamp.size <= 16 * 1024 * 1024,
                      let data = FileManager.default.contents(atPath: item.path)
                else { continue }
                for event in claudeDesktopConversationEvents(inCacheData: data) {
                    emittedIdentifiers.insert(event.identifier)
                    initialEvents.append(event)
                }
            }
            initialized = true
            guard BACKFILL > 0 else { return [] }
            let retained = BACKFILL == Int.max ? initialEvents : Array(
                initialEvents.sorted { $0.block.ts < $1.block.ts }.suffix(BACKFILL))
            return retained.map { event in
                ClaudeDesktopConversationEvent(
                    identifier: event.identifier, source: event.source,
                    block: Block(ts: event.block.ts, text: event.block.text,
                                 sealed: event.block.sealed,
                                 signatureChars: event.block.signatureChars,
                                 kind: event.block.kind,
                                 evaluationText: event.block.evaluationText,
                                 evaluationEventType: event.block.evaluationEventType,
                                 externallyEvaluable: event.block.externallyEvaluable,
                                 activityPhase: event.block.activityPhase,
                                 backfilled: true))
            }
        }

        var result: [ClaudeDesktopConversationEvent] = []
        for item in changed {
            inspectedFiles[item.path] = item.stamp
            guard item.stamp.size > 0,
                  item.stamp.size <= 16 * 1024 * 1024,
                  let data = FileManager.default.contents(atPath: item.path) else { continue }
            for event in claudeDesktopConversationEvents(inCacheData: data)
                where emittedIdentifiers.insert(event.identifier).inserted {
                result.append(event)
            }
        }
        return result
    }

    private func discoverConversationFiles() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory)
        else { return }
        let changes = discoveryIndex.update(names)
        for name in changes.removed {
            let path = directory + "/" + name
            conversationNames.remove(name)
            incompleteNames.remove(name)
            inspectedFiles.removeValue(forKey: path)
        }

        let candidates = changes.added.union(incompleteNames)
        for name in candidates {
            let path = directory + "/" + name
            guard let file = exactFileStamp(path),
                  let handle = FileHandle(forReadingAtPath: path) else {
                incompleteNames.insert(name)
                continue
            }
            let size = file.size
            defer { try? handle.close() }
            let prefix = handle.readData(ofLength: 4096)
            if isClaudeDesktopConversationCache(prefix) {
                conversationNames.insert(name)
                incompleteNames.remove(name)
            } else if size < 4096 {
                incompleteNames.insert(name)
            } else {
                incompleteNames.remove(name)
            }
        }
    }
}
