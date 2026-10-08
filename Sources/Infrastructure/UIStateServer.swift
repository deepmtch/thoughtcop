// Local-only HTTP API mirroring the AppKit window's state, so automated tests
// can inspect and drive the real window instead of relying on screenshots or OCR.

import Foundation
import Network

let UI_API_TOKEN_PATH = ProcessInfo.processInfo.environment["THOUGHTCOP_UI_API_TOKEN_PATH"]
    ?? ("~/Library/Application Support/ThoughtCop/ui-api-token" as NSString)
        .expandingTildeInPath

/// Keep browser pages and unrelated local processes from reading transcripts or
/// driving the app. Tests may inject a token; normal launches persist a random
/// capability in a user-only file so command-line automation can authenticate.
func loadUIAPIToken(path: String = UI_API_TOKEN_PATH,
                    environmentToken: String? = ProcessInfo.processInfo.environment[
                        "THOUGHTCOP_UI_API_TOKEN"]) -> String {
    if let injected = environmentToken,
       !injected.isEmpty {
        return injected
    }
    if let existing = try? String(contentsOfFile: path, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
       existing.count >= 32 {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: path)
        return existing
    }
    let token = UUID().uuidString.replacingOccurrences(of: "-", with: "") +
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                           ofItemAtPath: url.deletingLastPathComponent().path)
    do {
        try Data((token + "\n").utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: path)
    } catch {
        // A non-persisted random token fails closed: the UI keeps working, while
        // no external client can authenticate to the inspection endpoint.
    }
    return token
}

struct UIAPIRequest {
    let method: String
    let path: String
    let authorization: String?
}

func parseUIAPIRequest(_ text: String) -> UIAPIRequest? {
    let lines = text.components(separatedBy: "\r\n")
    let requestParts = lines.first?.split(separator: " ", maxSplits: 2) ?? []
    guard requestParts.count >= 2 else { return nil }
    var authorization: String?
    for line in lines.dropFirst() {
        let parts = line.split(separator: ":", maxSplits: 1,
                               omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "authorization" else { continue }
        authorization = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return UIAPIRequest(method: String(requestParts[0]).uppercased(),
                        path: String(requestParts[1]),
                        authorization: authorization)
}

func isAuthorizedUIAPIRequest(_ request: UIAPIRequest, token: String) -> Bool {
    request.authorization == "Bearer \(token)"
}

enum UICommandOrigin: String {
    case appKit
    case http
}

enum UICommand {
    case first
    case previous
    case next
    case latest
    case showHistory
    case showViolations
    case historyFilter(String)
    case restartTicker
    case showMessage
    case showHUD
    case hideHUD
    case close
    case quit
    case editCheckRules
    case closeCheckRules
    case saveCheckRules(text: String, mode: String)
    case editProviderCredentials
    case closeProviderCredentials
    case applyProviderCredentialEdits([CheckerProvider: CheckerCredentialEdit],
                                      completion: ([String]) -> Void)
    case selectSession(path: String?)
    case corner(String)
    case speed(String)
    case width(CGFloat)
    case position(String)
    case chooseBackground
    case backgroundRGBA([Double]?)
    case violationFlash(Bool)
    case violationBubble(Bool)
    case violationVerification(Bool)
    case violationHistoryLimit(Int)
    case toggleSelectedViolation
    case showUsage
    case readerTab(Int)
    case readerLatest
    case closeUsage
    case showLastViolation
    case statusItemHover(Bool)
    case expandViolationDetails
    case showSettings(String)
    case closeSettings
    case openViolationBubble

    var name: String {
        switch self {
        case .first: return "first"
        case .previous: return "previous"
        case .next: return "next"
        case .latest: return "latest"
        case .showHistory: return "show-history"
        case .showViolations: return "show-violations"
        case .historyFilter(let value): return "filter/\(value)"
        case .restartTicker: return "restart-ticker"
        case .showMessage: return "message"
        case .showHUD: return "show"
        case .hideHUD: return "hide"
        case .close: return "close"
        case .quit: return "quit"
        case .editCheckRules: return "check-rules"
        case .closeCheckRules: return "check-rules/close"
        case .saveCheckRules: return "save-check-rules"
        case .editProviderCredentials: return "provider-credentials"
        case .closeProviderCredentials: return "provider-credentials/close"
        case .applyProviderCredentialEdits: return "save-provider-credentials"
        case .selectSession: return "select-session"
        case .corner(let value): return "corner/\(value)"
        case .speed(let value): return "speed/\(value)"
        case .width(let value): return "width/\(Int(value))"
        case .position(let value): return "position/\(value)"
        case .chooseBackground: return "choose-background"
        case .backgroundRGBA(let values): return values == nil
            ? "background/system" : "background/rgba"
        case .violationFlash(let enabled): return enabled
            ? "violation-flash/on" : "violation-flash/off"
        case .violationBubble(let enabled): return enabled
            ? "violation-bubble/on" : "violation-bubble/off"
        case .violationVerification(let enabled): return enabled
            ? "violation-verification/on" : "violation-verification/off"
        case .violationHistoryLimit(let limit): return "violation-history/\(limit)"
        case .toggleSelectedViolation: return "toggle-selected-violation"
        case .showUsage: return "usage"
        case .readerTab(let index): return "reader-tab/\(index)"
        case .readerLatest: return "reader-latest"
        case .closeUsage: return "usage/close"
        case .showLastViolation: return "last-violation"
        case .expandViolationDetails: return "reader/violation-details"
        case .statusItemHover(let inside): return inside
            ? "status-item/hover/on" : "status-item/hover/off"
        case .showSettings(let tab): return "settings/\(tab)"
        case .closeSettings: return "settings/close"
        case .openViolationBubble: return "violation-bubble/open"
        }
    }
}

final class UIStateServer {
    private let lock = NSLock()
    private var body = Data("{\"schemaVersion\":1,\"ready\":false}".utf8)
    private var listener: NWListener?
    private let listenerQueue = DispatchQueue(label: "thoughtcop.ui-api")
    private let token: String
    /// Renders "window" (the visible ThoughtCop window) or "bubble" as PNG.
    var captureHandler: ((String) -> Data?)?
    var actionHandler: ((UICommand) -> Void)?
    private let logURL: URL

    init(logURL: URL? = nil, token: String? = nil) {
        self.token = token ?? loadUIAPIToken()
        self.logURL = logURL ?? ProcessInfo.processInfo.environment["THOUGHTCOP_UI_API_LOG"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/ThoughtCop/ui-api.jsonl")
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
        startListening(retriesRemaining: 25)
    }

    private func startListening(retriesRemaining: Int) {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: API_PORT) else {
            log(event: "api_invalid_port", fields: ["port": Int(API_PORT)])
            retryListening(retriesRemaining: retriesRemaining)
            return
        }
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                         port: port)
            listener = try NWListener(using: parameters)
        } catch {
            log(event: "api_create_failed", fields: [
                "port": Int(API_PORT),
                "error": String(describing: error),
            ])
            retryListening(retriesRemaining: retriesRemaining)
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            switch state {
            case .ready:
                self.log(event: "api_started", fields: ["port": Int(API_PORT)])
            case .waiting(let error):
                self.log(event: "api_waiting", fields: [
                    "port": Int(API_PORT),
                    "error": String(describing: error),
                ])
            case .failed(let error):
                self.log(event: "api_failed", fields: [
                    "port": Int(API_PORT),
                    "error": String(describing: error),
                ])
                listener.cancel()
                if self.listener === listener { self.listener = nil }
                self.retryListening(retriesRemaining: retriesRemaining)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: DispatchQueue.global(qos: .utility))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
                [weak self] request, _, _, _ in
                guard let self else { connection.cancel(); return }
                guard let requestText = request.flatMap({ String(data: $0, encoding: .utf8) }),
                      let parsed = parseUIAPIRequest(requestText) else {
                    self.send(connection, status: 400,
                              payload: Data("{\"error\":\"bad request\"}".utf8),
                              type: "application/json")
                    return
                }
                guard isAuthorizedUIAPIRequest(parsed, token: self.token) else {
                    self.send(connection, status: 401,
                              payload: Data("{\"error\":\"unauthorized\"}".utf8),
                              type: "application/json",
                              extraHeaders: ["WWW-Authenticate": "Bearer"])
                    return
                }
                if parsed.path == "/screenshot" || parsed.path == "/screenshot/bubble" {
                    guard parsed.method == "GET" else {
                        self.sendMethodNotAllowed(connection, allow: "GET")
                        return
                    }
                    let target = parsed.path == "/screenshot" ? "window"
                        : String(parsed.path.dropFirst("/screenshot/".count))
                    DispatchQueue.main.async {
                        let image = self.captureHandler?(target) ?? Data()
                        self.send(connection, payload: image, type: "image/png")
                    }
                    return
                }
                if parsed.path == "/ui" {
                    guard parsed.method == "GET" else {
                        self.sendMethodNotAllowed(connection, allow: "GET")
                        return
                    }
                    self.lock.lock(); let payload = self.body; self.lock.unlock()
                    self.send(connection, payload: payload, type: "application/json")
                    return
                }
                if let command = self.command(for: parsed.path) {
                    guard parsed.method == "POST" else {
                        self.sendMethodNotAllowed(connection, allow: "POST")
                        return
                    }
                    DispatchQueue.main.async {
                        self.perform(command, origin: .http)
                        let payload = Data("{\"ok\":true,\"action\":\"\(command.name)\"}".utf8)
                        self.send(connection, payload: payload, type: "application/json")
                    }
                    return
                }
                self.send(connection, status: 404,
                          payload: Data("{\"error\":\"not found\"}".utf8),
                          type: "application/json")
            }
        }
        listener.start(queue: listenerQueue)
    }

    private func retryListening(retriesRemaining: Int) {
        guard retriesRemaining > 0 else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            [weak self] in
            self?.startListening(retriesRemaining: retriesRemaining - 1)
        }
    }

    private func command(for path: String) -> UICommand? {
        let tabPrefix = "/reader-tab/"
        if path.hasPrefix(tabPrefix), let index = Int(path.dropFirst(tabPrefix.count)),
           (0...4).contains(index) {
            return .readerTab(index)
        }
        if path == "/reader-latest" { return .readerLatest }
        if path == "/settings" { return .showSettings("general") }
        if path == "/settings/close" { return .closeSettings }
        let settingsPrefix = "/settings/"
        if path.hasPrefix(settingsPrefix),
           let tab = SettingsTab(rawValue: String(path.dropFirst(settingsPrefix.count))) {
            return .showSettings(tab.rawValue)
        }
        let historyPrefix = "/violation-history/"
        if path.hasPrefix(historyPrefix),
           let limit = Int(path.dropFirst(historyPrefix.count)),
           ViolationHistoryPreference.choices.contains(limit) {
            return .violationHistoryLimit(limit)
        }
        switch path {
        case "/first": return .first
        case "/previous": return .previous
        case "/next": return .next
        case "/latest": return .latest
        case "/toggle-expanded": return .showHistory
        case "/violations": return .showViolations
        case "/filter/all": return .historyFilter("all")
        case "/filter/violations": return .historyFilter("violations")
        case "/filter/archive": return .historyFilter("archive")
        case "/last-violation": return .showLastViolation
        case "/reader/violation-details": return .expandViolationDetails
        case "/status-item/hover/on": return .statusItemHover(true)
        case "/status-item/hover/off": return .statusItemHover(false)
        case "/violation-bubble/open": return .openViolationBubble
        case "/restart-ticker": return .restartTicker
        case "/message": return .showMessage
        case "/show": return .showHUD
        case "/close": return .close
        case "/hide": return .hideHUD
        case "/quit": return .quit
        case "/check-rules": return .editCheckRules
        case "/check-rules/close": return .closeCheckRules
        case "/provider-credentials": return .editProviderCredentials
        case "/provider-credentials/close": return .closeProviderCredentials
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
        case "/violation-flash/on": return .violationFlash(true)
        case "/violation-flash/off": return .violationFlash(false)
        case "/violation-bubble/on": return .violationBubble(true)
        case "/violation-bubble/off": return .violationBubble(false)
        case "/toggle-selected-violation": return .toggleSelectedViolation
        case "/usage": return .showUsage
        case "/usage/close": return .closeUsage
        case "/violation-verification/on": return .violationVerification(true)
        case "/violation-verification/off": return .violationVerification(false)
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

    private func sendMethodNotAllowed(_ connection: NWConnection, allow: String) {
        send(connection, status: 405,
             payload: Data("{\"error\":\"method not allowed\"}".utf8),
             type: "application/json", extraHeaders: ["Allow": allow])
    }

    private func send(_ connection: NWConnection, status: Int = 200,
                      payload: Data, type: String,
                      extraHeaders: [String: String] = [:]) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        default: reason = "Error"
        }
        var header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\n" +
            "Content-Length: \(payload.count)\r\nCache-Control: no-store\r\n" +
            "X-Content-Type-Options: nosniff\r\nConnection: close\r\n"
        for (name, value) in extraHeaders.sorted(by: { $0.key < $1.key }) {
            header += "\(name): \(value)\r\n"
        }
        header += "\r\n"
        var response = Data(header.utf8); response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
