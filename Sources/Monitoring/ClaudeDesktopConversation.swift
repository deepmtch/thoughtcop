// Reading Claude Desktop's structured conversation responses from its Chromium
// cache. Only explicit plaintext `thinking` content becomes externally
// evaluable; messages, tools, summaries, and empty/encrypted records are not
// emitted by this monitor.

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
            guard item["type"] as? String == "thinking",
                  let thinking = item["thinking"] as? String,
                  !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let timestamp = item["stop_timestamp"] as? String ??
                item["start_timestamp"] as? String ?? messageTimestamp
            let identifier = conversationID + "|" + messageID + "|" + String(index)
            events.append(ClaudeDesktopConversationEvent(
                identifier: identifier,
                source: source,
                block: Block(ts: timestamp, text: thinking, sealed: false,
                             signatureChars: 0, kind: .thinking,
                             evaluationText: thinking,
                             evaluationEventType: "thinking",
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
    private var inspectedFiles: [String: FileStamp] = [:]
    private var emittedIdentifiers = Set<String>()
    private var initialized = false
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
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory)
        else { return [] }
        var changed: [(path: String, stamp: FileStamp)] = []
        for name in names {
            let path = directory + "/" + name
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let sizeNumber = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date else { continue }
            let stamp = FileStamp(size: sizeNumber.uint64Value, modified: modified)
            if inspectedFiles[path] != stamp { changed.append((path, stamp)) }
        }

        // Persistent browser cache must never be replayed as current activity.
        // Decode the structured records once on the utility queue so their
        // stable content identifiers form an exact baseline; no timestamp,
        // keyword, or content heuristic decides what is old.
        if !initialized {
            for item in changed {
                inspectedFiles[item.path] = item.stamp
                guard item.stamp.size > 0,
                      item.stamp.size <= 16 * 1024 * 1024,
                      let data = FileManager.default.contents(atPath: item.path)
                else { continue }
                for event in claudeDesktopConversationEvents(inCacheData: data) {
                    emittedIdentifiers.insert(event.identifier)
                }
            }
            initialized = true
            return []
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
}
