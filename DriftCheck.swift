// Scoring reasoning text against user-defined triggers via a direct Groq/Cerebras call.

import Foundation

/// A trigger that fired, as judged by the checker model.
struct Fired {
    let trigger: String
    let why: String
}

enum DriftOutcome {
    case scored([Fired], String)
    case failed(String)
}

struct DriftBackend {
    let name: String
    let url: URL
    let key: String
    let model: String
    var label: String { "\(name) · \(model)" }
}

/// One plain-English rule per line; `#` comments. Re-read per check, so edits are live.
func loadTriggers() -> [String] {
    guard let text = try? String(contentsOfFile: TRIGGERS_FILE, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

/// Direct providers only. Groq is attempted first; Cerebras is the fallback.
/// Credentials remain in memory and are never rendered or logged.
func driftBackends() -> [DriftBackend] {
    guard !LOCAL_ONLY else { return [] }
    var result: [DriftBackend] = []
    if let key = dotenv("GROQ_API_KEY"),
       let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") {
        result.append(DriftBackend(
            name: "Groq", url: url, key: key,
            model: dotenv("GROQ_MODEL") ?? "llama-3.3-70b-versatile"))
    }
    if let key = dotenv("CEREBRAS_API_KEY"),
       let url = URL(string: "https://api.cerebras.ai/v1/chat/completions") {
        result.append(DriftBackend(
            name: "Cerebras", url: url, key: key,
            model: dotenv("CEREBRAS_MODEL") ?? "gpt-oss-120b"))
    }
    return result
}

func checkLabel() -> String {
    driftBackends().map(\.label).joined(separator: " → fallback: ")
}

/// Score one reasoning block against the triggers. Async — never blocks the UI.
/// Groq direct is primary; a request failure falls back to Cerebras direct.
func checkDrift(_ reasoning: String, done: @escaping (DriftOutcome, Double) -> Void) {
    let triggers = loadTriggers()
    guard !triggers.isEmpty else {
        done(.failed("no triggers configured"), 0)
        return
    }
    let backends = driftBackends()
    guard !backends.isEmpty else {
        done(.failed(LOCAL_ONLY ? "local-only mode" : "no Groq or Cerebras key in .env"), 0)
        return
    }
    let numbered = triggers.enumerated().map { "\($0.offset + 1). \($0.element)" }
        .joined(separator: "\n")

    let started = Date()
    var failures: [String] = []

    func attempt(_ index: Int) {
        guard index < backends.count else {
            let ms = Date().timeIntervalSince(started) * 1000
            DispatchQueue.main.async { done(.failed(failures.joined(separator: "; ")), ms) }
            return
        }
        let backend = backends[index]
        let payload: [String: Any] = [
            "model": backend.model,
            "temperature": 0,
            "max_tokens": 250,
            "messages": [
                ["role": "system", "content": makeCheckSystemPrompt(
                    instructions: CheckPromptPreference.load())],
                ["role": "user", "content": "TRIGGERS:\n\(numbered)\n\nREASONING:\n"
                    + String(reasoning.prefix(6000))],
            ],
        ]
        var request = URLRequest(url: backend.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Bearer " + backend.key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            func fail(_ message: String) {
                failures.append("\(backend.name): \(message)")
                attempt(index + 1)
            }
            if let error { fail(error.localizedDescription); return }
            guard let http = response as? HTTPURLResponse else { fail("no HTTP response"); return }
            guard (200..<300).contains(http.statusCode) else {
                fail("HTTP \(http.statusCode)"); return
            }
            guard let data,
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  var text = message["content"] as? String else {
                fail("invalid response"); return
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}") {
                text = String(text[open...close])
            }
            guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
                  let fired = object["fired"] as? [[String: Any]] else {
                fail("checker returned invalid JSON"); return
            }
            let hits: [Fired] = fired.compactMap {
                guard let n = $0["n"] as? Int, n >= 1, n <= triggers.count else { return nil }
                return Fired(trigger: triggers[n - 1], why: $0["why"] as? String ?? "")
            }
            let ms = Date().timeIntervalSince(started) * 1000
            DispatchQueue.main.async { done(.scored(hits, backend.label), ms) }
        }.resume()
    }
    attempt(0)
}

/// Why the drift check is or is not running, in words fit for the status bar.
func driftStatus() -> (ready: Bool, detail: String) {
    let triggers = loadTriggers()
    if triggers.isEmpty { return (false, "no triggers in \((TRIGGERS_FILE as NSString).lastPathComponent)") }
    if LOCAL_ONLY { return (false, "local-only mode") }
    if driftBackends().isEmpty { return (false, "GROQ_API_KEY and CEREBRAS_API_KEY missing from .env") }
    return (true, "\(triggers.count) triggers → \(checkLabel())")
}
