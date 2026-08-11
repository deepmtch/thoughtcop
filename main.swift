// thinkpeek — always-on-top window streaming Claude Code's reasoning in real time.
//
// AppKit rather than Tk: the system Tk (8.5) is deprecated on macOS 26+ and
// renders a blank content area.
//
//   swiftc -O -swift-version 5 -o thinkpeek main.swift
//   ./thinkpeek            # normal
//   ./thinkpeek --selftest # parse-only, no window

import AppKit
import Foundation

let PROJECTS = ("~/.claude/projects" as NSString).expandingTildeInPath
let POLL = 0.4          // seconds between drains of the active file
let RESCAN = 2.0        // seconds between re-picking the active session
let BACKFILL = 3        // reasoning blocks of history shown on attach

let BG = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
let FG = NSColor(srgbRed: 0.84, green: 0.86, blue: 0.89, alpha: 1)
let DIM = NSColor(srgbRed: 0.42, green: 0.45, blue: 0.52, alpha: 1)
let ACCENT = NSColor(srgbRed: 0.79, green: 0.64, blue: 0.15, alpha: 1)
let SEALED = NSColor(srgbRed: 0.48, green: 0.36, blue: 0.62, alpha: 1)

// MARK: - Transcript reading

struct Block {
    let ts: String
    let text: String
    let sealed: Bool
}

/// The session Claude Code is writing to right now: newest .jsonl under any project.
func newestTranscript() -> String? {
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(atPath: PROJECTS) else { return nil }
    var best: (path: String, when: Date)?
    for dir in dirs {
        let sub = PROJECTS + "/" + dir
        guard let files = try? fm.contentsOfDirectory(atPath: sub) else { continue }
        for file in files where file.hasSuffix(".jsonl") {
            let path = sub + "/" + file
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let when = attrs[.modificationDate] as? Date else { continue }
            if best == nil || when > best!.when { best = (path, when) }
        }
    }
    return best?.path
}

/// Reasoning blocks carried by one JSONL record. Unparseable lines yield nothing.
func blocks(in line: String) -> [Block] {
    guard let data = line.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let message = obj["message"] as? [String: Any],
          let content = message["content"] as? [[String: Any]] else { return [] }
    let ts = obj["timestamp"] as? String ?? ""
    return content.compactMap { block in
        guard block["type"] as? String == "thinking" else { return nil }
        let text = ((block["thinking"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Block(ts: ts, text: text, sealed: text.isEmpty)
    }
}

/// Follows one JSONL file by byte offset, tolerating partial writes and truncation.
final class Tailer {
    let path: String
    let session: String
    private var offset: UInt64 = 0
    private var buf = ""
    private var pending: [Block] = []

    init(path: String, backfill: Int = BACKFILL) {
        self.path = path
        self.session = String((path as NSString).lastPathComponent.prefix(8))
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        offset = fileSize() ?? 0
        let all = text.components(separatedBy: "\n").flatMap { blocks(in: $0) }
        pending = backfill > 0 ? Array(all.suffix(backfill)) : []
    }

    private func fileSize() -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.size] as? NSNumber)?.uint64Value
    }

    func drain() -> [Block] {
        var out = pending
        pending = []
        guard let size = fileSize() else { return out }
        if size < offset { offset = 0; buf = "" }   // truncated or rotated
        guard size > offset, let fh = FileHandle(forReadingAtPath: path) else { return out }
        defer { try? fh.close() }
        try? fh.seek(toOffset: offset)
        let data = fh.readDataToEndOfFile()
        offset += UInt64(data.count)
        buf += String(data: data, encoding: .utf8) ?? ""
        var lines = buf.components(separatedBy: "\n")
        buf = lines.removeLast()                     // trailing partial line
        for line in lines { out += blocks(in: line) }
        return out
    }
}

// MARK: - Single instance

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
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    pgrep.waitUntilExit()

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

// MARK: - Window

final class HUD: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var textView: NSTextView!
    private var tailer: Tailer?
    private var lastScan = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NSPanel(
            contentRect: NSRect(x: 60, y: 200, width: 470, height: 340),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Claude reasoning"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = BG
        panel.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        textView = NSTextView(frame: scroll.bounds)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = BG
        textView.textContainerInset = NSSize(width: 9, height: 9)
        scroll.documentView = textView

        panel.contentView!.addSubview(scroll)
        panel.orderFrontRegardless()

        emit("waiting for a session…\n", ACCENT, 10, bold: true)
        Timer.scheduledTimer(withTimeInterval: POLL, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    private func emit(_ s: String, _ color: NSColor, _ size: CGFloat, bold: Bool = false,
                      italic: Bool = false) {
        var font = NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 1.5
        textView.textStorage?.append(NSAttributedString(string: s, attributes: [
            .foregroundColor: color, .font: font, .paragraphStyle: para,
        ]))
        textView.scrollToEndOfDocument(nil)
    }

    private func tick() {
        if Date().timeIntervalSince(lastScan) > RESCAN {
            lastScan = Date()
            if let path = newestTranscript(), path != tailer?.path {
                tailer = Tailer(path: path)
                emit("\n── session \(tailer!.session) ──\n", ACCENT, 10, bold: true)
            }
        }
        guard let tailer else { return }
        for block in tailer.drain() {
            let stamp = block.ts.count > 19
                ? String(block.ts[block.ts.index(block.ts.startIndex, offsetBy: 11)..<block.ts.index(block.ts.startIndex, offsetBy: 19)])
                : block.ts
            emit("\(stamp)\n", DIM, 9)
            if block.sealed {
                emit("⟨sealed — signature only⟩\n\n", SEALED, 10, italic: true)
            } else {
                emit(block.text + "\n\n", FG, 11.5)
            }
        }
    }
}

// MARK: - Entry point

if CommandLine.arguments.contains("--selftest") {
    guard let path = newestTranscript() else {
        FileHandle.standardError.write("no transcripts under \(PROJECTS)\n".data(using: .utf8)!)
        exit(1)
    }
    print("active: \(path)")
    for b in Tailer(path: path, backfill: 5).drain() {
        print("  [\(b.ts)] \(b.sealed ? "<sealed>" : String(b.text.prefix(110)))")
    }
    exit(0)
}

killOtherInstances()

let app = NSApplication.shared
let hud = HUD()
app.delegate = hud
app.setActivationPolicy(.accessory)
app.run()
