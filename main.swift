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
