// Headless and AppKit-backed regression checks callable from the app binary.

import AppKit
import Foundation

func runRequestedSelfTest() {

if CommandLine.arguments.contains("--selftest") {
    guard let path = newestTranscript() else {
        FileHandle.standardError.write("no Claude or Codex transcripts found\n".data(using: .utf8)!)
        exit(1)
    }
    print("active: \(path)")
    for b in Tailer(path: path, backfill: 5).drain() {
        print("  [\(b.ts)] \(b.sealed ? "<sealed>" : String(b.text.prefix(110)))")
    }
    exit(0)
}

if CommandLine.arguments.contains("--evaluator-selftest") {
    let instruction = "First line is not a category.\n# This remains user text.\nBANANA only.\n"
    let evidence = EvaluationRecord(content: "Planning the next source edit")
    let envelope = evaluationEnvelope(instruction: instruction, evidence: evidence)
    let oversizedEvidence = EvaluationRecord(content: String(repeating: "x", count: 41_245))
    let oversizedEnvelope = serializedEvaluationEnvelope(
        instruction: instruction, evidence: oversizedEvidence)
    guard envelope["EVALUATION_INSTRUCTION"] as? String == instruction,
          let record = envelope["EVIDENCE_RECORD"] as? [String: Any],
          record["event_type"] as? String == "reasoning_summary",
          record["content"] as? String == "Planning the next source edit",
          record["record_complete"] as? Bool == true,
          let decision = parseEvaluationDecision(Data(
            #"{"alert":true,"reason":"changed","evidence":"Sources/Test.swift"}"#.utf8)),
          decision.alert, decision.reason == "changed",
          parseEvaluationDecision(Data(#"{"alert":"yes"}"#.utf8)) == nil,
          let oversizedEnvelope,
          oversizedEnvelope.count > MAX_EXTERNAL_ENVELOPE_BYTES else {
        FileHandle.standardError.write(
            "evaluator envelope self-test failed\n".data(using: .utf8)!)
        exit(1)
    }

    let codexLine = #"{"timestamp":"2026-08-13T10:00:00.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","status":"completed","call_id":"call_1","input":"tools.apply_patch(...)"}}"#
    let claudeLine = #"{"timestamp":"2026-08-13T10:00:01.000Z","type":"assistant","message":{"content":[{"type":"tool_use","id":"tool_1","name":"Edit","input":{"file_path":"Sources/Test.swift"}}]}}"#
    let duplicateEventLine = #"{"timestamp":"2026-08-13T10:00:01.900Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"**Assessing safe change**"}}"#
    let reasoningLine = #"{"timestamp":"2026-08-13T10:00:02.000Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"**Assessing safe change**"},{"type":"summary_text","text":"**Planning a safe change**"}],"encrypted_content":"sealed"}}"#
    let toolRecords = blocks(in: codexLine) + blocks(in: claudeLine)
    let reasoningRecords = blocks(in: reasoningLine)
    guard toolRecords.isEmpty,
          blocks(in: duplicateEventLine).isEmpty,
          reasoningRecords.count == 1,
          reasoningRecords[0].kind == .thinking,
          reasoningRecords[0].text ==
            "**Assessing safe change**\n\n**Planning a safe change**",
          reasoningRecords[0].evaluationRecord.json["event_type"] as? String ==
            "reasoning_summary" else {
        FileHandle.standardError.write(
            "reasoning-only boundary self-test failed\n".data(using: .utf8)!)
        exit(1)
    }

    let preview = MessagePreview(source: "Codex · Test", text: "Tool call: exec",
                                 kind: "analysis")
    preview.evaluation = .alert(decision)
    guard preview.tickerText.contains("⚠ changed"),
          preview.detailText.contains("Sources/Test.swift"),
          preview.displaySource == "Thinkpeek · Warning",
          preview.readerTone == .warning else {
        FileHandle.standardError.write(
            "alert presentation self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    preview.evaluation = .failed("provider payload exceeded its limit")
    guard preview.tickerText.contains("⛔ Thinkpeek check failed"),
          preview.detailText.contains("THINKPEEK CHECK ERROR"),
          preview.detailText.contains("Original item from Codex · Test"),
          preview.displaySource == "Thinkpeek · Check error",
          preview.readerTone == .error else {
        FileHandle.standardError.write(
            "check-error attribution self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("evaluator: verbatim=true binary=true reasoningOnly=true toolRecordsExcluded=true " +
          "completeSummaryArrays=true " +
          "oversizeMeasured=true invalidVisible=true alertAttached=true")
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
    print("presentation: useful summary preserved until readable content arrives")
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
    guard preview.source == source,
          preview.text == event.text,
          !preview.source.isEmpty else {
        FileHandle.standardError.write("source-context self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("source context: \(preview.source) → \(preview.text)")
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
        .flatMap(TickerBackgroundPreference.components(of:)) ?? []
    TickerBackgroundPreference.save(sample, defaults: defaults)
    let restored = TickerBackgroundPreference.load(defaults: defaults)
    let values = restored.flatMap(TickerBackgroundPreference.components(of:)) ?? []
    TickerBackgroundPreference.save(nil, defaults: defaults)
    guard initial.count == 4,
          abs(initial[0] - 0.97) < 0.001,
          abs(initial[1] - 0.96) < 0.001,
          abs(initial[2] - 0.56) < 0.001,
          values.count == 4,
          abs(values[0] - 0.2) < 0.001,
          abs(values[1] - 0.4) < 0.001,
          abs(values[2] - 0.7) < 0.001,
          abs(values[3] - 0.85) < 0.001,
          TickerBackgroundPreference.load(defaults: defaults) == nil,
          TickerBackgroundPreference.usesDarkForeground(on: .white),
          !TickerBackgroundPreference.usesDarkForeground(on: .black) else {
        FileHandle.standardError.write("ticker background self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("ticker background: stickyDefault=true persisted=true custom=true " +
          "systemReset=true autoContrast=true")
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
          message.lifecycleButtonTitles == ["Done", "More"],
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
    print("message view: dedicated=true markdownRendered=true done=true overflow=true " +
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
            isReaderOpen: false, wasFollowingLatest: true) else {
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
    var checkRules = false
    var controls = false
    actions.checkRulesRequested = { checkRules = true }
    actions.controlsRequested = { controls = true }
    actions.requestCheckRulesForTest()
    actions.requestControlsForTest()
    guard actions.accessibilityNames == ["Edit what to check", "Open controls and settings"],
          checkRules, controls else {
        FileHandle.standardError.write("ticker actions self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("ticker actions: checkRules=oneClick controls=oneClick accessible=true")
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
    let chatGPT = ProviderIconView(frame: .zero)
    chatGPT.update(source: "Codex · Thought watch 2")
    let explicitChatGPT = MessageProvider.detect(from: "ChatGPT · Example")
    let nativeIconsAvailable = [MessageProvider.claude, .chatGPT].allSatisfy {
        guard let path = $0.installedApplicationPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
    guard claude.provider == .claude,
          chatGPT.provider == .chatGPT,
          explicitChatGPT == .chatGPT,
          claude.image != nil,
          chatGPT.image != nil,
          claude.accessibilityLabel() == "Provider: Claude",
          chatGPT.accessibilityLabel() == "Provider: ChatGPT" else {
        FileHandle.standardError.write(
            "provider icon self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("provider icons: claude=true chatGPT=true nativeAppIcons=\(nativeIconsAvailable) accessible=true")
    exit(0)
}

if CommandLine.arguments.contains("--settings-menu-selftest") {
    let button = NSButton(frame: .zero)
    let settings = TickerSettingsMenu()
    settings.install(on: button)
    settings.update(speed: .normal, width: CompactWindowSizing.standardWidth,
                    usesSystemBackground: true)
    let expected = [
        "Ticker Speed": ["Slow", "Normal", "Fast"],
        "Window Width": ["Narrow", "Standard"],
        "Window Position": ["Top Left", "Top Center", "Top Right", "Bottom Left",
                            "Bottom Center", "Bottom Right"],
        "Appearance": ["Ticker Background…", "Use System Background"],
    ]
    guard settings.structure == expected, settings.menu.numberOfItems == 4,
          settings.usesSingleButtonLauncher,
          settings.topLevelTitles == ["Ticker Speed", "Window Width",
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
          editor.actionTitles == ["Cancel", "Save"], editor.actionsAreHorizontal,
          editor.currentMode == .eachLine,
          CheckRulesStore.instruction(defaults: defaults) ==
            CheckRulesStore.defaultValue,
          !CheckRulesStore.isCustomized(defaults: defaults)
    else { exit(1) }
    guard let saveButton = editor.window?.contentView?.subviews
        .compactMap({ $0 as? NSStackView })
        .flatMap(\.arrangedSubviews)
        .compactMap({ $0 as? NSButton })
        .first(where: { $0.title == "Save" }) else { exit(1) }
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
          CompactWindowSizing.headerStyle(for: 700) == .inline,
          CompactWindowSizing.headerHeight(for: 400) == 82,
          CompactWindowSizing.headerHeight(for: 560) == 82,
          CompactWindowSizing.headerHeight(for: 700) == 52,
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
    guard CompactInteractionUX.clickDecisionDelay >= 0.18,
          CompactInteractionUX.clickDecisionDelay <= 0.30,
          CompactInteractionUX.dragTolerance >= 2 else {
        FileHandle.standardError.write("compact interaction self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("compact interaction: hover=false singleClick=message doubleClick=controls")
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
    var quit = false
    controls.closeRequested = { closed = true }
    controls.quitRequested = { quit = true }
    controls.requestClose(nil)
    controls.requestQuit(nil)
    guard controls.buttonTitles == ["Done", "More"],
          controls.accessibilityNames == ["Close details and return to ticker",
                                          "More application actions"],
          controls.overflowMenuTitles == ["Quit Thinkpeek"], closed, quit else {
        FileHandle.standardError.write(
            "exit controls self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("exit controls: done=true quitInOverflow=true visible=true accessible=true")
    exit(0)
}

if CommandLine.arguments.contains("--privacy-audit-selftest") {
    let path = NSTemporaryDirectory() + "/thinkpeek-audit-\(UUID().uuidString).jsonl"
    let audit = PrivacyAudit(path: path)
    audit.start()
    let toolLine = #"{"timestamp":"2026-08-15T00:00:00Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call_1","output":"TOP_SECRET_TOOL_CONTENT"}}"#
    let reasoningLine = #"{"timestamp":"2026-08-15T00:00:01Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"PRIVATE_REASONING_CONTENT"}],"encrypted_content":"sealed"}}"#
    audit.recordTranscriptLine(toolLine, sourcePath: "/tmp/session.jsonl")
    audit.recordTranscriptLine(reasoningLine, sourcePath: "/tmp/session.jsonl")
    audit.recordExternalRequest(source: "Codex · Test", destination: "Provider · Model",
                                envelopeBytes: 321)
    let log = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    try? FileManager.default.removeItem(atPath: path)
    guard log.contains("app_started"),
          log.contains("tool_record_discarded"),
          log.contains("reasoning_selected"),
          log.contains("external_reasoning_request"),
          log.contains("\"envelope_bytes\":321"),
          !log.contains("TOP_SECRET_TOOL_CONTENT"),
          !log.contains("PRIVATE_REASONING_CONTENT") else {
        FileHandle.standardError.write(
            "privacy audit self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("privacy audit: reasoning=true toolsDiscarded=true outbound=true contentLogged=false")
    exit(0)
}

if CommandLine.arguments.contains("--ui-command-api-selftest") {
    let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("thinkpeek-ui-api-\(UUID().uuidString).jsonl")
    let api = UIStateServer(logURL: logURL)
    var handled: [String] = []
    api.actionHandler = { handled.append($0.name) }
    api.perform(.showControls, origin: .appKit)
    api.perform(.next, origin: .http)
    api.perform(.saveCheckRules(text: "SECRET_RULE_CONTENT", mode: "whole-text"),
                origin: .appKit)
    let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    try? FileManager.default.removeItem(at: logURL)
    guard handled == ["controls", "next", "save-check-rules"],
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
}
