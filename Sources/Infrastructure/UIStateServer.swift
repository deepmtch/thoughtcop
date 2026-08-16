// Local-only HTTP API mirroring the AppKit window's state, so automated tests
// can inspect and drive the real window instead of relying on screenshots or OCR.

import Foundation
import Network

enum UICommandOrigin: String {
    case appKit
    case http
}

enum UICommand {
    case previous
    case next
    case latest
    case showHistory
    case restartTicker
    case showMessage
    case showControls
    case close
    case quit
    case editCheckRules
    case saveCheckRules(text: String, mode: String)
    case selectSession(path: String?)
    case corner(String)
    case speed(String)
    case width(CGFloat)
    case position(String)
    case chooseBackground
    case backgroundRGBA([Double]?)

    var name: String {
        switch self {
        case .previous: return "previous"
        case .next: return "next"
        case .latest: return "latest"
        case .showHistory: return "show-history"
        case .restartTicker: return "restart-ticker"
        case .showMessage: return "message"
        case .showControls: return "controls"
        case .close: return "close"
        case .quit: return "quit"
        case .editCheckRules: return "check-rules"
        case .saveCheckRules: return "save-check-rules"
        case .selectSession: return "select-session"
        case .corner(let value): return "corner/\(value)"
        case .speed(let value): return "speed/\(value)"
        case .width(let value): return "width/\(Int(value))"
        case .position(let value): return "position/\(value)"
        case .chooseBackground: return "choose-background"
        case .backgroundRGBA(let values): return values == nil
            ? "background/system" : "background/rgba"
        }
    }
}

final class UIStateServer {
    private let lock = NSLock()
    private var body = Data("{\"schemaVersion\":1,\"ready\":false}".utf8)
    private var listener: NWListener?
    var captureHandler: (() -> Data?)?
    var actionHandler: ((UICommand) -> Void)?
    private let logURL: URL

    init(logURL: URL? = nil) {
        self.logURL = logURL ?? ProcessInfo.processInfo.environment["THINKPEEK_UI_API_LOG"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Thinkpeek/ui-api.jsonl")
    }

    func publish(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.sortedKeys]) else { return }
        lock.lock(); body = data; lock.unlock()
    }

    func perform(_ command: UICommand, origin: UICommandOrigin) {
        log(event: "command", fields: ["command": command.name,
                                        "origin": origin.rawValue])
        actionHandler?(command)
    }

    func start() {
        resetLog()
        log(event: "api_started", fields: ["port": Int(API_PORT)])
        guard let port = NWEndpoint.Port(rawValue: API_PORT),
              let listener = try? NWListener(using: .tcp, on: port) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: DispatchQueue.global(qos: .utility))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
                [weak self] request, _, _, _ in
                guard let self else { connection.cancel(); return }
                let wantsImage = request.flatMap { String(data: $0, encoding: .utf8) }?
                    .hasPrefix("GET /screenshot ") == true
                if wantsImage {
                    DispatchQueue.main.async {
                        let image = self.captureHandler?() ?? Data()
                        self.send(connection, payload: image, type: "image/png")
                    }
                    return
                }
                let requestLine = request.flatMap { String(data: $0, encoding: .utf8) }?
                    .components(separatedBy: "\r\n").first ?? ""
                let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                if let command = self.command(for: path) {
                    DispatchQueue.main.async {
                        self.perform(command, origin: .http)
                        let payload = Data("{\"ok\":true,\"action\":\"\(command.name)\"}".utf8)
                        self.send(connection, payload: payload, type: "application/json")
                    }
                    return
                }
                self.lock.lock(); let payload = self.body; self.lock.unlock()
                self.send(connection, payload: payload, type: "application/json")
            }
        }
        listener.start(queue: DispatchQueue(label: "thinkpeek.ui-api"))
    }

    private func command(for path: String) -> UICommand? {
        switch path {
        case "/previous": return .previous
        case "/next": return .next
        case "/latest": return .latest
        case "/toggle-expanded": return .showHistory
        case "/restart-ticker": return .restartTicker
        case "/message": return .showMessage
        case "/controls", "/reveal": return .showControls
        case "/close", "/hide": return .close
        case "/quit": return .quit
        case "/check-rules": return .editCheckRules
        case "/corner/top-left": return .corner("top-left")
        case "/corner/top-right": return .corner("top-right")
        case "/corner/bottom-left": return .corner("bottom-left")
        case "/corner/bottom-right": return .corner("bottom-right")
        case "/speed/slow": return .speed("slow")
        case "/speed/normal": return .speed("normal")
        case "/speed/fast": return .speed("fast")
        case "/width/narrow": return .width(CompactWindowSizing.narrowWidth)
        case "/width/standard": return .width(CompactWindowSizing.standardWidth)
        case "/background/blue": return .backgroundRGBA([0.16, 0.38, 0.68, 1])
        case "/background/system": return .backgroundRGBA(nil)
        case "/position/top-left": return .position("top-left")
        case "/position/top-center": return .position("top-center")
        case "/position/top-right": return .position("top-right")
        case "/position/bottom-left": return .position("bottom-left")
        case "/position/bottom-center": return .position("bottom-center")
        case "/position/bottom-right": return .position("bottom-right")
        default: return nil
        }
    }

    private func log(event: String, fields: [String: Any]) {
        var object = fields
        object["event"] = event
        object["timestamp"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.sortedKeys]) else { return }
        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory,
                                                  withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil,
                                           attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data([0x0a]))
    }

    private func resetLog() {
        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory,
                                                  withIntermediateDirectories: true)
        try? Data().write(to: logURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: logURL.path)
    }

    private func send(_ connection: NWConnection, payload: Data, type: String) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\n" +
            "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8); response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
