// Local-only HTTP API mirroring the AppKit window's state, so automated tests
// can inspect and drive the real window instead of relying on screenshots or OCR.

import Foundation
import Network

final class UIStateServer {
    private let lock = NSLock()
    private var body = Data("{\"schemaVersion\":1,\"ready\":false}".utf8)
    private var listener: NWListener?
    var captureHandler: (() -> Data?)?
    var actionHandler: ((String) -> Void)?

    func publish(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.sortedKeys]) else { return }
        lock.lock(); body = data; lock.unlock()
    }

    func start() {
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
                let actions = ["/previous": "previous", "/next": "next",
                               "/toggle-expanded": "toggle-expanded",
                               "/restart-ticker": "restart-ticker",
                               "/message": "message", "/controls": "controls",
                               "/speed/slow": "speed/slow",
                               "/speed/normal": "speed/normal",
                               "/speed/fast": "speed/fast",
                               "/width/narrow": "width/narrow",
                               "/width/standard": "width/standard",
                               "/background/blue": "background/blue",
                               "/background/system": "background/system",
                               "/reveal": "reveal", "/hide": "hide",
                               "/position/top-left": "position/top-left",
                               "/position/top-center": "position/top-center",
                               "/position/top-right": "position/top-right",
                               "/position/bottom-left": "position/bottom-left",
                               "/position/bottom-center": "position/bottom-center",
                               "/position/bottom-right": "position/bottom-right"]
                if let action = actions[path] {
                    DispatchQueue.main.async {
                        self.actionHandler?(action)
                        let payload = Data("{\"ok\":true,\"action\":\"\(action)\"}".utf8)
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

    private func send(_ connection: NWConnection, payload: Data, type: String) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\n" +
            "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8); response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
