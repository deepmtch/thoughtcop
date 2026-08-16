// Discovering and naming Claude/Codex sessions across transcripts.

import Foundation

struct SessionInfo {
    let path: String
    let id: String        // first 8 chars of the uuid
    let title: String     // what the sidebar calls it
    let project: String   // slugified cwd, as Claude Code names it
    let modified: Date
}

func isCodexTranscript(_ path: String) -> Bool {
    path.hasPrefix(CODEX_SESSIONS + "/")
}

func codexSessionID(from path: String) -> String {
    let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    return String(stem.suffix(36)).lowercased()
}

private var codexTitleCache: [String: String] = [:]
private var codexTitleCacheTime = Date.distantPast
private let codexTitleCacheLock = NSLock()
private var claudeDesktopTitleCache: [String: String] = [:]
private var claudeDesktopTitleCacheTime = Date.distantPast
private let claudeDesktopTitleCacheLock = NSLock()

func codexTitles() -> [String: String] {
    codexTitleCacheLock.lock()
    defer { codexTitleCacheLock.unlock() }
    if Date().timeIntervalSince(codexTitleCacheTime) < 3 { return codexTitleCache }
    codexTitleCacheTime = Date()
    guard let text = try? String(contentsOfFile: CODEX_INDEX, encoding: .utf8) else { return [:] }
    var result: [String: String] = [:]
    for line in text.components(separatedBy: "\n") {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = object["id"] as? String,
              let title = object["thread_name"] as? String,
              !title.isEmpty else { continue }
        result[id.lowercased()] = title
    }
    codexTitleCache = result
    return result
}

func claudeSessionID(from path: String) -> String {
    ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
}

func claudeDesktopTitleRecord(from data: Data) -> (sessionID: String, title: String)? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let sessionID = object["cliSessionId"] as? String,
          let title = object["title"] as? String,
          !sessionID.isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return (sessionID.lowercased(), title)
}

/// Claude Desktop owns the title its session UI displays. Its local metadata
/// maps that user-facing title to the CLI transcript UUID Thinkpeek tails.
func claudeDesktopTitles() -> [String: String] {
    claudeDesktopTitleCacheLock.lock()
    defer { claudeDesktopTitleCacheLock.unlock() }
    if Date().timeIntervalSince(claudeDesktopTitleCacheTime) < 3 {
        return claudeDesktopTitleCache
    }
    claudeDesktopTitleCacheTime = Date()
    let fm = FileManager.default
    guard let files = fm.enumerator(atPath: CLAUDE_DESKTOP_SESSIONS) else { return [:] }
    var result: [String: String] = [:]
    for case let relative as String in files
        where relative.hasSuffix(".json") && relative.contains("local_") {
        let path = CLAUDE_DESKTOP_SESSIONS + "/" + relative
        guard let data = fm.contents(atPath: path),
              let record = claudeDesktopTitleRecord(from: data) else { continue }
        result[record.sessionID] = record.title
    }
    claudeDesktopTitleCache = result
    return result
}

struct TranscriptDiscoverySnapshot {
    let activePaths: [String]
    let sizes: [String: UInt64]
    let sessions: [SessionInfo]?
}

/// Recursively discovering transcripts can take long enough to freeze AppKit.
/// This coordinator guarantees that discovery runs off the main thread and that
/// a slow scan never overlaps with the next periodic request.
final class TranscriptDiscovery {
    private let queue: DispatchQueue
    private let fileProvider: () -> [String]
    private let stateLock = NSLock()
    private var scanInFlight = false

    init(fileProvider: @escaping () -> [String] = allTranscriptFiles,
         queue: DispatchQueue = DispatchQueue(
            label: "thinkpeek.transcript-discovery", qos: .utility)) {
        self.fileProvider = fileProvider
        self.queue = queue
    }

    @discardableResult
    func request(activeHours: Double = ACTIVE_HOURS,
                 includeSessions: Bool,
                 sessionHours: Double = 12,
                 sessionLimit: Int = 25,
                 completion: @escaping (TranscriptDiscoverySnapshot) -> Void) -> Bool {
        stateLock.lock()
        guard !scanInFlight else {
            stateLock.unlock()
            return false
        }
        scanInFlight = true
        stateLock.unlock()

        queue.async { [self] in
            let snapshot = makeTranscriptDiscoverySnapshot(
                paths: fileProvider(), activeHours: activeHours,
                includeSessions: includeSessions, sessionHours: sessionHours,
                sessionLimit: sessionLimit)
            DispatchQueue.main.async { [self] in
                stateLock.lock()
                scanInFlight = false
                stateLock.unlock()
                completion(snapshot)
            }
        }
        return true
    }
}

private func makeTranscriptDiscoverySnapshot(
    paths: [String], activeHours: Double, includeSessions: Bool,
    sessionHours: Double, sessionLimit: Int
) -> TranscriptDiscoverySnapshot {
    let fm = FileManager.default
    let now = Date()
    let activeCutoff = now.addingTimeInterval(-activeHours * 3600)
    let sessionCutoff = now.addingTimeInterval(-sessionHours * 3600)
    var sizes: [String: UInt64] = [:]
    var active: [(path: String, modified: Date)] = []
    var newestByRoot: [String: Date] = [:]

    for path in paths {
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
        if let size = attrs[.size] as? NSNumber { sizes[path] = size.uint64Value }
        guard let modified = attrs[.modificationDate] as? Date else { continue }
        if modified > activeCutoff { active.append((path, modified)) }
        if includeSessions, modified > sessionCutoff {
            let root = rootSessionPath(for: path)
            if newestByRoot[root] == nil || modified > newestByRoot[root]! {
                newestByRoot[root] = modified
            }
        }
    }

    let sessions: [SessionInfo]? = includeSessions ? newestByRoot
        .sorted { $0.value > $1.value }
        .prefix(sessionLimit)
        .map { path, modified in
            SessionInfo(path: path, id: sessionID(for: path),
                        title: sessionTitle(of: path) ?? "untitled",
                        project: platformName(for: path), modified: modified)
        } : nil
    return TranscriptDiscoverySnapshot(
        activePaths: active.sorted { $0.modified > $1.modified }.map(\.path),
        sizes: sizes, sessions: sessions)
}

/// Match the title shown by the owning app. Claude titles live in its transcript;
/// Codex task names live in ~/.codex/session_index.jsonl.
func sessionTitle(of path: String) -> String? {
    if isCodexTranscript(path) {
        let id = codexSessionID(from: path)
        return codexTitles()[id] ?? "task \(id.prefix(8))"
    }
    return preferredClaudeTitle(of: path, desktopTitles: claudeDesktopTitles())
}

func preferredClaudeTitle(of path: String,
                          desktopTitles: [String: String]) -> String? {
    if let desktopTitle = desktopTitles[claudeSessionID(from: path)] {
        return desktopTitle
    }
    return transcriptEmbeddedTitle(of: path)
}

private func transcriptEmbeddedTitle(of path: String) -> String? {
    // Title records are appended near the end. Reading only the tail avoids
    // repeatedly loading multi-megabyte transcripts on the AppKit main thread.
    guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? fh.close() }
    let size = (try? fh.seekToEnd()) ?? 0
    let start = size > 262_144 ? size - 262_144 : 0
    try? fh.seek(toOffset: start)
    var text = String(data: fh.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if start > 0, let newline = text.firstIndex(of: "\n") {
        text = String(text[text.index(after: newline)...])
    }
    var custom: String?, ai: String?
    for line in text.components(separatedBy: "\n").reversed() {
        guard line.contains("-title\""),
              let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { continue }
        if custom == nil, let t = obj["customTitle"] as? String { custom = t }
        if ai == nil, let t = obj["aiTitle"] as? String { ai = t }
        if custom != nil { break }
    }
    return custom ?? ai
}

/// All transcripts that may currently be producing output. Unlike the old
/// single-newest-file design, this includes concurrent sessions and sub-agents.
func activeTranscriptPaths(within hours: Double = ACTIVE_HOURS) -> [String] {
    let fm = FileManager.default
    let cutoff = Date().addingTimeInterval(-hours * 3600)
    var out: [(String, Date)] = []
    for path in allTranscriptFiles() {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let when = attrs[.modificationDate] as? Date, when > cutoff else { continue }
        out.append((path, when))
    }
    return out.sorted { $0.1 > $1.1 }.map(\.0)
}

/// Snapshot every existing file once at launch. When an old session becomes
/// active later, its tailer starts at this exact byte rather than at the new EOF,
/// so analysis written between discovery scans is still delivered exactly once.
func transcriptSizes() -> [String: UInt64] {
    let fm = FileManager.default
    var out: [String: UInt64] = [:]
    for path in allTranscriptFiles() {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { continue }
        out[path] = size.uint64Value
    }
    return out
}

/// A sub-agent transcript lives under <session uuid>/subagents/. Map it back to
/// the owning top-level transcript so pinning a session also follows its agents.
func rootSessionPath(for path: String) -> String {
    let file = path as NSString
    let parent = file.deletingLastPathComponent as NSString
    guard parent.lastPathComponent == "subagents" else { return path }
    let sessionDir = parent.deletingLastPathComponent as NSString
    return (sessionDir.deletingLastPathComponent as NSString)
        .appendingPathComponent(sessionDir.lastPathComponent + ".jsonl")
}

func sameTranscript(_ lhs: String, _ rhs: String) -> Bool {
    lhs.caseInsensitiveCompare(rhs) == .orderedSame
}

func platformName(for path: String) -> String {
    isCodexTranscript(path) ? "Codex" : "Claude"
}

func sessionID(for path: String) -> String {
    if isCodexTranscript(path) { return String(codexSessionID(from: path).prefix(8)) }
    return String((path as NSString).lastPathComponent.prefix(8))
}

/// Every Claude and Codex session touched recently, newest first.
func recentSessions(within hours: Double = 12, limit: Int = 25) -> [SessionInfo] {
    let fm = FileManager.default
    let cutoff = Date().addingTimeInterval(-hours * 3600)
    var newestByRoot: [String: Date] = [:]
    for path in allTranscriptFiles() {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let when = attrs[.modificationDate] as? Date, when > cutoff else { continue }
        let root = rootSessionPath(for: path)
        if newestByRoot[root] == nil || when > newestByRoot[root]! { newestByRoot[root] = when }
    }
    let out = newestByRoot.map { path, when in
        SessionInfo(path: path, id: sessionID(for: path),
                    title: sessionTitle(of: path) ?? "untitled",
                    project: platformName(for: path), modified: when)
    }
    return Array(out.sorted { $0.modified > $1.modified }.prefix(limit))
}
