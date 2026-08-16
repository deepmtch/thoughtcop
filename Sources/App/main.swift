// Thinkpeek application and command-line entry point.

import AppKit
import Foundation

if CommandLine.arguments.contains("--drift-status") {
    let state = driftStatus()
    print(state.ready ? "ready: \(state.detail)" : "disabled: \(state.detail)")
    exit(state.ready ? 0 : 1)
}

// Headless API for tests and integrations. It returns the exact presentation
// objects consumed by the AppKit renderer, not a second test-only parser.
if let index = CommandLine.arguments.firstIndex(of: "--ui-json"),
   index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
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
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    print("Auto — all active sessions")
    for session in recentSessions() {
        print("\(formatter.string(from: session.modified))  " +
              "\(session.project) · \(session.title)")
    }
    exit(0)
}

runRequestedSelfTest()

// Headless check of the alarm path: no window or transcript tailing.
var requestedEvidence: EvaluationRecord?
if let index = CommandLine.arguments.firstIndex(of: "--check"),
          index + 1 < CommandLine.arguments.count {
    requestedEvidence = EvaluationRecord(content: CommandLine.arguments[index + 1])
}

if let requestedEvidence {
    print("evaluation instruction: verbatim from local app storage")
    var finished = false
    PrivacyAudit.shared.start()
    checkDrift(requestedEvidence, source: "explicit command") { outcome, milliseconds in
        print("latency : \(Int(milliseconds)) ms")
        switch outcome {
        case .scored(let decision, let provider):
            print("provider: \(provider)")
            print("alert   : \(decision.alert)")
            print("reason  : \(decision.reason)")
            print("evidence: \(decision.evidence)")
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

if !ISOLATED_E2E { killOtherInstances() }

let app = NSApplication.shared
let hud = HUD()
app.delegate = hud
app.setActivationPolicy(.accessory)
app.run()
