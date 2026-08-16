// Exact activity events from Claude Desktop's cached cloud-session SSE stream.
// No message, tool, summary, or reasoning content leaves this monitor.

import Foundation

struct ProviderActivityEvent {
    let source: String
    let phase: Block.ActivityPhase
}

func claudeCloudActivityEvents(in text: String,
                               source: String = "Claude · cloud chat")
    -> [ProviderActivityEvent] {
    text.components(separatedBy: .newlines).compactMap { line in
        guard line.hasPrefix("data: "),
              let data = String(line.dropFirst(6)).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any] else { return nil }

        if object["event_type"] as? String == "result" {
            return ProviderActivityEvent(source: source, phase: .finished)
        }
        if object["event_type"] as? String == "control_request" {
            return ProviderActivityEvent(source: source, phase: .waiting)
        }
        if object["event_type"] as? String == "stream_event" {
            return ProviderActivityEvent(source: source, phase: .updated)
        }
        if object["event_type"] as? String == "system",
           let payload = object["payload"] as? [String: Any],
           payload["subtype"] as? String == "status",
           payload["status"] as? String == "requesting" {
            return ProviderActivityEvent(source: source, phase: .started)
        }
        return nil
    }
}

private func readableASCII(_ data: Data) -> String {
    let bytes = data.map { byte -> UInt8 in
        if byte == 10 || byte == 13 || byte == 9 || (32...126).contains(byte) {
            return byte
        }
        return 32
    }
    return String(decoding: bytes, as: UTF8.self)
}

final class ClaudeCloudActivityMonitor {
    private let queue = DispatchQueue(label: "thinkpeek.claude-cloud-activity",
                                      qos: .utility)
    private let directory: String
    private var offsets: [String: UInt64] = [:]
    private var buffers: [String: String] = [:]
    private var streamSources: [String: String] = [:]
    private var inspectedSizes: [String: UInt64] = [:]
    private var lastDiscovery = Date.distantPast
    private let lock = NSLock()
    private var pollInFlight = false

    init(directory: String? = nil) {
        self.directory = directory ?? ProcessInfo.processInfo.environment[
            "THINKPEEK_CLAUDE_CACHE"] ?? NSString(
                string: "~/Library/Application Support/Claude/Cache/Cache_Data")
                .expandingTildeInPath
    }

    @discardableResult
    func poll(completion: @escaping ([ProviderActivityEvent]) -> Void) -> Bool {
        lock.lock()
        guard !pollInFlight else { lock.unlock(); return false }
        pollInFlight = true
        lock.unlock()

        queue.async { [self] in
            if Date().timeIntervalSince(lastDiscovery) >= 1 {
                lastDiscovery = Date()
                discoverStreams()
            }
            var events: [ProviderActivityEvent] = []
            for (path, source) in streamSources {
                events += drain(path: path, source: source)
            }
            lock.lock()
            pollInFlight = false
            lock.unlock()
            DispatchQueue.main.async { completion(events) }
        }
        return true
    }

    private func discoverStreams() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory)
        else { return }
        for name in names {
            let path = directory + "/" + name
            guard streamSources[path] == nil,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let sizeNumber = attributes[.size] as? NSNumber else { continue }
            let size = sizeNumber.uint64Value
            guard inspectedSizes[path] != size else { continue }
            inspectedSizes[path] = size
            guard let handle = FileHandle(forReadingAtPath: path) else { continue }
            defer { try? handle.close() }
            let prefix = handle.readData(ofLength: 2048)
            let header = readableASCII(prefix)
            guard let source = cloudSource(fromCacheHeader: header) else { continue }
            streamSources[path] = source
            offsets[path] = 0
        }
    }

    private func drain(path: String, source: String) -> [ProviderActivityEvent] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let number = attributes[.size] as? NSNumber else { return [] }
        let size = number.uint64Value
        var offset = offsets[path] ?? 0
        if size < offset {
            offset = 0
            buffers[path] = ""
        }
        guard size > offset, let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        offsets[path] = offset + UInt64(data.count)
        let combined = (buffers[path] ?? "") + readableASCII(data)
        var lines = combined.components(separatedBy: "\n")
        buffers[path] = lines.removeLast()
        return claudeCloudActivityEvents(in: lines.joined(separator: "\n"),
                                         source: source)
    }
}

func cloudSource(fromCacheHeader header: String) -> String? {
    let marker = "/v1/code/sessions/"
    guard let markerRange = header.range(of: marker) else { return nil }
    let remainder = header[markerRange.upperBound...]
    guard let end = remainder.range(of: "/events/stream") else { return nil }
    let identifier = String(remainder[..<end.lowerBound])
    guard identifier.hasPrefix("cse_"), !identifier.isEmpty else { return nil }
    return "Claude · cloud chat \(identifier.suffix(6))"
}
