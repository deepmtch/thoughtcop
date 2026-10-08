// Ensures only one thoughtcrime window runs at a time.

import Foundation

/// Terminate any other running thoughtcrime before this one opens a window.
///
/// Matches on process *name* (`pgrep -x`), never the full command line: a
/// `-f thoughtcrime` match would also hit the shell that launched us and kill the
/// user's terminal session.
func killOtherInstances() {
    let me = getpid()
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    // The pre-rename process name is included so an old Thinkpeek that is
    // still running is replaced too (a rebuild after the rename left both).
    pgrep.arguments = ["-x", "thoughtcrime|thinkpeek"]
    let pipe = Pipe()
    pgrep.standardOutput = pipe
    pgrep.standardError = Pipe()
    guard (try? pgrep.run()) != nil else { return }
    let deadline = Date().addingTimeInterval(0.5)
    while pgrep.isRunning, Date() < deadline { usleep(10_000) }
    guard !pgrep.isRunning else {
        pgrep.terminate()
        return
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()

    let others = (String(data: data, encoding: .utf8) ?? "")
        .split(separator: "\n")
        .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        .filter { $0 != me }
    guard !others.isEmpty else { return }

    for pid in others { kill(pid, SIGTERM) }
    usleep(300_000)
    for pid in others where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    FileHandle.standardError.write(
        "thoughtcrime: replaced \(others.count) running instance(s)\n".data(using: .utf8)!)
}
