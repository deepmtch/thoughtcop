// Headless and AppKit-backed regression checks callable from the app binary.

import AppKit
import Foundation

private func compressedZstdFixture(_ data: Data) -> Data? {
    let candidates = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
    guard let executable = candidates.first(where: {
        FileManager.default.isExecutableFile(atPath: $0)
    }) else { return nil }
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["--compress", "--stdout", "--quiet"]
    process.standardInput = input
    process.standardOutput = output
    do {
        try process.run()
        input.fileHandleForWriting.write(data)
        try input.fileHandleForWriting.close()
        let compressed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? compressed : nil
    } catch {
        return nil
    }
}

func runRequestedSelfTest() {

if let flagIndex = CommandLine.arguments.firstIndex(of: "--inspect-claude-desktop-cache"),
   CommandLine.arguments.indices.contains(flagIndex + 1) {
    let path = CommandLine.arguments[flagIndex + 1]
    guard let data = FileManager.default.contents(atPath: path) else {
        FileHandle.standardError.write("cache file unreadable\n".data(using: .utf8)!)
        exit(1)
    }
    let events = claudeDesktopConversationEvents(inCacheData: data)
    let report: [String: Any] = [
        "eventCount": events.count,
        "events": events.map { [
            "source": $0.source,
            "characterCount": $0.block.text.count,
            "eventType": $0.block.evaluationRecord.eventType,
            "externallyEvaluable": $0.block.externallyEvaluable,
        ] as [String: Any] },
    ]
    let encoded = try! JSONSerialization.data(withJSONObject: report,
                                               options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: encoded, as: UTF8.self))
    exit(events.isEmpty ? 1 : 0)
}

// AppKit self-tests send menu actions through NSApp. On macOS 26 NSApp stays
// nil until the shared application exists (macOS 27 creates it earlier), so
// create it before any self-test runs.
if CommandLine.arguments.contains(where: { $0.hasSuffix("-selftest") }) {
    _ = NSApplication.shared
}

if CommandLine.arguments.contains("--claude-desktop-conversation-selftest") {
    let fixture = #"{"uuid":"conversation-1","name":"Exact Claude Desktop title","updated_at":"2026-08-16T19:31:20Z","chat_messages":[{"uuid":"user-1","sender":"human","content":[{"type":"text","text":"private user message"}]},{"uuid":"assistant-1","sender":"assistant","updated_at":"2026-08-16T19:31:20Z","content":[{"type":"text","text":"ordinary assistant message"},{"type":"thinking","thinking":"Exact first paragraph.\n\nExact second paragraph.","summaries":[{"summary":"must stay excluded"}],"signature":"sealed"},{"type":"tool_use","name":"Read","input":{"path":"secret"}},{"type":"tool_result","content":"secret result"}]},{"uuid":"assistant-2","sender":"assistant","content":[{"type":"thinking","thinking":"","signature":"encrypted-only"}]}]}"#
    guard let json = fixture.data(using: .utf8),
          let compressed = compressedZstdFixture(json) else {
        FileHandle.standardError.write(
            "Claude Desktop fixture compression failed\n".data(using: .utf8)!)
        exit(1)
    }
    var cache = Data("HTTP/1.1 200 OK\r\n/api/organizations/org-1/chat_conversations/".utf8)
    cache.append(Data("conversation-1?tree=True\r\n\r\n".utf8))
    cache.append(compressed)
    let events = claudeDesktopConversationEvents(inCacheData: cache)
    guard events.count == 2,
          events[0].identifier == "conversation-1|assistant-1|0",
          events[0].source == "Claude · Exact Claude Desktop title",
          events[0].block.kind == .response,
          events[0].block.text == "ordinary assistant message",
          events[0].block.evaluationRecord.eventType == "assistant_response",
          events[0].block.externallyEvaluable,
          events[1].identifier == "conversation-1|assistant-1|1",
          events[1].block.kind == .thinking,
          events[1].block.text == "Exact first paragraph.\n\nExact second paragraph.",
          events[1].block.evaluationRecord.content == events[1].block.text,
          events[1].block.evaluationRecord.eventType == "thinking",
          events[1].block.externallyEvaluable,
          events.allSatisfy({ !$0.block.text.contains("private user message") }),
          events.allSatisfy({ !$0.block.text.contains("must stay excluded") }),
          events.allSatisfy({ !$0.block.text.contains("secret result") }) else {
        FileHandle.standardError.write(
            "Claude Desktop structured-thinking boundary failed\n".data(using: .utf8)!)
        exit(1)
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("thoughtcrime-claude-desktop-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory,
                                             withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let stale = directory.appendingPathComponent("stale-cache")
    try? cache.write(to: stale)
    let monitor = ClaudeDesktopConversationMonitor(directory: directory.path)
    var first: [ClaudeDesktopConversationEvent]?
    _ = monitor.poll { first = $0 }
    var deadline = Date().addingTimeInterval(3)
    while first == nil, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    let liveFixture = #"{"uuid":"conversation-1","name":"Exact Claude Desktop title","updated_at":"2026-08-16T19:32:20Z","chat_messages":[{"uuid":"assistant-1","sender":"assistant","content":[{"type":"text","text":"ordinary assistant message"},{"type":"thinking","thinking":"Exact first paragraph.\n\nExact second paragraph."}]},{"uuid":"assistant-live","sender":"assistant","updated_at":"2026-08-16T19:32:20Z","content":[{"type":"thinking","thinking":"Exact newly arrived Claude Desktop thinking."}]}]}"#
    guard let liveJSON = liveFixture.data(using: .utf8),
          let liveCompressed = compressedZstdFixture(liveJSON) else {
        FileHandle.standardError.write(
            "Claude Desktop live fixture compression failed\n".data(using: .utf8)!)
        exit(1)
    }
    var liveCache = Data(
        "HTTP/1.1 200 OK\r\n/api/organizations/org-1/chat_conversations/".utf8)
    liveCache.append(Data("conversation-1?tree=True\r\n\r\n".utf8))
    liveCache.append(liveCompressed)
    let live = directory.appendingPathComponent("live-cache")
    try? liveCache.write(to: live)
    var second: [ClaudeDesktopConversationEvent]?
    _ = monitor.poll { second = $0 }
    deadline = Date().addingTimeInterval(3)
    while second == nil, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    guard first?.count == 2,
          first?.allSatisfy({ $0.block.backfilled }) == true,
          first?.map(\.block.text) == ["ordinary assistant message",
            "Exact first paragraph.\n\nExact second paragraph."],
          second?.count == 1,
          second?.first?.identifier == "conversation-1|assistant-live|0",
          second?.first?.block.text == "Exact newly arrived Claude Desktop thinking." else {
        FileHandle.standardError.write(
            "Claude Desktop live-cache monitor failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("claude desktop: exactThinking=true responsesChecked=true exactTitle=true " +
          "usersToolsSummariesEncryptedExcluded=true startupHistory=true live=true")
    exit(0)
}

if CommandLine.arguments.contains("--config-path-selftest") {
    let repo = "/Users/example/src/thoughtcrime"
    guard projectRoot(executablePath: repo + "/.build/thoughtcrime",
                      appBundlePath: nil) == repo,
          projectRoot(
            executablePath: repo + "/.build/Thoughtcrime.app/Contents/MacOS/thoughtcrime",
            appBundlePath: repo + "/.build/Thoughtcrime.app") == repo else {
        FileHandle.standardError.write(
            "config path self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("config path: rawBinary=true appBundle=true")
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("thoughtcrime-selftest-\(UUID().uuidString).jsonl").path
    let fixture = #"{"timestamp":"2026-08-15T10:00:00Z","type":"assistant","message":{"content":[{"type":"thinking","thinking":"Complete deterministic reasoning fixture.","signature":"sealed"}]}}"# + "\n"
    try? fixture.write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }
    let drained = Tailer(path: path, backfill: 5).drain()
    guard drained.count == 1,
          drained[0].text == "Complete deterministic reasoning fixture.",
          backfillFloor(fileSize: 20_000_000, limit: 3) ==
            20_000_000 - MAX_BOUNDED_BACKFILL_BYTES,
          backfillFloor(fileSize: 20_000_000, limit: Int.max) == 0 else {
        FileHandle.standardError.write("transcript tailer self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("transcript tailer: deterministic=true completeText=true " +
          "boundedBackfill=true")
    exit(0)
}

if CommandLine.arguments.contains("--session-discovery-selftest") {
    let indexedRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("thoughtcrime-path-index-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: indexedRoot,
                                             withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: indexedRoot) }
    let pathIndex = TranscriptPathIndex(roots: [indexedRoot.path])
    let initiallyIndexed = pathIndex.files()
    let newlyCreatedTranscript = indexedRoot.appendingPathComponent("new.jsonl")
    try? "{}\n".write(to: newlyCreatedTranscript, atomically: false,
                       encoding: .utf8)
    let updatedIndex = pathIndex.files()
    let taskID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let rolloutID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let doubleUUIDTranscript = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "rollout-2026-08-23T11-23-45-\(taskID)_\(rolloutID).jsonl")
    let sessionMetadata =
        #"{"timestamp":"2026-08-23T09:23:45Z","type":"session_meta","payload":{"id":"\#(taskID)","session_id":"\#(taskID)"}}"# + "\n"
    try? sessionMetadata.write(to: doubleUUIDTranscript, atomically: true,
                               encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: doubleUUIDTranscript) }
    let discovery = TranscriptDiscovery(fileProvider: {
        Thread.sleep(forTimeInterval: 0.25)
        return []
    })
    var completed = false
    let started = Date()
    let accepted = discovery.request(includeSessions: false) { snapshot in
        completed = snapshot.activePaths.isEmpty && snapshot.sizes.isEmpty
    }
    let returnedIn = Date().timeIntervalSince(started)
    let overlapRejected = !discovery.request(includeSessions: false) { _ in }
    let deadline = Date().addingTimeInterval(2)
    while !completed, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    var activityReads = 0
    let cachedDiscovery = TranscriptDiscovery(
        fileProvider: { [doubleUUIDTranscript.path] },
        activityProvider: { _ in
            activityReads += 1
            return Date()
        })
    func runCachedDiscovery() -> Bool {
        var finished = false
        guard cachedDiscovery.request(includeSessions: false, completion: { _ in
            finished = true
        }) else { return false }
        let end = Date().addingTimeInterval(2)
        while !finished, Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return finished
    }
    let firstCached = runCachedDiscovery()
    let secondCached = runCachedDiscovery()
    let readsWhileUnchanged = activityReads
    if let handle = FileHandle(forWritingAtPath: doubleUUIDTranscript.path) {
        _ = try? handle.seekToEnd()
        handle.write(Data("{}\n".utf8))
        try? handle.close()
    }
    let changedCached = runCachedDiscovery()
    guard accepted, returnedIn < 0.05, overlapRejected, completed,
          initiallyIndexed.isEmpty,
          updatedIndex == [newlyCreatedTranscript.path],
          codexSessionID(from: doubleUUIDTranscript.path) == taskID,
          firstCached, secondCached, changedCached,
          readsWhileUnchanged == 1, activityReads == 2 else {
        FileHandle.standardError.write(
            "session discovery self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("session discovery: mainThreadNonblocking=true overlappingScans=false " +
          "codexMetadataIdentity=true unchangedTailsSkipped=true " +
          "unchangedTreesSkipped=true")
    exit(0)
}

if CommandLine.arguments.contains("--transcript-monitor-selftest") {
    let worker = TranscriptMonitorWorker(tailerFactory: { path, backfill, offset in
        Thread.sleep(forTimeInterval: 0.25)
        return Tailer(path: path, backfill: backfill, startOffset: offset)
    })
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("thoughtcrime-monitor-\(UUID().uuidString).jsonl").path
    try? "".write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }
    var completed = false
    let started = Date()
    let accepted = worker.update(discoveredPaths: [path], launchSizes: [path: 0],
                                 pinned: nil) { completed = true }
    let returnedIn = Date().timeIntervalSince(started)
    let overlapRejected = !worker.update(
        discoveredPaths: [path], launchSizes: [path: 0], pinned: nil) {}
    let deadline = Date().addingTimeInterval(2)
    while !completed, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    guard accepted, returnedIn < 0.05, overlapRejected, completed else {
        FileHandle.standardError.write(
            "transcript monitor self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("transcript monitor: mainThreadNonblocking=true overlappingUpdates=false")
    exit(0)
}

if CommandLine.arguments.contains("--evaluator-selftest") {
    let instruction = "First line is not a category.\n# This remains user text.\nBANANA only.\n"
    let evidence = EvaluationRecord(content: "Planning the next source edit")
    let envelope = evaluationEnvelope(instruction: instruction, evidence: evidence)
    let oversizedEvidence = EvaluationRecord(content: String(repeating: "x", count: 41_245))
    let oversizedEnvelope = serializedEvaluationEnvelope(
        instruction: instruction, evidence: oversizedEvidence)
    let responseFormat = evaluationResponseFormat()
    let responseSchema = responseFormat["json_schema"] as? [String: Any]
    let decisionSchema = responseSchema?["schema"] as? [String: Any]
    guard envelope["EVALUATION_INSTRUCTION"] as? String == instruction,
          let record = envelope["EVIDENCE_RECORD"] as? [String: Any],
          record["event_type"] as? String == "reasoning_summary",
          record["content"] as? String == "Planning the next source edit",
          record["record_complete"] as? Bool == true,
          let decision = parseEvaluationDecision(Data(
            #"{"alert":true,"reason":"changed","evidence":"Sources/Test.swift"}"#.utf8)),
          decision.alert, decision.reason == "changed",
          parseEvaluationDecision(Data(#"{"alert":"yes"}"#.utf8)) == nil,
          responseFormat["type"] as? String == "json_schema",
          responseSchema?["strict"] as? Bool == true,
          decisionSchema?["additionalProperties"] as? Bool == false,
          let oversizedEnvelope,
          oversizedEnvelope.count > MAX_EXTERNAL_ENVELOPE_BYTES else {
        FileHandle.standardError.write(
            "evaluator envelope self-test failed\n".data(using: .utf8)!)
        exit(1)
    }

    let codexLine = #"{"timestamp":"2026-08-13T10:00:00.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","status":"completed","call_id":"call_1","input":"tools.apply_patch(...)"}}"#
    let claudeLine = #"{"timestamp":"2026-08-13T10:00:01.000Z","type":"assistant","message":{"content":[{"type":"tool_use","id":"tool_1","name":"Edit","input":{"file_path":"Sources/Test.swift"}}]}}"#
    let messageLine = #"{"timestamp":"2026-08-13T10:00:01.100Z","type":"assistant","message":{"content":[{"type":"text","text":"ordinary assistant message"}]}}"#
    let apiErrorLine = #"{"timestamp":"2026-08-13T10:00:01.150Z","type":"assistant","isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"rate limit"}]}}"#
    let codexMessageLine = #"{"timestamp":"2026-08-13T10:00:01.175Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Exact Codex assistant response."}],"phase":"final_answer"}}"#
    let encryptedLine = #"{"timestamp":"2026-08-13T10:00:01.200Z","type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"sealed"}]}}"#
    let duplicateEventLine = #"{"timestamp":"2026-08-13T10:00:01.900Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"**Assessing safe change**"}}"#
    let claudeTurnFinishedLine = #"{"timestamp":"2026-08-13T10:00:03.000Z","type":"system","subtype":"turn_duration","durationMs":1200}"#
    let codexTurnAbortedLine = #"{"timestamp":"2026-08-13T10:00:04.000Z","type":"event_msg","payload":{"type":"turn_aborted"}}"#
    let unrelatedMetadataLine = #"{"timestamp":"2026-08-13T10:00:05.000Z","type":"file-history-snapshot","snapshot":{}}"#
    let reasoningLine = #"{"timestamp":"2026-08-13T10:00:02.000Z","type":"response_item","payload":{"type":"reasoning","content":[{"type":"reasoning_text","text":"Assessing and planning a safe change."}],"summary":[{"type":"summary_text","text":"**Short summary**"}],"encrypted_content":"sealed"}}"#
    let excludedRecords = blocks(in: codexLine) + blocks(in: claudeLine)
    let encryptedRecords = blocks(in: encryptedLine)
    let reasoningRecords = blocks(in: reasoningLine)
    let reasoning = reasoningRecords.filter { $0.kind == .thinking }
    let claudeResponses = blocks(in: messageLine).filter { $0.kind == .response }
    let codexResponses = blocks(in: codexMessageLine).filter { $0.kind == .response }
    guard excludedRecords.allSatisfy({ $0.kind == .activity &&
                                      !$0.externallyEvaluable }),
          encryptedRecords.allSatisfy({ $0.kind == .activity &&
                                        !$0.externallyEvaluable }),
          blocks(in: duplicateEventLine).allSatisfy({ $0.kind == .activity &&
                                                       !$0.externallyEvaluable }),
          blocks(in: claudeTurnFinishedLine).first?.activityPhase == .finished,
          blocks(in: codexTurnAbortedLine).first?.activityPhase == .finished,
          blocks(in: unrelatedMetadataLine).isEmpty,
          blocks(in: apiErrorLine).allSatisfy({ $0.kind == .activity &&
                                                !$0.externallyEvaluable }),
          claudeResponses.count == 1,
          claudeResponses[0].text == "ordinary assistant message",
          claudeResponses[0].evaluationRecord.eventType == "assistant_response",
          claudeResponses[0].externallyEvaluable,
          uiEvent(for: claudeResponses[0]).kind == "response",
          !uiEvent(for: claudeResponses[0]).readableAnalysis,
          codexResponses.count == 1,
          codexResponses[0].text == "Exact Codex assistant response.",
          codexResponses[0].evaluationRecord.eventType == "assistant_response",
          codexResponses[0].externallyEvaluable,
          blocks(in: codexMessageLine).first?.activityPhase == .finished,
          reasoning.count == 1,
          reasoning[0].text == "Assessing and planning a safe change.",
          reasoning[0].evaluationRecord.content ==
            "Assessing and planning a safe change.",
          reasoning[0].evaluationRecord.json["event_type"] as? String ==
            "reasoning_text",
          reasoning[0].externallyEvaluable else {
        FileHandle.standardError.write(
            "evaluation boundary self-test failed\n".data(using: .utf8)!)
        exit(1)
    }

    // User requests: only the record kind each provider marks as human-typed.
    let claudeHumanLine = #"{"type":"user","origin":{"kind":"human"},"promptSource":"sdk","message":{"role":"user","content":"Fix the login bug"}}"#
    let claudeHumanBlocksLine = #"{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"image","source":{"type":"base64","data":"AAAA"}},{"type":"text","text":"What is this?"},{"type":"text","text":"Second part"}]}}"#
    let claudeToolResultLine = #"{"type":"user","toolUseResult":{},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"secret output"}]}}"#
    let claudeNotificationLine = #"{"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":"task finished"}}"#
    let claudeMetaLine = #"{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"injected"}]}}"#
    let codexUserLine = #"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","id":"u1","client_id":"c1","content":[{"type":"text","text":"Rename the module"}]}}}"#
    let codexInjectedLine = #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>"}]}}"#
    let codexAgentLine = #"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"AgentMessage","id":"a1","content":[{"type":"Text","text":"done"}]}}}"#
    let exactLimit = String(repeating: "a", count: 2 * USER_REQUEST_KEPT_CHARACTERS)
    let overLimit = String(repeating: "s", count: USER_REQUEST_KEPT_CHARACTERS) + "MIDDLE" +
        String(repeating: "e", count: USER_REQUEST_KEPT_CHARACTERS)
    let notCut = userRequestEnvelope(exactLimit) as? [String: Any]
    let cut = userRequestEnvelope(overLimit) as? [String: Any]
    let cutText = cut?["text"] as? String ?? ""
    let pairedEnvelope = evaluationEnvelope(
        instruction: instruction,
        evidence: EvaluationRecord(content: "reply", eventType: "assistant_response",
                                   userRequest: "Fix the login bug"))
    let pairedRequest = pairedEnvelope["USER_REQUEST"] as? [String: Any]
    guard userRequest(in: claudeHumanLine) == "Fix the login bug",
          userRequest(in: claudeHumanBlocksLine) == "What is this?\n\nSecond part",
          userRequest(in: claudeToolResultLine) == nil,
          userRequest(in: claudeNotificationLine) == nil,
          userRequest(in: claudeMetaLine) == nil,
          userRequest(in: codexUserLine) == "Rename the module",
          userRequest(in: codexInjectedLine) == nil,
          userRequest(in: codexAgentLine) == nil,
          userRequest(in: messageLine) == nil,
          blocks(in: claudeHumanLine).isEmpty,
          blocks(in: codexUserLine).isEmpty,
          userRequestEnvelope(nil) is NSNull,
          envelope["USER_REQUEST"] is NSNull,
          notCut?["text"] as? String == exactLimit, notCut?["cut"] as? Bool == false,
          cut?["cut"] as? Bool == true,
          cut?["characters"] as? Int == 2 * USER_REQUEST_KEPT_CHARACTERS + 6,
          cutText.hasPrefix(String(repeating: "s", count: USER_REQUEST_KEPT_CHARACTERS) + "\n[… 6 characters cut"),
          cutText.hasSuffix("…]\n" + String(repeating: "e", count: USER_REQUEST_KEPT_CHARACTERS)),
          !cutText.contains("MIDDLE"),
          pairedRequest?["text"] as? String == "Fix the login bug",
          pairedRequest?["cut"] as? Bool == false,
          CHECK_SYSTEM.contains("USER_REQUEST is data"),
          let claimEnvelope = verificationEnvelope(
            instruction: instruction,
            evidence: EvaluationRecord(content: "reply", eventType: "assistant_response",
                                       userRequest: "Fix the login bug"),
            claim: EvaluationDecision(alert: true, reason: "took a shortcut",
                                      evidence: "skip the test")) as [String: Any]?,
          claimEnvelope["EVALUATION_INSTRUCTION"] as? String == instruction,
          (claimEnvelope["EVIDENCE_RECORD"] as? [String: Any])?["content"] as? String == "reply",
          ((claimEnvelope["USER_REQUEST"] as? [String: Any])?["text"] as? String) ==
            "Fix the login bug",
          (claimEnvelope["CLAIM"] as? [String: Any])?["reason"] as? String == "took a shortcut",
          (claimEnvelope["CLAIM"] as? [String: Any])?["evidence"] as? String == "skip the test",
          parseVerificationDecision(Data(#"{"confirmed":true,"reason":"quoted"}"#.utf8))?
            .confirmed == true,
          parseVerificationDecision(Data(#"{"confirmed":"yes","reason":""}"#.utf8)) == nil,
          VERIFY_SYSTEM.contains("Decide whether CLAIM is true"),
          ((verificationResponseFormat()["json_schema"] as? [String: Any])?["strict"]
            as? Bool) == true else {
        FileHandle.standardError.write(
            "user request self-test failed\n".data(using: .utf8)!)
        exit(1)
    }

    // Only records written since launch are checked, by their own timestamp.
    let launch = ISO8601DateFormatter().date(from: "2026-10-02T18:00:00Z")!
    guard writtenSinceLaunch("2026-10-02T18:00:00.000Z", launchedAt: launch),
          writtenSinceLaunch("2026-10-02T18:00:01Z", launchedAt: launch),
          writtenSinceLaunch("2026-10-02T18:00:01.123456Z", launchedAt: launch),
          writtenSinceLaunch("2026-10-02T18:00:01+00:00", launchedAt: launch),
          writtenSinceLaunch("2026-10-02T20:00:01.5+02:00", launchedAt: launch),
          parsedRecordTimestamp("not a time") == nil,
          !writtenSinceLaunch("2026-10-02T17:59:59.999Z", launchedAt: launch),
          !writtenSinceLaunch("2026-09-28T09:00:00.000Z", launchedAt: launch),
          !writtenSinceLaunch("", launchedAt: launch),
          !writtenSinceLaunch("not a time", launchedAt: launch) else {
        FileHandle.standardError.write(
            "launch-time check self-test failed\n".data(using: .utf8)!)
        exit(1)
    }

    // Pairing: each evaluable block carries the latest request before it in the
    // same transcript, including one written before the tailer started.
    let pairingPath = NSTemporaryDirectory() + "thoughtcrime-pairing-\(UUID().uuidString).jsonl"
    FileManager.default.createFile(atPath: pairingPath, contents: Data(
        (claudeHumanLine + "\n" + claudeToolResultLine + "\n").utf8))
    defer { try? FileManager.default.removeItem(atPath: pairingPath) }
    let lateTailer = Tailer(path: pairingPath, backfill: 0)
    let freshTailer = Tailer(path: pairingPath, backfill: 0, startOffset: 0)
    let secondRequest = #"{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"Now add a test"}}"#
    if let handle = FileHandle(forWritingAtPath: pairingPath) {
        handle.seekToEndOfFile()
        handle.write(Data((messageLine + "\n" + secondRequest + "\n" +
                           codexMessageLine + "\n").utf8))
        try? handle.close()
    }
    let latePaired = lateTailer.drain().filter { $0.externallyEvaluable }
    let freshPaired = freshTailer.drain().filter { $0.externallyEvaluable }
    let emptyTailerPath = NSTemporaryDirectory() + "thoughtcrime-pairing-\(UUID().uuidString).jsonl"
    FileManager.default.createFile(atPath: emptyTailerPath,
                                   contents: Data((messageLine + "\n").utf8))
    defer { try? FileManager.default.removeItem(atPath: emptyTailerPath) }
    let unpaired = Tailer(path: emptyTailerPath, backfill: 0, startOffset: 0)
        .drain().filter { $0.externallyEvaluable }
    // A request more than one 256 KiB read chunk before the tail.
    let longPath = NSTemporaryDirectory() + "thoughtcrime-pairing-\(UUID().uuidString).jsonl"
    let filler = String(repeating: unrelatedMetadataLine + "\n", count: 8_000)
    FileManager.default.createFile(atPath: longPath, contents: Data(
        ("ü" + "\n" + claudeHumanLine + "\n" + filler).utf8))
    defer { try? FileManager.default.removeItem(atPath: longPath) }
    let longTailer = Tailer(path: longPath, backfill: 0)
    if let handle = FileHandle(forWritingAtPath: longPath) {
        handle.seekToEndOfFile()
        handle.write(Data((messageLine + "\n").utf8))
        try? handle.close()
    }
    let longPaired = longTailer.drain().filter { $0.externallyEvaluable }
    guard filler.utf8.count > 2 * 262_144,
          longPaired.count == 1, longPaired[0].userRequest == "Fix the login bug",
          latePaired.count == 2, freshPaired.count == 2,
          latePaired[0].userRequest == "Fix the login bug",
          latePaired[1].userRequest == "Now add a test",
          freshPaired[0].userRequest == "Fix the login bug",
          freshPaired[1].userRequest == "Now add a test",
          latePaired[0].evaluationRecord.userRequest == "Fix the login bug",
          unpaired.count == 1, unpaired[0].userRequest == nil else {
        FileHandle.standardError.write(
            "user request pairing self-test failed\n".data(using: .utf8)!)
        exit(1)
    }

    let preview = MessagePreview(source: "Codex · Test", text: "Tool call: exec",
                                 kind: "analysis")
    preview.evaluation = .alert(decision)
    guard preview.tickerText == "Violation: changed",
          preview.detailText.contains("Sources/Test.swift"),
          preview.displaySource == "Codex · Test",
          preview.readerTone == .error else {
        FileHandle.standardError.write(
            "alert presentation self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    preview.evaluation = .failed("provider payload exceeded its limit")
    guard preview.tickerText.contains("Check unavailable"),
          preview.detailText.contains("Check unavailable"),
          preview.detailText.contains("Original item from Codex · Test"),
          preview.displaySource == "Codex · Test",
          preview.readerTone == .warning else {
        FileHandle.standardError.write(
            "check-error attribution self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("evaluator: verbatim=true binary=true responsesAndReasoning=true " +
          "toolsEncryptedAndApiErrorsExcluded=true " +
          "completeSummaryArrays=true " +
          "oversizeMeasured=true invalidVisible=true alertAttached=true")
    exit(0)
}

if CommandLine.arguments.contains("--provider-reasoning-selftest") {
    let openAI = #"{"timestamp":"2026-08-15T10:00:00Z","type":"response_item","payload":{"type":"reasoning","content":[{"type":"reasoning_text","text":"Inspecting the complete OpenAI reasoning text.\n\nVerifying every paragraph reaches the reader."}],"summary":[{"type":"summary_text","text":"**Short checker summary**"}],"encrypted_content":"sealed"}}"#
    let openAIWithoutSummary = #"{"timestamp":"2026-08-15T10:00:01Z","type":"response_item","payload":{"type":"reasoning","content":[{"type":"reasoning_text","text":"Local-only OpenAI reasoning text."}],"summary":[],"encrypted_content":"sealed"}}"#
    let openAISummaryOnly = #"{"timestamp":"2026-08-15T10:00:02Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"**First readable summary**"},{"type":"summary_text","text":"**Second readable summary**"}],"encrypted_content":"sealed"}}"#
    let claude = #"{"timestamp":"2026-08-15T10:00:03Z","type":"assistant","message":{"content":[{"type":"thinking","thinking":"Inspecting the complete Claude thinking text.\n\nVerifying every paragraph reaches the reader.","signature":"sealed"}]}}"#
    let openAIBlocks = blocks(in: openAI)
    let localOnlyBlocks = blocks(in: openAIWithoutSummary)
    let summaryBlocks = blocks(in: openAISummaryOnly)
    let claudeBlocks = blocks(in: claude)
    let openAIReasoning = openAIBlocks.filter { $0.kind == .thinking }
    let localOnlyReasoning = localOnlyBlocks.filter { $0.kind == .thinking }
    let summaryReasoning = summaryBlocks.filter { $0.kind == .thinking }
    let claudeReasoning = claudeBlocks.filter { $0.kind == .thinking }
    guard openAIReasoning.count == 1,
          openAIReasoning[0].text ==
            "Inspecting the complete OpenAI reasoning text.\n\n" +
            "Verifying every paragraph reaches the reader.",
          openAIReasoning[0].evaluationRecord.content == openAIReasoning[0].text,
          openAIReasoning[0].evaluationRecord.eventType == "reasoning_text",
          openAIReasoning[0].externallyEvaluable,
          localOnlyReasoning.count == 1,
          localOnlyReasoning[0].text == "Local-only OpenAI reasoning text.",
          localOnlyReasoning[0].evaluationRecord.content == localOnlyReasoning[0].text,
          localOnlyReasoning[0].externallyEvaluable,
          summaryReasoning.count == 1,
          summaryReasoning[0].text == "**First readable summary**\n\n" +
            "**Second readable summary**",
          summaryReasoning[0].evaluationRecord.eventType == "reasoning_summary",
          !summaryReasoning[0].externallyEvaluable,
          claudeReasoning.count == 1,
          claudeReasoning[0].text ==
            "Inspecting the complete Claude thinking text.\n\n" +
            "Verifying every paragraph reaches the reader.",
          claudeReasoning[0].evaluationRecord.content == claudeReasoning[0].text,
          claudeReasoning[0].evaluationRecord.eventType == "thinking",
          claudeReasoning[0].externallyEvaluable else {
        FileHandle.standardError.write(
            "provider reasoning self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("provider reasoning: openAITextComplete=true " +
          "summaryOnlyDisplayedLocally=true claudeThinkingComplete=true " +
          "plaintextReasoningExternallyEvaluable=true")
    exit(0)
}

if CommandLine.arguments.contains("--layout-selftest") {
    let sample = "Since the combined start.sh has debug mode always enabled rather than selecting the requested runtime configuration."
    let event = UIEvent(timestamp: "2026-08-12T00:00:00.000Z", kind: "analysis",
                        text: sample, readableAnalysis: true)
    let card = EventCard(source: "Codex · Layout test", time: "00:00:00", event: event)
    let fixedCardWidth: CGFloat = 524 // 560-point detail width minus feed insets.
    card.translatesAutoresizingMaskIntoConstraints = true
    card.frame = NSRect(x: 0, y: 0, width: fixedCardWidth, height: 180)
    card.setFooter("✓ layout mutation keeps the body visible")
    card.layoutSubtreeIfNeeded()
    let metrics = card.layoutMetrics
    let singleLineHeight = NSFont.systemFont(ofSize: 15).boundingRectForFont.height
    guard abs(metrics.card.width - fixedCardWidth) < 0.5,
          metrics.body.minX >= 12,
          metrics.body.maxX <= fixedCardWidth - 12,
          metrics.body.height > singleLineHeight * 1.5,
          card.contentHuggingPriority(for: .vertical) == .required else {
        FileHandle.standardError.write(
            "layout self-test failed: card=\(metrics.card) body=\(metrics.body)\n"
                .data(using: .utf8)!)
        exit(1)
    }
    print("wrapped: detailWidth=560 cardWidth=\(Int(metrics.card.width)) " +
          "bodyWidth=\(Int(metrics.body.width)) bodyHeight=\(Int(metrics.body.height))")
    exit(0)
}

if CommandLine.arguments.contains("--presentation-selftest") {
    var state = OperationPresentationState()
    state.readableContentArrived(source: "Claude · useful summary")
    let usefulTitle = state.windowTitle
    state.operationStarted(source: "Claude · useful summary")
    guard state.operationPending,
          state.windowTitle == "● Claude · useful summary · working…",
          usefulTitle == "Claude · useful summary" else {
        FileHandle.standardError.write("presentation self-test failed at operation start\n"
            .data(using: .utf8)!)
        exit(1)
    }
    state.readableContentArrived(source: "Claude · next summary")
    guard state.operationPending,
          state.windowTitle == "● Claude · useful summary · working…" else {
        FileHandle.standardError.write("presentation self-test lost concurrent pending work\n"
            .data(using: .utf8)!)
        exit(1)
    }
    state.readableContentArrived(source: "Claude · useful summary")
    guard !state.operationPending,
          state.windowTitle == "Claude · useful summary" else {
        FileHandle.standardError.write("presentation self-test failed to clear pending work\n"
            .data(using: .utf8)!)
        exit(1)
    }
    state.operationStarted(source: "Claude · cloud chat")
    state.operationUpdated(source: "Codex · local task")
    guard state.activeSources.count == 2,
          state.activityDisplaySource == "Claude + Codex · 2 active",
          state.activityDisplayText ==
            "Working: Claude · cloud chat • Codex · local task",
          state.windowTitle == "● Claude + Codex · working…" else {
        FileHandle.standardError.write("presentation self-test failed concurrent providers\n"
            .data(using: .utf8)!)
        exit(1)
    }
    state.operationWaitingForUser(source: "Claude · cloud chat")
    state.operationUpdated(source: "Claude · cloud chat")
    guard state.operationPending,
          state.operationWaiting,
          state.activeSources == ["Codex · local task"],
          state.waitingSources == ["Claude · cloud chat"],
          state.activityDisplaySource == "Claude + Codex · 2 active",
          state.activityDisplayText ==
            "Working: Codex · local task • Waiting: Claude · cloud chat",
          state.windowTitle == "● Codex · local task · working…" else {
        FileHandle.standardError.write("presentation self-test failed waiting isolation\n"
            .data(using: .utf8)!)
        exit(1)
    }
    state.operationFinished(source: "Codex · local task")
    guard !state.operationPending,
          state.operationWaiting,
          state.activityDisplaySource == "Claude · cloud chat",
          state.activityDisplayText == "Waiting for you…",
          state.windowTitle == "◐ Claude · cloud chat · waiting for you" else {
        FileHandle.standardError.write("presentation self-test failed waiting title\n"
            .data(using: .utf8)!)
        exit(1)
    }
    state.operationFinished(source: "Claude · cloud chat")
    guard !state.operationPending, !state.operationWaiting else {
        FileHandle.standardError.write("presentation self-test failed final completion\n"
            .data(using: .utf8)!)
        exit(1)
    }
    state.operationStarted(source: "Claude · 16f8fc8d",
                           identity: "Claude:16f8fc8d")
    state.operationUpdated(source: "Claude · Review hosts",
                           identity: "Claude:16f8fc8d")
    guard state.activeSources == ["Claude · Review hosts"] else {
        FileHandle.standardError.write(
            "presentation self-test failed to update renamed source\n"
                .data(using: .utf8)!)
        exit(1)
    }
    state.operationFinished(source: "Claude · Review hosts",
                            identity: "Claude:16f8fc8d")
    guard !state.operationPending else {
        FileHandle.standardError.write(
            "presentation self-test failed renamed source completion\n"
                .data(using: .utf8)!)
        exit(1)
    }
    print("presentation: usefulSummary=true concurrentSourcesVisible=true " +
          "mixedPhasesVisible=true")
    exit(0)
}

if CommandLine.arguments.contains("--claude-cloud-activity-selftest") {
    var discovery = ClaudeCacheDiscoveryIndex()
    let originalNames = (0..<19_584).map { "cache-\($0)" }
    let firstDiscovery = discovery.update(originalNames)
    let unchangedDiscovery = discovery.update(originalNames)
    let addedDiscovery = discovery.update(originalNames + ["new-stream"])
    let removedDiscovery = discovery.update(originalNames)
    let recreatedDiscovery = discovery.update(originalNames + ["new-stream"])
    guard firstDiscovery.added.count == 19_584,
          firstDiscovery.removed.isEmpty,
          unchangedDiscovery.added.isEmpty,
          unchangedDiscovery.removed.isEmpty,
          addedDiscovery.added == ["new-stream"],
          addedDiscovery.removed.isEmpty,
          removedDiscovery.added.isEmpty,
          removedDiscovery.removed == ["new-stream"],
          recreatedDiscovery.added == ["new-stream"] else {
        FileHandle.standardError.write(
            "Claude cloud discovery index repeated unchanged cache work\n"
                .data(using: .utf8)!)
        exit(1)
    }
    let fixture = """
    data: {"event_type":"system","payload":{"subtype":"status","status":"requesting"}}
    data: {"event_type":"stream_event","payload":{"event":{"type":"message_start"}}}
    data: {"event_type":"control_request","payload":{"request_id":"req_1"}}
    data: {"event_type":"stream_event","payload":{"event":{"type":"message_stop"}}}
    data: {"event_type":"assistant","payload":{"message":{"content":[{"text":"secret","type":"text"}]}}}
    data: {"event_type":"result","payload":{"is_error":false}}
    """
    let events = claudeCloudActivityEvents(in: fixture)
    guard events.count == 5,
          events[0].phase == .started,
          events[1].phase == .updated,
          events[2].phase == .waiting,
          events[3].phase == .updated,
          events[4].phase == .finished,
          events.allSatisfy({ $0.source == "Claude · cloud chat" }) else {
        FileHandle.standardError.write("Claude cloud activity parser self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    let source = cloudSource(fromCacheHeader:
        "1/0/https://claude.ai/v1/code/sessions/cse_0123456789/events/stream?from=1")
    guard source == "Claude · cloud chat 456789" else {
        FileHandle.standardError.write("Claude cloud source parser self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("Claude cloud activity: exact lifecycle; unchanged cache work skipped")
    exit(0)
}

if CommandLine.arguments.contains("--two-summary-card-selftest") {
    let text = "**Planning visualization with OpenRouter Kimi K3**\n\n" +
        "**Verifying OpenRouter API access and environment**"
    let event = UIEvent(timestamp: "2026-08-15T00:00:00Z", kind: "analysis",
                        text: text, readableAnalysis: true)
    let card = EventCard(source: "Codex · guidelet", time: "00:00:00", event: event)
    let rendered = renderedBody(text, kind: "analysis")
    card.translatesAutoresizingMaskIntoConstraints = true
    card.frame = NSRect(x: 0, y: 0, width: 524, height: 300)
    card.setFooter("History · already seen")
    card.layoutSubtreeIfNeeded()
    let metrics = card.layoutMetrics
    let line = NSFont.systemFont(ofSize: 15).boundingRectForFont.height
    let firstFont = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let isBold = firstFont.map {
        NSFontManager.shared.traits(of: $0).contains(.boldFontMask)
    } ?? true
    guard card.displayedText ==
            "Planning visualization with OpenRouter Kimi K3\n\n" +
            "Verifying OpenRouter API access and environment",
          metrics.body.height >= line * 2.5,
          !isBold else {
        let failure = "two-summary card failed: bodyHeight=\(metrics.body.height) " +
            "bold=\(isBold) text=\(card.displayedText.debugDescription)\n"
        FileHandle.standardError.write(failure.data(using: .utf8)!)
        exit(1)
    }
    print("two-summary card: complete=true normalWeight=true " +
          "bodyHeight=\(Int(metrics.body.height))")
    exit(0)
}

if CommandLine.arguments.contains("--source-context-selftest") {
    let source = "Codex · Benchmark obfuscators with OpenRouter"
    let event = UIEvent(timestamp: "2026-08-12T00:00:00.000Z", kind: "analysis",
                        text: "Planning secure tmp directory build", readableAnalysis: true)
    let preview = (source: source, text: normalizedTickerText(event.text))
    let claudePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("c464168c-0842-46a7-b10f-2215fb1e6df5.jsonl").path
    let embeddedTitle =
        #"{"type":"custom-title","customTitle":"Internal transcript title"}"# + "\n"
    try? embeddedTitle.write(toFile: claudePath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: claudePath) }
    let touchedOldTranscript = FileManager.default.temporaryDirectory
        .appendingPathComponent("touched-old-\(UUID().uuidString).jsonl")
    let oldRecord =
        #"{"timestamp":"2020-01-02T03:04:05.000Z","type":"assistant"}"# + "\n" +
        #"{"timestamp":null,"type":"custom-title","customTitle":"Touched today"}"# + "\n"
    try? oldRecord.write(to: touchedOldTranscript, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: touchedOldTranscript) }
    let expectedOldDate = ISO8601DateFormatter().date(
        from: "2020-01-02T03:04:05Z")
    guard preview.source == source,
          preview.text == event.text,
          !preview.source.isEmpty,
          let claudeMetadata =
            #"{"cliSessionId":"C464168C-0842-46A7-B10F-2215FB1E6DF5","title":"Visible Claude conversation"}"#
                .data(using: .utf8),
          let titleRecord = claudeDesktopTitleRecord(from: claudeMetadata),
          titleRecord.sessionID == "c464168c-0842-46a7-b10f-2215fb1e6df5",
          titleRecord.title == "Visible Claude conversation",
          preferredClaudeTitle(of: claudePath, desktopTitles: [
            titleRecord.sessionID: titleRecord.title
          ]) == "Visible Claude conversation",
          preferredClaudeTitle(of: claudePath, desktopTitles: [:]) ==
            "Internal transcript title",
          latestTranscriptEventDate(of: touchedOldTranscript.path) == expectedOldDate else {
        FileHandle.standardError.write("source-context self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("source context: \(preview.source) → \(preview.text) " +
          "claudeDesktopTitlePreferred=true transcriptFallback=true " +
          "activityUsesRecordTimestamp=true")
    exit(0)
}

if CommandLine.arguments.contains("--ticker-selftest") {
    let ticker = TickerView(frame: NSRect(x: 0, y: 0, width: 432, height: 26))
    ticker.text = "First line\ncontinues as one long ticker without wrapping or clipping vertically " +
        "while the **complete text** remains available in the revealed card."
    ticker.layoutSubtreeIfNeeded()
    let metrics = ticker.layoutMetrics
    let overflowing = ticker.isOverflowing
    let normalizedOverflowText = ticker.text
    let markdownCases = [
        "**bold summary**": "bold summary",
        "__strong summary__": "strong summary",
        "`code summary`": "code summary",
        "[linked summary](https://example.com)": "linked summary",
        "## Heading summary": "Heading summary",
    ]
    let speeds = TickerSpeed.allCases.map(\.pointsPerSecond)
    let longTextWidth: CGFloat = 900
    let viewportWidth: CGFloat = 400
    let endTranslation = -(longTextWidth - viewportWidth)
    ticker.text = "Visible summary"
    ticker.text = "  \n\t  "
    guard overflowing,
          !normalizedOverflowText.contains("\n"),
          !normalizedOverflowText.contains("**"),
          markdownCases.allSatisfy({ normalizedTickerText($0.key) == $0.value }),
          presentableTickerText("  \n\t  ") == nil,
          ticker.text == "Visible summary",
          visibleTickerTextWidth(textWidth: longTextWidth,
                                 viewportWidth: viewportWidth,
                                 translation: 0) == viewportWidth,
          visibleTickerTextWidth(textWidth: longTextWidth,
                                 viewportWidth: viewportWidth,
                                 translation: endTranslation) == viewportWidth,
          speeds == [22, 34, 52],
          metrics.label.minY >= metrics.viewport.minY,
          metrics.label.maxY <= metrics.viewport.maxY,
          TickerTiming.startPause >= 1,
          TickerTiming.returnDuration <= 0.2 else {
        FileHandle.standardError.write(
            "ticker self-test failed: viewport=\(metrics.viewport) label=\(metrics.label)\n"
                .data(using: .utf8)!)
        exit(1)
    }
    print("ticker: oneLine=true overflow=true verticallyContained=true " +
          "emptyRejected=true alwaysVisible=true reset=true")
    exit(0)
}

if CommandLine.arguments.contains("--ticker-background-selftest") {
    let suiteName = "thoughtcrime.ticker-background.selftest.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else { exit(1) }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let sample = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.7, alpha: 0.85)
    let initial = TickerBackgroundPreference.load(defaults: defaults)
    TickerBackgroundPreference.save(sample, defaults: defaults)
    let restored = TickerBackgroundPreference.load(defaults: defaults)
    let values = restored.flatMap(TickerBackgroundPreference.components(of:)) ?? []
    let normal = TickerAppearance.background(alarmActive: false,
                                             configuredAlarmColor: sample)
    let normalValues = TickerBackgroundPreference.components(of: normal) ?? []
    let alarm = TickerAppearance.background(alarmActive: true,
                                            configuredAlarmColor: sample)
    let alarmValues = TickerBackgroundPreference.components(of: alarm) ?? []
    let defaultAlarm = TickerAppearance.background(alarmActive: true,
                                                   configuredAlarmColor: nil)
    let defaultAlarmValues = TickerBackgroundPreference.components(of: defaultAlarm) ?? []
    let ticker = TickerView(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    let tickerIsBold = NSFontManager.shared.traits(of: ticker.textFont)
        .contains(.boldFontMask)
    TickerBackgroundPreference.save(nil, defaults: defaults)
    guard initial == nil,
          values.count == 4,
          abs(values[0] - 0.2) < 0.001,
          abs(values[1] - 0.4) < 0.001,
          abs(values[2] - 0.7) < 0.001,
          abs(values[3] - 0.85) < 0.001,
          normalValues.count == 4,
          normalValues == (TickerBackgroundPreference.components(
            of: NSColor.windowBackgroundColor) ?? []),
          // A violation never changes the ticker background.
          alarmValues == normalValues, defaultAlarmValues == normalValues,
          !tickerIsBold,
          TickerBackgroundPreference.load(defaults: defaults) == nil,
          TickerBackgroundPreference.usesDarkForeground(on: .white),
          !TickerBackgroundPreference.usesDarkForeground(on: .black) else {
        FileHandle.standardError.write("ticker background self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("ticker background: semanticSurface=true violationUnchanged=true custom=true " +
          "autoContrast=true textWeight=regular")
    exit(0)
}

if CommandLine.arguments.contains("--message-view-selftest") {
    // BUG-088: the violation empty state and an expanded violation row must
    // fit the 380-point history; an expanded reason wraps to two lines.
    let emptyState = HistoryEmptyStateView(frame: .zero)
    let emptyHost = NSView(frame: NSRect(x: 0, y: 0, width: 364, height: 300))
    emptyHost.addSubview(emptyState)
    NSLayoutConstraint.activate([
        emptyState.leadingAnchor.constraint(equalTo: emptyHost.leadingAnchor),
        emptyState.widthAnchor.constraint(equalToConstant: 364),
    ])
    emptyHost.layoutSubtreeIfNeeded()
    let row = EventCard(source: "Claude · video recap", time: "20:24",
                        event: UIEvent(timestamp: "", kind: "analysis",
                                       text: "x", readableAnalysis: true))
    let rowHost = NSView(frame: NSRect(x: 0, y: 0, width: 364, height: 400))
    rowHost.addSubview(row)
    NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: rowHost.leadingAnchor),
        row.topAnchor.constraint(equalTo: rowHost.topAnchor),
        row.widthAnchor.constraint(equalToConstant: 364),
    ])
    row.setViolation(
        reason: String(repeating: "The assistant adds a missing parameter on its own. ",
                       count: 6),
        evidence: "Manual dubs need dubbing_studio=true.",
        provider: "Groq · openai/gpt-oss-120b · confirmed by second check",
        latencyMs: 1246, checkPrompt: "rule")
    row.setViolationReviewed(true)
    rowHost.layoutSubtreeIfNeeded()
    let collapsedHeight = row.fittingSize.height
    row.setViolationExpanded(true)
    rowHost.layoutSubtreeIfNeeded()
    let expandedHeight = row.fittingSize.height
    let summary = row.violationSummary
    guard emptyState.fittingSize.width <= 364,
          row.fittingSize.width <= 364,
          summary.reasonVisible, summary.detailVisible, summary.bodyHidden,
          summary.detail == "Confirmed by second check · 1.2 s ·",
          expandedHeight - collapsedHeight > 40,   // quote + 2 reason lines + detail
          expandedHeight < 160 else {              // reason is clamped, not unlimited
        FileHandle.standardError.write(("violation row self-test failed: empty=" +
            "\(emptyState.fittingSize.width) row=\(row.fittingSize.width) " +
            "collapsed=\(collapsedHeight) expanded=\(expandedHeight)\n")
            .data(using: .utf8)!)
        exit(1)
    }
    let message = FullMessageView(frame: NSRect(x: 0, y: 0, width: 560, height: 300))
    message.show(source: "Codex · Message test",
                 text: "**Complete rendered summary** with `inline code`.",
                 kind: "analysis")
    message.layoutSubtreeIfNeeded()
    let shortHeight = message.preferredHeight(forWidth: 560)
    guard message.source == "Codex · Message test",
          message.text == "Complete rendered summary with inline code.",
          message.lifecycleButtonTitles == ["Done"],
          message.tone == .normal,
          shortHeight == 118,
          !message.text.contains("**") else {
        FileHandle.standardError.write("message view self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    message.show(source: "Thoughtcrime · Check error",
                 text: "⛔ **THOUGHTCRIME CHECK ERROR**\nProvider failed.",
                 kind: "analysis", tone: .error)
    guard message.source == "Thoughtcrime · Check error",
          message.text.contains("THOUGHTCRIME CHECK ERROR"),
          message.tone == .error else {
        FileHandle.standardError.write(
            "message error tone self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    message.show(source: "Codex · Long message",
                 text: Array(repeating: "A complete rendered line.", count: 120)
                    .joined(separator: "\n"),
                 kind: "analysis")
    let longHeight = message.preferredHeight(forWidth: 560)
    guard longHeight == 420, longHeight > shortHeight else {
        FileHandle.standardError.write(
            "message content-fit self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("message view: dedicated=true markdownRendered=true hide=true menuQuit=true " +
          "errorTone=true contentFit=true")
    exit(0)
}

if CommandLine.arguments.contains("--message-reader-freeze-selftest") {
    var selectedIndex = 2
    var eventCount = 3
    let snapshot = MessageReaderSnapshot(source: "Codex · frozen",
                                         text: "Message being read", kind: "analysis",
                                         tone: .normal)
    eventCount += 1
    if MessageReaderSelection.shouldAdvanceForNewMessage(
        isReaderOpen: true, wasFollowingLatest: selectedIndex == eventCount - 2) {
        selectedIndex = eventCount - 1
    }
    eventCount += 1
    if MessageReaderSelection.shouldAdvanceForNewMessage(
        isReaderOpen: true, wasFollowingLatest: selectedIndex == eventCount - 2) {
        selectedIndex = eventCount - 1
    }
    guard selectedIndex == 2,
          snapshot.source == "Codex · frozen",
          snapshot.text == "Message being read",
          MessageReaderSelection.latestIndex(eventCount: eventCount) == 4,
          MessageReaderSelection.latestIndex(eventCount: 0) == -1,
          MessageReaderSelection.shouldAdvanceForNewMessage(
            isReaderOpen: false, wasFollowingLatest: true),
          MessageReaderSelection.shouldAdvanceForNewMessage(
            isReaderOpen: false, wasFollowingLatest: false) else {
        FileHandle.standardError.write("message reader freeze self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("message reader: snapshot=frozen incomingIgnored=true closeResumesLatest=true")
    exit(0)
}

if CommandLine.arguments.contains("--outside-click-selftest") {
    let frame = NSRect(x: 100, y: 100, width: 560, height: 300)
    guard !shouldDismissDetails(isShowingDetails: true, isEditorVisible: false,
                                windowFrame: frame,
                                clickLocation: NSPoint(x: 120, y: 120)),
          !shouldDismissDetails(isShowingDetails: true, isEditorVisible: true,
                                windowFrame: frame,
                                clickLocation: NSPoint(x: 20, y: 20)),
          shouldDismissDetails(isShowingDetails: true, isEditorVisible: false,
                               windowFrame: frame,
                               clickLocation: NSPoint(x: 20, y: 20)),
          !shouldDismissDetails(isShowingDetails: false, isEditorVisible: false,
                                windowFrame: frame,
                                clickLocation: NSPoint(x: 20, y: 20)) else {
        FileHandle.standardError.write("outside click self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    // The click that opens the reader is judged against the ticker it hit,
    // not against the narrower reader it opens (BUG-099).
    _ = NSApplication.shared
    let monitor = OutsideClickMonitor()
    var showingDetails = false
    var windowFrame = NSRect(x: 880, y: 900, width: 560, height: 28)   // ticker
    var dismissed = false
    monitor.start(shouldDismiss: { location in
        shouldDismissDetails(isShowingDetails: showingDetails, isEditorVisible: false,
                             windowFrame: windowFrame, clickLocation: location)
    }, dismiss: { dismissed = true })
    monitor.handleClick(at: NSPoint(x: 900, y: 914))    // "2 active", left part
    showingDetails = true                               // the click opened the reader
    windowFrame = NSRect(x: 1060, y: 650, width: 380, height: 278)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let openingClickKept = !dismissed
    monitor.handleClick(at: NSPoint(x: 200, y: 200))    // a real outside click
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    monitor.stop()
    guard openingClickKept, dismissed else {
        FileHandle.standardError.write("outside click timing self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("outside click: details=true editorProtected=true insideIgnored=true openingClickKept=true")
    exit(0)
}

if CommandLine.arguments.contains("--ticker-actions-selftest") {
    let actions = TickerPrimaryActions(frame: .zero)
    let activity = CheckerActivityIndicator(frame: .zero)
    var history = false
    var hidden = false
    actions.historyRequested = { history = true }
    actions.hideRequested = { hidden = true }
    actions.requestHistoryForTest()
    actions.requestHideForTest()
    activity.begin(destination: "Groq · Test")
    guard actions.accessibilityNames == ["Open history", "Settings", "Hide Thoughtcrime"],
          history, hidden,
          activity.isChecking, !activity.isHidden,
          activity.destination == "Groq · Test",
          activity.accessibilityLabel() == "Checking reasoning with Groq · Test" else {
        FileHandle.standardError.write("ticker actions self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    activity.finish(minimumVisibleDuration: 0)
    guard !activity.isChecking, activity.isHidden else {
        FileHandle.standardError.write("checker activity reset self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("ticker actions: history=oneClick settings=oneClick hide=oneClick " +
          "checkerLight=true accessible=true")
    exit(0)
}

if CommandLine.arguments.contains("--window-position-selftest") {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let bottomRightPeek = NSRect(x: 968, y: 12, width: 460, height: 70)
    let expanded = resizedWindowFrame(bottomRightPeek, toHeight: 210,
                                      width: 560, within: visible)
    let collapsed = resizedWindowFrame(expanded, toHeight: 70,
                                       width: 460, within: visible)
    let floating = NSRect(x: 400, y: 300, width: 460, height: 70)
    let floatingExpanded = resizedWindowFrame(floating, toHeight: 210,
                                              width: 560, within: visible)
    // Docked 20 pt below the top: the ticker and the reader touch the menu bar.
    let topDocked = NSRect(x: 968, y: 900 - 28 - 20, width: 460, height: 28)
    let topExpanded = resizedWindowFrame(topDocked, toHeight: 300, width: 380, within: visible)
    let topCollapsed = resizedWindowFrame(topExpanded, toHeight: 28, width: 460,
                                          within: visible)
    let close: (CGFloat, CGFloat) -> Bool = { abs($0 - $1) < 0.5 }
    guard close(topExpanded.maxY, 900), close(topCollapsed.maxY, 900),
          close(topCollapsed.height, 28),
          close(expanded.minY, 12), close(collapsed.minY, 12),
          close(expanded.maxX, 1428), close(collapsed.maxX, 1428),
          close(floatingExpanded.midX, floating.midX),
          close(floatingExpanded.midY, floating.midY) else {
        FileHandle.standardError.write(
            "window-position self-test failed: expanded=\(expanded) collapsed=\(collapsed)\n"
                .data(using: .utf8)!)
        exit(1)
    }
    print("window position: top flush, bottom/right insets and floating center preserved")
    exit(0)
}

if CommandLine.arguments.contains("--ticker-corner-selftest") ||
   CommandLine.arguments.contains("--ticker-position-selftest") {
    let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let initial = NSRect(x: 300, y: 200, width: 460, height: 70)
    let topLeft = movedWindowFrame(initial, to: .topLeft, within: visible)
    let topRight = movedWindowFrame(initial, to: .topRight, within: visible)
    let bottomLeft = movedWindowFrame(initial, to: .bottomLeft, within: visible)
    let bottomRight = movedWindowFrame(initial, to: .bottomRight, within: visible)
    // Top corners touch the menu bar (visible.maxY); the others keep 12 pt.
    guard topLeft.origin == NSPoint(x: 12, y: 730),
          topRight.origin == NSPoint(x: 528, y: 730),
          bottomLeft.origin == NSPoint(x: 12, y: 12),
          bottomRight.origin == NSPoint(x: 528, y: 12),
          TickerWindowCorner.allCases.map(\.routeName) ==
            ["top-left", "top-right", "bottom-left", "bottom-right"] else {
        FileHandle.standardError.write(
            "ticker position self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("ticker corners: topLeft=true topRight=true bottomLeft=true bottomRight=true")
    exit(0)
}

if CommandLine.arguments.contains("--provider-icon-selftest") {
    let claude = ProviderIconView(frame: .zero)
    claude.update(source: "Claude · Appium")
    let codex = ProviderIconView(frame: .zero)
    codex.update(source: "Codex · Thought watch 2")
    let explicitChatGPT = MessageProvider.detect(from: "ChatGPT · Example")
    let nativeIconsAvailable = [MessageProvider.claude, .codex, .chatGPT].allSatisfy {
        guard let path = $0.installedApplicationPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
    guard claude.provider == .claude,
          codex.provider == .codex,
          explicitChatGPT == .chatGPT,
          claude.image != nil,
          codex.image != nil,
          claude.accessibilityLabel() == "Provider: Claude",
          codex.accessibilityLabel() == "Provider: Codex" else {
        FileHandle.standardError.write(
            "provider icon self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("provider icons: claude=true codex=true nativeAppIcons=\(nativeIconsAvailable) accessible=true")
    exit(0)
}

if CommandLine.arguments.contains("--settings-window-selftest") {
    _ = NSApplication.shared
    let rules = CheckRulesEditor(contents: "Rule", mode: .wholeText, save: { _, _ in })
    let keys = ProviderCredentialsEditor(statuses: [:], save: { _ in [] })
    let settings = SettingsWindow(rules: rules, keys: keys)
    var requestedFlash: Bool?
    var requestedBubble: Bool?
    var requestedVerification: Bool?
    var requestedLimit: Int?
    var requestedSpeed: TickerSpeed?
    var requestedPosition: String?
    settings.alerts.flashChanged = { requestedFlash = $0 }
    settings.alerts.bubbleChanged = { requestedBubble = $0 }
    settings.alerts.verificationChanged = { requestedVerification = $0 }
    settings.alerts.historyLimitChanged = { requestedLimit = $0 }
    settings.general.speedChanged = { requestedSpeed = $0 }
    settings.general.positionPicked = { requestedPosition = $0 }
    settings.alerts.update(flashEnabled: true, bubbleEnabled: false, verificationEnabled: true,
                           historyLimit: 50)
    settings.general.update(speed: .normal, width: CompactWindowSizing.standardWidth,
                            usesDefaultAlarmColor: true)
    let initialFlashOn = settings.alerts.flashSwitch.state == .on
    let initialBubbleOff = settings.alerts.bubbleSwitch.state == .off
    let initialHistory = settings.alerts.historyButton.titleOfSelectedItem
    let initialSpeed = settings.general.speedButton.titleOfSelectedItem
    settings.alerts.flashSwitch.performClick(nil)
    settings.alerts.bubbleSwitch.performClick(nil)
    settings.alerts.verificationSwitch.performClick(nil)
    settings.alerts.historyButton.selectItem(withTitle: "100 newest")
    _ = settings.alerts.historyButton.target?.perform(settings.alerts.historyButton.action,
                                                     with: settings.alerts.historyButton)
    settings.general.speedButton.selectItem(withTitle: "Fast")
    _ = settings.general.speedButton.target?.perform(settings.general.speedButton.action,
                                                    with: settings.general.speedButton)
    settings.general.positionButton.selectItem(withTitle: "Bottom Right")
    _ = settings.general.positionButton.target?.perform(
        settings.general.positionButton.action, with: settings.general.positionButton)
    settings.show(.alerts)
    let alertsTab = settings.selectedTab
    settings.show(.keys)
    let keysTab = settings.selectedTab
    let windowWidth = settings.window?.frame.width ?? 0
    settings.window?.close()
    let suite = "thoughtcrime.violation-alerts-selftest"
    guard let defaults = UserDefaults(suiteName: suite) else { exit(1) }
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let flashDefaultOn = ViolationFlashPreference.load(defaults: defaults)
    let bubbleDefaultOff = !ViolationBubblePreference.load(defaults: defaults)
    let verificationDefaultOn = ViolationVerificationPreference.load(defaults: defaults)
    let historyDefault = ViolationHistoryPreference.load(defaults: defaults)
    ViolationFlashPreference.save(false, defaults: defaults)
    ViolationBubblePreference.save(true, defaults: defaults)
    let hiddenDefaultOff = !HiddenPreference.load(defaults: defaults)
    HiddenPreference.save(true, defaults: defaults)
    let hiddenRemembered = HiddenPreference.load(defaults: defaults)
    ViolationHistoryPreference.save(25, defaults: defaults)
    ViolationHistoryPreference.save(7, defaults: defaults)  // not a choice: ignored
    guard SettingsTab.allCases.map(\.title) == ["General", "Alerts", "Rules", "Keys"],
          initialFlashOn, initialBubbleOff, initialHistory == "50 newest",
          initialSpeed == "Normal",
          requestedFlash == false, requestedBubble == true, requestedVerification == false,
          requestedLimit == 100, requestedSpeed == .fast,
          requestedPosition == "bottom-right",
          alertsTab == .alerts, keysTab == .keys, windowWidth >= 500,
          flashDefaultOn, bubbleDefaultOff, verificationDefaultOn, historyDefault == 50,
          hiddenDefaultOff, hiddenRemembered,
          !ViolationFlashPreference.load(defaults: defaults),
          ViolationBubblePreference.load(defaults: defaults),
          ViolationHistoryPreference.load(defaults: defaults) == 25,
          ViolationFlashPreference.duration == 3,
          ViolationBubblePreference.duration == 5 else {
        FileHandle.standardError.write("settings window self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("settings window: tabs=General,Alerts,Rules,Keys switches=true popups=true " +
          "flashDefaultOn=true bubbleDefaultOff=true flash=3 bubble=5 verificationDefaultOn=true " +
          "historyDefault=50")
    exit(0)
}

if CommandLine.arguments.contains("--check-rules-editor-selftest") ||
   CommandLine.arguments.contains("--check-prompt-selftest") {
    guard let defaults = UserDefaults(suiteName: "thoughtcrime.check-rules-selftest") else {
        exit(1)
    }
    defaults.removePersistentDomain(forName: "thoughtcrime.check-rules-selftest")
    defer { defaults.removePersistentDomain(forName: "thoughtcrime.check-rules-selftest") }
    var saveActionRan = false
    let editor = CheckRulesEditor(contents: CheckRulesStore.loadRaw(defaults: defaults),
                                  mode: .eachLine,
                                  save: { text, mode in
        saveActionRan = true
        CheckRulesStore.saveRaw(text, defaults: defaults)
        CheckRulesStore.saveMode(mode, defaults: defaults)
    })
    guard editor.currentText == CheckRulesStore.defaultValue,
          editor.actionTitles == ["Revert", "Save Rules"],
          editor.actionsAreHorizontal,
          editor.currentMode == .eachLine,
          CheckRulesStore.instruction(defaults: defaults) ==
            CheckRulesStore.defaultValue,
          !CheckRulesStore.isCustomized(defaults: defaults)
    else { exit(1) }
    guard let saveButton = editor.view.subviews
        .compactMap({ $0 as? NSStackView })
        .flatMap(\.arrangedSubviews)
        .compactMap({ $0 as? NSButton })
        .first(where: { $0.title == "Save Rules" }) else { exit(1) }
    saveButton.performClick(nil)
    guard saveActionRan, !editor.isDirty,
          CheckRulesStore.loadRaw(defaults: defaults) == CheckRulesStore.defaultValue,
          CheckRulesStore.isCustomized(defaults: defaults) else { exit(1) }
    let verbatim = "Updated instruction\n# remains literal user text\nSecond paragraph"
    CheckRulesStore.saveRaw(verbatim, defaults: defaults)
    CheckRulesStore.saveMode(.wholeText, defaults: defaults)
    guard CheckRulesStore.loadRaw(defaults: defaults) == verbatim + "\n",
          CheckRulesStore.instruction(defaults: defaults) == verbatim + "\n",
          CheckRulesStore.instructions(defaults: defaults) == [verbatim + "\n"],
          CheckRulesStore.isCustomized(defaults: defaults) else { exit(1) }
    CheckRulesStore.saveMode(.eachLine, defaults: defaults)
    guard CheckRulesStore.instructions(defaults: defaults) ==
            ["Updated instruction", "# remains literal user text", "Second paragraph"] else {
        exit(1)
    }
    print("check rules editor: saveButton=true verbatim=true explicitMode=true appLocalOnly=true " +
          "noFiles=true persisted=true nextCheck=true compactWindow=true")
    exit(0)
}

if CommandLine.arguments.contains("--window-chrome-selftest") {
    let testPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 70),
                            styleMask: [.borderless, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
    let content = testPanel.contentRect(forFrameRect: testPanel.frame)
    let chrome = testPanel.frame.height - content.height
    guard abs(chrome) < 0.5, abs(content.height - 70) < 0.5 else {
        FileHandle.standardError.write(
            "window chrome self-test failed: frame=\(testPanel.frame) content=\(content)\n"
                .data(using: .utf8)!)
        exit(1)
    }
    print("window chrome: borderless=true chromeHeight=0 restingHeight=70")
    exit(0)
}

if CommandLine.arguments.contains("--compact-width-selftest") {
    guard CompactWindowSizing.clamped(300) == 380,
          CompactWindowSizing.clamped(440) == 440,
          CompactWindowSizing.clamped(700) == 560,
          CompactWindowSizing.headerStyle(for: 400) == .stacked,
          CompactWindowSizing.headerStyle(for: 560) == .stacked,
          CompactWindowSizing.headerStyle(for: 700) == .stacked,
          CompactWindowSizing.headerHeight(for: 400) == 82,
          CompactWindowSizing.headerHeight(for: 560) == 82,
          CompactWindowSizing.headerHeight(for: 700) == 82,
          CompactWindowSizing.controlsHeight(for: 400) == 292,
          CompactWindowSizing.controlsHeight(for: 560) == 292,
          shouldShowHistoryFeed(peekMode: false, messageMode: false,
                                compactMode: true),
          shouldShowHistoryFeed(peekMode: false, messageMode: false,
                                compactMode: false) else {
        FileHandle.standardError.write("compact width self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("compact width: range=380...560 narrow=400 responsiveHeader=true persisted=true")
    exit(0)
}

if CommandLine.arguments.contains("--interaction-selftest") ||
   CommandLine.arguments.contains("--hover-ux-selftest") {
    let interactionView = CompactInteractionView(frame: NSRect(x: 0, y: 0,
                                                               width: 460, height: 70))
    interactionView.dragOnly = true
    guard CompactInteractionUX.dragTolerance >= 2,
          interactionView.backgroundCursor === NSCursor.arrow else {
        FileHandle.standardError.write("compact interaction self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("compact interaction: cursor=arrow singleClick=immediate dragSafe=true")
    exit(0)
}

if CommandLine.arguments.contains("--escape-selftest") {
    let panel = ConstrainedPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                                 styleMask: [.borderless, .resizable],
                                 backing: .buffered, defer: false)
    var collapseCount = 0
    panel.escapeRequested = { collapseCount += 1 }
    guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                        modifierFlags: [], timestamp: 0,
                                        windowNumber: panel.windowNumber,
                                        context: nil, characters: "\u{1b}",
                                        charactersIgnoringModifiers: "\u{1b}",
                                        isARepeat: false, keyCode: 53),
          panel.performKeyEquivalent(with: escape),
          collapseCount == 1,
          controlsExpansionTitle(compactMode: true) == "Show all",
          controlsExpansionTitle(compactMode: false) == nil else {
        FileHandle.standardError.write(
            "escape self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    panel.cancelOperation(nil)
    guard collapseCount == 2 else {
        FileHandle.standardError.write(
            "escape cancel-operation self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("escape: message=true controls=true history=true collapseButton=false")
    exit(0)
}

if CommandLine.arguments.contains("--exit-controls-selftest") {
    let controls = DetailExitControls(frame: .zero)
    var closed = false
    controls.closeRequested = { closed = true }
    controls.requestClose(nil)
    guard controls.buttonTitles == ["Done"],
          controls.accessibilityNames == ["Close details"], closed else {
        FileHandle.standardError.write(
            "exit controls self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("exit controls: doneReturnsToTicker=true visible=true accessible=true")
    exit(0)
}

if CommandLine.arguments.contains("--privacy-audit-selftest") {
    let path = NSTemporaryDirectory() + "/thoughtcrime-audit-\(UUID().uuidString).jsonl"
    let audit = PrivacyAudit(path: path)
    audit.start()
    audit.start(reset: false)
    let toolLine = #"{"timestamp":"2026-08-15T00:00:00Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call_1","output":"TOP_SECRET_TOOL_CONTENT"}}"#
    let summaryLine = #"{"timestamp":"2026-08-15T00:00:01Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"PRIVATE_PROVIDER_SUMMARY"}],"encrypted_content":"sealed"}}"#
    let reasoningLine = #"{"timestamp":"2026-08-15T00:00:02Z","type":"response_item","payload":{"type":"reasoning","content":[{"type":"reasoning_text","text":"PRIVATE_REASONING_CONTENT"}],"encrypted_content":"sealed"}}"#
    let codexResponseLine = #"{"timestamp":"2026-08-15T00:00:03Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"PRIVATE_CODEX_RESPONSE"}],"phase":"final_answer"}}"#
    let claudeResponseLine = #"{"timestamp":"2026-08-15T00:00:04Z","type":"assistant","message":{"content":[{"type":"text","text":"PRIVATE_CLAUDE_RESPONSE"}]}}"#
    audit.recordTranscriptLine(toolLine, sourcePath: "/tmp/session.jsonl")
    audit.recordTranscriptLine(summaryLine, sourcePath: "/tmp/session.jsonl")
    audit.recordTranscriptLine(reasoningLine, sourcePath: "/tmp/session.jsonl")
    audit.recordTranscriptLine(codexResponseLine, sourcePath: "/tmp/session.jsonl")
    audit.recordTranscriptLine(claudeResponseLine, sourcePath: "/tmp/session.jsonl")
    audit.recordExternalRequest(source: "Codex · Test", destination: "Provider · Model",
                                recordType: "reasoning_text",
                                envelopeBytes: 321, requestID: "request-1")
    audit.recordExternalResult(source: "Codex · Test", destination: "Provider · Model",
                               recordType: "reasoning_text", requestID: "request-1",
                               status: "alert", alert: true, latencyMs: 87)
    audit.recordExternalRequest(source: "Claude · Test", destination: "Provider · Model",
                                recordType: "assistant_response",
                                envelopeBytes: 144, requestID: "request-2")
    audit.recordExternalResult(source: "Claude · Test", destination: "Provider · Model",
                               recordType: "assistant_response", requestID: "request-2",
                               status: "clean", alert: false, latencyMs: 43)
    let log = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    try? FileManager.default.removeItem(atPath: path)
    guard log.components(separatedBy: "\"action\":\"app_started\"").count - 1 == 2,
          log.contains("tool_record_discarded"),
          log.contains("provider_summary_displayed_locally"),
          log.contains("reasoning_selected"),
          log.contains("assistant_response_selected"),
          log.contains("external_reasoning_request"),
          log.contains("external_reasoning_result"),
          log.contains("external_assistant_response_request"),
          log.contains("external_assistant_response_result"),
          log.contains("\"request_id\":\"request-1\""),
          log.contains("\"status\":\"alert\""),
          log.contains("\"alert\":true"),
          log.contains("\"latency_ms\":87"),
          log.contains("\"record_type\":\"reasoning_text\""),
          log.contains("\"envelope_bytes\":321"),
          log.contains("\"record_type\":\"assistant_response\""),
          !log.contains("TOP_SECRET_TOOL_CONTENT"),
          !log.contains("PRIVATE_PROVIDER_SUMMARY"),
          !log.contains("PRIVATE_REASONING_CONTENT"),
          !log.contains("PRIVATE_CODEX_RESPONSE"),
          !log.contains("PRIVATE_CLAUDE_RESPONSE") else {
        FileHandle.standardError.write(
            "privacy audit self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("privacy audit: reasoningAndResponses=true providerSummaryExcluded=true " +
          "toolsDiscarded=true outbound=true outcome=true contentLogged=false")
    exit(0)
}

if CommandLine.arguments.contains("--violation-bubble-selftest") {
    // Every part of the bubble opens it, including its title and quote.
    _ = NSApplication.shared
    let bubble = ViolationBubble()
    bubble.show(title: "Violation · research grants",
                quote: "“sesame status still says locked, so the AI calls can't run.”",
                below: nil)
    let size = bubble.frame.size
    let points = [NSPoint(x: 40, y: size.height - 14),     // title
                  NSPoint(x: 120, y: size.height / 2),     // quote
                  NSPoint(x: 30, y: 14),                   // "Click to open"
                  NSPoint(x: size.width - 6, y: 3)]        // empty corner
    let allOpen = points.allSatisfy { bubble.viewHit(at: $0) === bubble.contentView }
    bubble.hide()
    guard allOpen else {
        FileHandle.standardError.write("violation bubble self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("violation bubble: wholeBubbleOpens=true")
    exit(0)
}

if CommandLine.arguments.contains("--violation-store-selftest") {
    // Violations vs Archive: exactly one hour from the record's timestamp.
    let archiveNow = parsedRecordTimestamp("2026-10-04T12:00:00.000Z")!
    guard violationIsArchived(timestamp: "2026-10-04T11:00:00.001Z", now: archiveNow) == false,
          violationIsArchived(timestamp: "2026-10-04T11:00:00.000Z", now: archiveNow) == true,
          violationIsArchived(timestamp: "2026-10-03T12:00:00Z", now: archiveNow) == true,
          violationIsArchived(timestamp: "2026-10-04T11:59:00.123456Z", now: archiveNow) == false,
          violationIsArchived(timestamp: "", now: archiveNow) == nil,
          violationIsArchived(timestamp: "yesterday", now: archiveNow) == nil,
          violationArchiveAge == 3600 else {
        FileHandle.standardError.write("violation archive boundary self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    guard violationHistoryMenuTitle(recorded: 0, unreviewed: 0,
                                    storageUnavailable: false) ==
            "Open Violation History…",
          violationHistoryMenuTitle(recorded: 13, unreviewed: 13,
                                    storageUnavailable: false) ==
            "Open Violation History (13 New)…",
          violationHistoryMenuTitle(recorded: 13, unreviewed: 0,
                                    storageUnavailable: false) ==
            "Open Violation History (13 Reviewed)…",
          violationHistoryMenuTitle(recorded: 13, unreviewed: 2,
                                    storageUnavailable: true) ==
            "Open Violation History (Unavailable)…",
          violationStatusBadgeTitle(unreviewed: 0) == "",
          violationStatusBadgeTitle(unreviewed: 9) == " 9",
          violationStatusBadgeTitle(unreviewed: 10) == " 10",
          violationStatusBadgeTitle(unreviewed: 27) == " 27" else {
        FileHandle.standardError.write(
            "violation menu title self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    let path = NSTemporaryDirectory() + "/thoughtcrime-violations-\(UUID().uuidString).json"
    let first = ViolationRecord(
        timestamp: "2026-08-31T12:00:00Z", source: "Claude · Alpha",
        content: "Reasoning that matched the check prompt", reason: "Asked user to wait",
        evidence: "wait for you", provider: "Dummy · deterministic",
        latencyMs: 42, checkPrompt: "Claude is waiting for the user")
    let second = ViolationRecord(
        timestamp: "2026-08-31T12:01:00Z", source: "Codex · Beta",
        content: "Another matching reasoning record", reason: "Confused",
        evidence: "I am unsure", provider: "Dummy · deterministic",
        latencyMs: 53, checkPrompt: "The agent is confused")
    let store = ViolationStore(path: path)
    store.append(first)
    store.append(second)
    let reloaded = ViolationStore(path: path).load()
    let reviewed = store.markReviewed(id: first.id,
                                      at: "2026-08-31T12:02:00Z")
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue
    let damagedPath = path + ".damaged"
    try? Data("not-json".utf8).write(to: URL(fileURLWithPath: damagedPath))
    let damagedStore = ViolationStore(path: damagedPath)
    let damagedLoad = damagedStore.load()
    let damagedAppend = damagedStore.append(first)
    let damagedContents = try? String(contentsOfFile: damagedPath, encoding: .utf8)
    let damagedLimited = damagedStore.setLimit(10)
    let damagedAfterLimit = try? String(contentsOfFile: damagedPath, encoding: .utf8)
    // History limit: append trims to the limit; lowering it deletes the oldest.
    let limitedPath = path + ".limited"
    let limited = ViolationStore(path: limitedPath, limit: 3)
    let many = (0..<5).map { index in
        ViolationRecord(timestamp: "2026-08-31T12:0\(index):00Z", source: "Claude · Alpha",
                        content: "record \(index)", reason: "r", evidence: "e",
                        provider: "Dummy", latencyMs: 1, checkPrompt: "p")
    }
    for record in many { limited.append(record) }
    let afterAppend = ViolationStore(path: limitedPath, limit: 3).load()
    let lowered = limited.setLimit(2)
    let afterLowering = ViolationStore(path: limitedPath, limit: 2).load()
    let raised = limited.setLimit(10)
    try? FileManager.default.removeItem(atPath: path)
    try? FileManager.default.removeItem(atPath: damagedPath)
    try? FileManager.default.removeItem(atPath: limitedPath)
    guard afterAppend == Array(many.suffix(3)), lowered == Array(many.suffix(2)),
          afterLowering == Array(many.suffix(2)), raised == Array(many.suffix(2)),
          damagedLimited.isEmpty, damagedAfterLimit == "not-json",
          ViolationStore.maximumRecords == 500 else {
        FileHandle.standardError.write(
            "violation history limit self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    guard reloaded == [first, second], reviewed.first?.reviewedAt != nil,
          reviewed.last?.reviewedAt == nil, permissions == 0o600,
          reloaded[0].checkPrompt == "Claude is waiting for the user",
          damagedLoad.isEmpty, damagedAppend == [first],
          damagedStore.lastError != nil, damagedContents == "not-json" else {
        FileHandle.standardError.write(
            "violation store self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("violations: persisted=true ordered=true reviewedState=true " +
          "exactStatusBadge=true corruptFilePreserved=true promptSnapshot=true " +
          "permissions=0600 historyLimit=true")
    exit(0)
}

if CommandLine.arguments.contains("--usage-selftest") {
    let path = NSTemporaryDirectory() + "thoughtcrime-usage-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let store = UsageStore(path: path)
    let day = ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z")!
    let lastMonth = ISO8601DateFormatter().date(from: "2026-09-15T12:00:00Z")!
    let groqModel: [String: Any] = ["id": "qwen/qwen3.8-27b",
        "pricing": ["prompt": "0.0000008", "completion": "0.000004"]]
    let price = ModelPrice(modelResponse: groqModel)
    let usage = TokenUsage(response: ["usage": ["prompt_tokens": 280, "completion_tokens": 70]])
    store.record(model: "Groq · qwen", usage: TokenUsage(input: 280, output: 70),
                 secondCheck: false, at: day)
    store.record(model: "Groq · qwen", usage: TokenUsage(input: 300, output: 60),
                 secondCheck: true, at: day)
    store.record(model: "Groq · qwen", usage: TokenUsage(input: 1000, output: 100),
                 secondCheck: false, at: lastMonth)
    let unpriced = store.summary(today: day)
    if let price { store.setPrice(price, for: "Groq · qwen") }
    let priced = store.summary(today: day)
    let reloaded = UsageStore(path: path).summary(today: day)
    let expectedToday = 580 * 0.0000008 + 130 * 0.000004
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    guard price == ModelPrice(input: 0.0000008, output: 0.000004),
          usage == TokenUsage(input: 280, output: 70),
          TokenUsage(response: [:]) == nil,
          ModelPrice(modelResponse: ["id": "x"]) == nil,
          unpriced.today.costUSD == nil,                       // never guessed
          formattedCost(nil) == "price not published",
          priced.today.totals == UsageTotals(checks: 1, secondChecks: 1,
                                             inputTokens: 580, outputTokens: 130),
          abs((priced.today.costUSD ?? 0) - expectedToday) < 1e-12,
          priced.month.totals.checks == 1,                     // September excluded
          reloaded.today.totals == priced.today.totals,
          (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o600,
          usageMenuTitle(priced.today) == "Usage Today: $0.0010 · 1 checks…" else {
        FileHandle.standardError.write(("usage self-test failed: price=\(String(describing: price)) " +
            "usage=\(String(describing: usage)) unpriced=\(String(describing: unpriced.today.costUSD)) " +
            "today=\(priced.today.totals) cost=\(String(describing: priced.today.costUSD)) " +
            "month=\(priced.month.totals.checks) reloaded=\(reloaded.today.totals) " +
            "perm=\(String(describing: attributes?[.posixPermissions])) " +
            "title=\(usageMenuTitle(priced.today))\n").data(using: .utf8)!)
        exit(1)
    }
    print("usage: providerTokens=true publishedPrice=true unpricedNotGuessed=true " +
          "perDay=true monthScope=true persisted=0600")
    exit(0)
}

if CommandLine.arguments.contains("--checker-credentials-selftest") {
    final class MemoryCredentialAccess: CredentialAccess {
        var values: [String: String] = [:]
        func read(account: String) throws -> String? { values[account] }
        func save(_ value: String, account: String) throws { values[account] = value }
        func remove(account: String) throws { values.removeValue(forKey: account) }
    }
    let memory = MemoryCredentialAccess()
    memory.values["GROQ_API_KEY"] = "keychain-groq"
    memory.values["CEREBRAS_API_KEY"] = "keychain-cerebras"
    let credentials = CheckerCredentials(store: memory, overrideLookup: {
        $0 == "GROQ_API_KEY" ? "environment-groq" : nil
    })
    guard credentials.resolve(.groq) == "environment-groq",
          credentials.resolve(.cerebras) == "keychain-cerebras",
          credentials.status(.groq).contains("environment"),
          credentials.status(.cerebras).contains("Keychain") else {
        FileHandle.standardError.write(
            "checker credential precedence self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    let failures = credentials.apply([.cerebras: .set("replacement-cerebras")])
    guard failures.isEmpty, credentials.resolve(.cerebras) == "replacement-cerebras" else {
        FileHandle.standardError.write(
            "checker credential save self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    _ = credentials.apply([.cerebras: .remove])
    guard credentials.resolve(.cerebras) == nil else {
        FileHandle.standardError.write(
            "checker credential removal self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    let tokenPath = NSTemporaryDirectory() + "/thoughtcrime-api-token-\(UUID().uuidString)"
    let token = loadUIAPIToken(path: tokenPath, environmentToken: "")
    let attributes = try? FileManager.default.attributesOfItem(atPath: tokenPath)
    let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue
    try? FileManager.default.removeItem(atPath: tokenPath)
    guard token.count == 64, permissions == 0o600 else {
        FileHandle.standardError.write(
            "UI API token self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    let editor = ProviderCredentialsEditor(statuses: [
        .groq: "Not configured", .cerebras: "Active: macOS Keychain",
    ], save: { _ in [] })
    guard editor.usesSecureInputs else {
        FileHandle.standardError.write(
            "provider credentials editor self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("checker credentials: environmentPrecedence=true keychainFallback=true " +
          "saveRemove=true secureEditor=true apiTokenPermissions=0600")
    exit(0)
}

if CommandLine.arguments.contains("--ui-command-api-selftest") {
    let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("thoughtcrime-ui-api-\(UUID().uuidString).jsonl")
    let api = UIStateServer(logURL: logURL,
                            token: "selftest-ui-token-0000000000000000")
    var handled: [String] = []
    api.actionHandler = { handled.append($0.name) }
    api.perform(.first, origin: .appKit)
    api.perform(.showHistory, origin: .appKit)
    api.perform(.hideHUD, origin: .http)
    api.perform(.showViolations, origin: .http)
    api.perform(.closeCheckRules, origin: .http)
    api.perform(.historyFilter("violations"), origin: .http)
    api.perform(.violationBubble(true), origin: .http)
    api.perform(.violationBubble(false), origin: .appKit)
    api.perform(.next, origin: .http)
    api.perform(.saveCheckRules(text: "SECRET_RULE_CONTENT", mode: "whole-text"),
                origin: .appKit)
    api.perform(.applyProviderCredentialEdits([.groq: .set("SECRET_PROVIDER_KEY")],
        completion: { _ in }), origin: .appKit)
    let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    try? FileManager.default.removeItem(at: logURL)
    guard handled == ["first", "show-history", "hide", "show-violations",
                      "check-rules/close",
                      "filter/violations", "violation-bubble/on",
                      "violation-bubble/off", "next",
                      "save-check-rules", "save-provider-credentials"],
          log.contains("\"origin\":\"appKit\""),
          log.contains("\"origin\":\"http\""),
          !log.contains("SECRET_RULE_CONTENT"),
          !log.contains("SECRET_PROVIDER_KEY") else {
        FileHandle.standardError.write(
            "UI command API self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("UI command API: appKit=true http=true sameHandler=true contentFreeLog=true")
    exit(0)
}

if CommandLine.arguments.contains("--keyboard-navigation-selftest") {
    let panel = ConstrainedPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                 styleMask: [.borderless], backing: .buffered,
                                 defer: false)
    var actions: [String] = []
    panel.previousRequested = { actions.append("previous") }
    panel.nextRequested = { actions.append("next") }
    panel.firstRequested = { actions.append("first") }
    panel.latestRequested = { actions.append("latest") }
    panel.openMessageRequested = { actions.append("open") }
    panel.violationsRequested = { actions.append("violations") }
    func press(_ keyCode: UInt16, _ characters: String = "",
               _ modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode)!
        _ = panel.performKeyEquivalent(with: event)
    }
    press(123); press(125); press(0, "k"); press(0, "j")
    press(115); press(119); press(36, "\r"); press(9, "v", [.command, .shift])
    guard actions == ["previous", "next", "previous", "next", "first",
                      "latest", "open", "violations"] else {
        FileHandle.standardError.write(
            "keyboard navigation self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    panel.contentView?.addSubview(editor)
    _ = panel.makeFirstResponder(editor)
    let actionCount = actions.count
    press(123); press(125); press(49, " "); press(0, "j")
    guard actions.count == actionCount else {
        FileHandle.standardError.write(
            "keyboard focus-preservation self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("keyboard navigation: arrows=true jk=true homeEnd=true open=true " +
          "violations=true focusedEditorPreserved=true")
    exit(0)
}

if CommandLine.arguments.contains("--status-item-foreground-selftest") {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    guard let button = item.button else {
        FileHandle.standardError.write(
            "status item foreground self-test failed: missing button\n".data(using: .utf8)!)
        exit(1)
    }
    // The violation flash colors both the shield and the count.
    button.title = " 2"
    button.contentTintColor = .systemRed
    button.attributedTitle = NSAttributedString(
        string: " 2", attributes: [.foregroundColor: NSColor.systemRed])
    restoreNativeStatusItemForeground(button)
    let titleColor = button.attributedTitle.length > 0
        ? button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil)
        : nil
    let usesNativeForeground = button.contentTintColor == nil &&
        (titleColor as? NSColor) != NSColor.systemRed && button.title == " 2"
    // The flash is a regular image that really draws the chosen color
    // (a template image or tint would be redrawn black or white).
    let redFlash = statusFlashImage(count: "2", color: .systemRed)
    let customColor = NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)
    let customFlash = statusFlashImage(count: "12", color: customColor)
    let flashDrawsColor = !redFlash.isTemplate && imageDrawsColor(redFlash, .systemRed) &&
        !customFlash.isTemplate && imageDrawsColor(customFlash, customColor) &&
        !imageDrawsColor(redFlash, customColor) && customFlash.size.width > redFlash.size.width
    NSStatusBar.system.removeStatusItem(item)
    guard usesNativeForeground, flashDrawsColor else {
        FileHandle.standardError.write(
            "status item foreground self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("status item foreground: native=true titleNative=true flashDrawsColor=true " +
          "customBackground=false")
    exit(0)
}
}
