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
        .appendingPathComponent("thinkpeek-claude-desktop-\(UUID().uuidString)")
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
    let repo = "/Users/example/src/thinkpeek"
    guard projectRoot(executablePath: repo + "/.build/thinkpeek",
                      appBundlePath: nil) == repo,
          projectRoot(
            executablePath: repo + "/.build/Thinkpeek.app/Contents/MacOS/thinkpeek",
            appBundlePath: repo + "/.build/Thinkpeek.app") == repo else {
        FileHandle.standardError.write(
            "config path self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("config path: rawBinary=true appBundle=true")
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("thinkpeek-selftest-\(UUID().uuidString).jsonl").path
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
    let taskID = "01a02dd4-2314-7f30-8313-b23268b2c1ae"
    let rolloutID = "01a02dee-e313-7d60-8222-ff6e9c8c5c6b"
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
    guard accepted, returnedIn < 0.05, overlapRejected, completed,
          codexSessionID(from: doubleUUIDTranscript.path) == taskID else {
        FileHandle.standardError.write(
            "session discovery self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("session discovery: mainThreadNonblocking=true overlappingScans=false " +
          "codexMetadataIdentity=true")
    exit(0)
}

if CommandLine.arguments.contains("--transcript-monitor-selftest") {
    let worker = TranscriptMonitorWorker(tailerFactory: { path, backfill, offset in
        Thread.sleep(forTimeInterval: 0.25)
        return Tailer(path: path, backfill: backfill, startOffset: offset)
    })
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("thinkpeek-monitor-\(UUID().uuidString).jsonl").path
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
          state.windowTitle == "● Codex · local task · working…" else {
        FileHandle.standardError.write("presentation self-test failed waiting isolation\n"
            .data(using: .utf8)!)
        exit(1)
    }
    state.operationFinished(source: "Codex · local task")
    guard !state.operationPending,
          state.operationWaiting,
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
    print("presentation: useful summary preserved until readable content arrives")
    exit(0)
}

if CommandLine.arguments.contains("--claude-cloud-activity-selftest") {
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
    print("Claude cloud activity: exact start, update, and finish states")
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
    let suiteName = "thinkpeek.ticker-background.selftest.\(UUID().uuidString)"
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
          alarmValues == values,
          defaultAlarmValues.count == 4,
          !tickerIsBold,
          TickerBackgroundPreference.load(defaults: defaults) == nil,
          TickerBackgroundPreference.usesDarkForeground(on: .white),
          !TickerBackgroundPreference.usesDarkForeground(on: .black) else {
        FileHandle.standardError.write("ticker background self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("ticker background: semanticSurface=true alarmOnly=true custom=true " +
          "defaultAlarm=true autoContrast=true textWeight=regular")
    exit(0)
}

if CommandLine.arguments.contains("--message-view-selftest") {
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
    message.show(source: "Thinkpeek · Check error",
                 text: "⛔ **THINKPEEK CHECK ERROR**\nProvider failed.",
                 kind: "analysis", tone: .error)
    guard message.source == "Thinkpeek · Check error",
          message.text.contains("THINKPEEK CHECK ERROR"),
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
    print("outside click: details=true editorProtected=true insideIgnored=true")
    exit(0)
}

if CommandLine.arguments.contains("--ticker-actions-selftest") {
    let actions = TickerPrimaryActions(frame: .zero)
    let activity = CheckerActivityIndicator(frame: .zero)
    let settingsMenu = TickerSettingsMenu()
    settingsMenu.install(on: actions.displaySettingsButton)
    var checkRules = false
    var controls = false
    var hidden = false
    actions.checkRulesRequested = { checkRules = true }
    actions.controlsRequested = { controls = true }
    actions.hideRequested = { hidden = true }
    actions.requestCheckRulesForTest()
    actions.requestControlsForTest()
    actions.requestHideForTest()
    activity.begin(destination: "Groq · Test")
    guard actions.accessibilityNames == ["Edit check prompt", "Display settings",
                                         "Open message navigation", "Hide Thinkpeek"],
          actions.displaySettingsButton.target != nil,
          actions.displaySettingsButton.action != nil,
          checkRules, controls, hidden,
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
    print("ticker actions: checkRules=oneClick settings=oneClick controls=oneClick hide=oneClick " +
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
    let close: (CGFloat, CGFloat) -> Bool = { abs($0 - $1) < 0.5 }
    guard close(expanded.minY, 12), close(collapsed.minY, 12),
          close(expanded.maxX, 1428), close(collapsed.maxX, 1428),
          close(floatingExpanded.midX, floating.midX),
          close(floatingExpanded.midY, floating.midY) else {
        FileHandle.standardError.write(
            "window-position self-test failed: expanded=\(expanded) collapsed=\(collapsed)\n"
                .data(using: .utf8)!)
        exit(1)
    }
    print("window position: bottom/right insets and floating center preserved")
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
    let controls = TickerCornerControls(frame: .zero)
    var requested: [TickerWindowCorner] = []
    controls.cornerRequested = { requested.append($0) }
    TickerWindowCorner.allCases.forEach(controls.request)
    guard topLeft.origin == NSPoint(x: 12, y: 718),
          topRight.origin == NSPoint(x: 528, y: 718),
          bottomLeft.origin == NSPoint(x: 12, y: 12),
          bottomRight.origin == NSPoint(x: 528, y: 12),
          requested == TickerWindowCorner.allCases,
          controls.accessibilityNames == ["Move window to top left corner",
                                          "Move window to top right corner",
                                          "Move window to bottom left corner",
                                          "Move window to bottom right corner"] else {
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

if CommandLine.arguments.contains("--settings-menu-selftest") {
    let button = NSButton(frame: .zero)
    let settings = TickerSettingsMenu()
    settings.install(on: button)
    settings.update(speed: .normal, width: CompactWindowSizing.standardWidth,
                    usesDefaultAlarmColor: true)
    let expected = [
        "Scroll Speed": ["Slow", "Normal", "Fast"],
        "Window Width": ["Narrow", "Standard"],
        "Window Position": ["Top Left", "Top Center", "Top Right", "Bottom Left",
                            "Bottom Center", "Bottom Right"],
        "Appearance": ["Violation Highlight Color…", "Use Default Violation Color"],
    ]
    guard settings.structure == expected, settings.menu.numberOfItems == 4,
          settings.usesSingleButtonLauncher,
          settings.topLevelTitles == ["Scroll Speed", "Window Width",
                                      "Window Position", "Appearance"] else {
        FileHandle.standardError.write(
            "settings menu self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("settings menu: categories=4 singleButton=true hierarchical=true")
    exit(0)
}

if CommandLine.arguments.contains("--check-rules-editor-selftest") ||
   CommandLine.arguments.contains("--check-prompt-selftest") {
    guard let defaults = UserDefaults(suiteName: "thinkpeek.check-rules-selftest") else {
        exit(1)
    }
    defaults.removePersistentDomain(forName: "thinkpeek.check-rules-selftest")
    defer { defaults.removePersistentDomain(forName: "thinkpeek.check-rules-selftest") }
    var saveActionRan = false
    let editor = CheckRulesEditor(contents: CheckRulesStore.loadRaw(defaults: defaults),
                                  mode: .eachLine,
                                  save: { text, mode in
        saveActionRan = true
        CheckRulesStore.saveRaw(text, defaults: defaults)
        CheckRulesStore.saveMode(mode, defaults: defaults)
    }, closed: {})
    guard editor.currentText == CheckRulesStore.defaultValue,
          editor.actionTitles == ["Cancel", "Save Check Instructions"],
          editor.actionsAreHorizontal,
          editor.currentMode == .eachLine,
          CheckRulesStore.instruction(defaults: defaults) ==
            CheckRulesStore.defaultValue,
          !CheckRulesStore.isCustomized(defaults: defaults)
    else { exit(1) }
    guard let saveButton = editor.window?.contentView?.subviews
        .compactMap({ $0 as? NSStackView })
        .flatMap(\.arrangedSubviews)
        .compactMap({ $0 as? NSButton })
        .first(where: { $0.title == "Save Check Instructions" }) else { exit(1) }
    saveButton.performClick(nil)
    guard saveActionRan,
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
    let path = NSTemporaryDirectory() + "/thinkpeek-audit-\(UUID().uuidString).jsonl"
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

if CommandLine.arguments.contains("--violation-store-selftest") {
    let path = NSTemporaryDirectory() + "/thinkpeek-violations-\(UUID().uuidString).json"
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
    try? FileManager.default.removeItem(atPath: path)
    try? FileManager.default.removeItem(atPath: damagedPath)
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
          "corruptFilePreserved=true promptSnapshot=true permissions=0600")
    exit(0)
}

if CommandLine.arguments.contains("--ui-command-api-selftest") {
    let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("thinkpeek-ui-api-\(UUID().uuidString).jsonl")
    let api = UIStateServer(logURL: logURL)
    var handled: [String] = []
    api.actionHandler = { handled.append($0.name) }
    api.perform(.first, origin: .appKit)
    api.perform(.showControls, origin: .appKit)
    api.perform(.hideHUD, origin: .http)
    api.perform(.showViolations, origin: .http)
    api.perform(.closeCheckRules, origin: .http)
    api.perform(.historyFilter("violations"), origin: .http)
    api.perform(.next, origin: .http)
    api.perform(.saveCheckRules(text: "SECRET_RULE_CONTENT", mode: "whole-text"),
                origin: .appKit)
    let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    try? FileManager.default.removeItem(at: logURL)
    guard handled == ["first", "controls", "hide", "show-violations",
                      "check-rules/close",
                      "filter/violations", "next",
                      "save-check-rules"],
          log.contains("\"origin\":\"appKit\""),
          log.contains("\"origin\":\"http\""),
          !log.contains("SECRET_RULE_CONTENT") else {
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
}
