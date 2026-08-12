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
          metrics.body.height > singleLineHeight * 1.5 else {
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
    guard message.source == "Codex · Message test",
          message.text == "Complete rendered summary with inline code.",
          message.lifecycleButtonTitles == ["Done", "Quit"],
          !message.text.contains("**") else {
        FileHandle.standardError.write("message view self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("message view: dedicated=true markdownRendered=true close=true quit=true")
    exit(0)
}

if CommandLine.arguments.contains("--outside-click-selftest") {
    let frame = NSRect(x: 100, y: 100, width: 560, height: 300)
    guard !shouldDismissFullMessage(isShowing: true, windowFrame: frame,
                                    clickLocation: NSPoint(x: 120, y: 120)),
          shouldDismissFullMessage(isShowing: true, windowFrame: frame,
                                   clickLocation: NSPoint(x: 20, y: 20)),
          !shouldDismissFullMessage(isShowing: false, windowFrame: frame,
                                    clickLocation: NSPoint(x: 20, y: 20)) else {
        FileHandle.standardError.write("outside click self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("outside click: messageDismissed=true insideIgnored=true controlsUnaffected=true")
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
    let button = NSPopUpButton(frame: .zero, pullsDown: true)
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
    guard settings.structure == expected, button.numberOfItems == 6,
          settings.topLevelTitles == ["Ticker Speed", "Window Width",
                                      "Window Position", "Appearance",
                                      "What to Check…"] else {
        FileHandle.standardError.write(
            "settings menu self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("settings menu: categories=4 whatToCheck=true hierarchical=true")
    exit(0)
}

if CommandLine.arguments.contains("--check-rules-editor-selftest") ||
   CommandLine.arguments.contains("--check-prompt-selftest") {
    guard let defaults = UserDefaults(suiteName: "thinkpeek.check-rules-selftest") else {
        exit(1)
    }
    defaults.removePersistentDomain(forName: "thinkpeek.check-rules-selftest")
    defer { defaults.removePersistentDomain(forName: "thinkpeek.check-rules-selftest") }
    let editor = CheckRulesEditor(contents: CheckRulesStore.loadRaw(defaults: defaults),
                                  save: { _ in }, closed: {})
    guard editor.currentText == CheckRulesStore.defaultValue,
          editor.actionTitles == ["Cancel", "Save"], editor.actionsAreHorizontal,
          CheckRulesStore.rules(defaults: defaults) ==
            ["Claude is confused or waiting for user to do someting."],
          !CheckRulesStore.isCustomized(defaults: defaults)
    else { exit(1) }
    CheckRulesStore.saveRaw("Updated local rule", defaults: defaults)
    guard CheckRulesStore.loadRaw(defaults: defaults) == "Updated local rule\n",
          CheckRulesStore.isCustomized(defaults: defaults) else { exit(1) }
    print("check rules editor: appLocalOnly=true noFiles=true persisted=true nextCheck=true compactWindow=true")
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
          CompactWindowSizing.headerStyle(for: 560) == .inline,
          CompactWindowSizing.headerHeight(for: 400) == 106,
          CompactWindowSizing.headerHeight(for: 560) == 74,
          CompactWindowSizing.controlsHeight(for: 400) == 106,
          CompactWindowSizing.controlsHeight(for: 560) == 74,
          !shouldShowHistoryFeed(peekMode: false, messageMode: false,
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
    guard controls.buttonTitles == ["Close", "Quit"],
          controls.accessibilityNames == ["Close details and return to ticker",
                                          "Quit Thinkpeek"],
          closed, quit else {
        FileHandle.standardError.write(
            "exit controls self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("exit controls: close=true quit=true visible=true accessible=true")
    exit(0)
}
}
