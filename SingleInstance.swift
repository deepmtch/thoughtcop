// Ensures only one thinkpeek window runs at a time.

import Foundation

/// Terminate any other running thinkpeek before this one opens a window.
///
/// Matches on process *name* (`pgrep -x`), never the full command line: a
/// `-f thinkpeek` match would also hit the shell that launched us and kill the
/// user's terminal session.
func killOtherInstances() {
    let me = getpid()
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-x", "thinkpeek"]
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
        "thinkpeek: replaced \(others.count) running instance(s)\n".data(using: .utf8)!)
}
