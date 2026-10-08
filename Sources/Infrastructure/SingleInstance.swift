// Ensures only one thoughtcop window runs at a time.

import Foundation

/// Terminate any other running thoughtcop before this one opens a window.
///
/// Matches on process *name* (`pgrep -x`), never the full command line: a
/// `-f thoughtcop` match would also hit the shell that launched us and kill the
/// user's terminal session.
func killOtherInstances() {
    let me = getpid()
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    // The pre-rename process name is included so an old Thinkpeek that is
    // still running is replaced too (a rebuild after the rename left both).
    pgrep.arguments = ["-x", "thoughtcop|doublethink|thoughtcrime|thinkpeek"]
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
        .filter { $0 != me && !isIsolatedTestInstance($0) }
    guard !others.isEmpty else { return }

    for pid in others { kill(pid, SIGTERM) }
    usleep(300_000)
    for pid in others where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    FileHandle.standardError.write(
        "thoughtcop: replaced \(others.count) running instance(s)\n".data(using: .utf8)!)
}

/// True when `pid` was started with `--isolated-e2e`. Test instances share the
/// process name; a real launch during a test run must not terminate them
/// (a user-opened app killed the isolated suite with SIGTERM on 2026-10-08).
func isIsolatedTestInstance(_ pid: pid_t) -> Bool {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-o", "args=", "-p", String(pid)]
    let pipe = Pipe()
    ps.standardOutput = pipe
    ps.standardError = Pipe()
    guard (try? ps.run()) != nil else { return false }
    ps.waitUntilExit()
    let args = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return args.split(separator: " ").contains("--isolated-e2e")
}
