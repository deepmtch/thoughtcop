// thinkpeek command-line entry point.
//
// Build with ./build.sh, then run ./thinkpeek.

import AppKit
import Foundation

// MARK: - Entry point

if CommandLine.arguments.contains("--drift-status") {
    let state = driftStatus()
    print(state.ready ? "ready: \(state.detail)" : "disabled: \(state.detail)")
    exit(state.ready ? 0 : 1)
}

// Headless API for tests and integrations. It returns the exact presentation
// objects consumed by the AppKit renderer, not a second test-only parser.

if let i = CommandLine.arguments.firstIndex(of: "--ui-json"),
   i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    let events = text.components(separatedBy: "\n")
        .flatMap { blocks(in: $0) }
        .map { uiEvent(for: $0).json }
    let payload: [String: Any] = [
        "schemaVersion": 1,
        "sourcePath": path,
        "sourceTitle": sessionTitle(of: rootSessionPath(for: path)) ?? NSNull(),
        "events": events,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                   options: [.prettyPrinted, .sortedKeys]) else {
        exit(1)
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    exit(0)
}

if CommandLine.arguments.contains("--sessions") {
    let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
    print("Auto — all active sessions")
    for s in recentSessions() {
        print("\(fmt.string(from: s.modified))  \(s.project) · \(s.title)")
    }
    exit(0)
}

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
    let preview = (source: source, body: renderedBody(event.text, kind: event.kind))
    guard preview.source == source,
          preview.body.string == event.text,
          !preview.source.isEmpty else {
        FileHandle.standardError.write("source-context self-test failed\n"
            .data(using: .utf8)!)
        exit(1)
    }
    print("source context: \(preview.source) → \(preview.body.string)")
    exit(0)
}

if CommandLine.arguments.contains("--window-position-selftest") {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let bottomRightPeek = NSRect(x: 968, y: 12, width: 460, height: 98)
    let expanded = resizedWindowFrame(bottomRightPeek, toHeight: 210,
                                      width: 560, within: visible)
    let collapsed = resizedWindowFrame(expanded, toHeight: 98,
                                       width: 460, within: visible)
    let floating = NSRect(x: 400, y: 300, width: 460, height: 98)
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

if CommandLine.arguments.contains("--hover-ux-selftest") {
    guard HoverUX.revealDelay <= 0.10,
          HoverUX.hideDelay >= 0.30,
          HoverUX.dragTolerance >= 2 else {
        FileHandle.standardError.write("hover UX self-test failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("hover UX: reveal=80ms clickFallback=true dragTolerance=2pt")
    exit(0)
}

// Headless check of the alarm path: no window, no transcript, just the model.
if let i = CommandLine.arguments.firstIndex(of: "--check"), i + 1 < CommandLine.arguments.count {
    print("triggers: \(loadTriggers().count) from \(TRIGGERS_FILE)")
    var finished = false
    checkDrift(CommandLine.arguments[i + 1]) { outcome, ms in
        print("latency : \(Int(ms)) ms")
        switch outcome {
        case .scored(let hits, let provider):
            print("provider: \(provider)")
            print("fired   : \(hits.count)")
            for h in hits { print("          ▸ \(h.trigger)  — \(h.why)") }
        case .failed(let message):
            print("failed  : \(message)")
        }
        finished = true
    }
    let deadline = Date().addingTimeInterval(15)
    while !finished, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    exit(finished ? 0 : 1)
}

killOtherInstances()

let app = NSApplication.shared
let hud = HUD()
app.delegate = hud
app.setActivationPolicy(.accessory)
app.run()
