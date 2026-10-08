// Checker usage and cost: provider-reported tokens times provider-published
// prices. Nothing here is estimated; a missing price is shown as missing.

import Foundation

let USAGE_PATH = ProcessInfo.processInfo.environment["DOUBLETHINK_USAGE_PATH"]
    // An isolated test never writes the user's real usage and cost.
    ?? (ISOLATED_E2E
        ? NSTemporaryDirectory() + "doublethink-e2e-usage-\(getpid()).json"
        : ("~/Library/Application Support/Doublethink/usage.json" as NSString)
            .expandingTildeInPath)

/// Tokens reported in one chat-completions response (`usage`).
struct TokenUsage: Equatable {
    let input: Int
    let output: Int

    init(input: Int, output: Int) {
        self.input = input
        self.output = output
    }

    /// From an OpenAI-compatible response root; nil when the provider sent none.
    init?(response root: [String: Any]) {
        guard let usage = root["usage"] as? [String: Any],
              let input = usage["prompt_tokens"] as? Int,
              let output = usage["completion_tokens"] as? Int else { return nil }
        self.init(input: input, output: output)
    }
}

/// US dollars per token, as published by the provider's model endpoint.
struct ModelPrice: Codable, Equatable {
    let input: Double
    let output: Double

    /// Groq's `GET /openai/v1/models/{id}` returns `pricing.prompt` and
    /// `pricing.completion` as per-token decimal strings.
    init?(modelResponse root: [String: Any]) {
        guard let pricing = root["pricing"] as? [String: Any],
              let input = (pricing["prompt"] as? String).flatMap(Double.init),
              let output = (pricing["completion"] as? String).flatMap(Double.init)
        else { return nil }
        self.input = input
        self.output = output
    }

    init(input: Double, output: Double) {
        self.input = input
        self.output = output
    }

    func cost(_ usage: UsageTotals) -> Double {
        Double(usage.inputTokens) * input + Double(usage.outputTokens) * output
    }
}

struct UsageTotals: Codable, Equatable {
    var checks = 0
    var secondChecks = 0
    var inputTokens = 0
    var outputTokens = 0

    static func + (lhs: UsageTotals, rhs: UsageTotals) -> UsageTotals {
        UsageTotals(checks: lhs.checks + rhs.checks,
                    secondChecks: lhs.secondChecks + rhs.secondChecks,
                    inputTokens: lhs.inputTokens + rhs.inputTokens,
                    outputTokens: lhs.outputTokens + rhs.outputTokens)
    }
}

/// A period's usage with its cost where every model in it has a price.
struct UsageSummary: Equatable {
    let totals: UsageTotals
    /// nil when at least one model used in the period has no published price.
    let costUSD: Double?
    let models: [String]
}

func formattedCost(_ cost: Double?) -> String {
    guard let cost else { return "price not published" }
    return cost < 0.01 && cost > 0 ? String(format: "$%.4f", cost)
                                   : String(format: "$%.2f", cost)
}

/// Per-day, per-model totals in a user-only JSON file. Days older than the
/// current and previous calendar month are dropped.
final class UsageStore {
    static let shared = UsageStore(path: USAGE_PATH)

    let path: String
    private let lock = NSLock()
    /// day ("yyyy-MM-dd") → model label → totals
    private var days: [String: [String: UsageTotals]] = [:]
    private var prices: [String: ModelPrice] = [:]
    private var loaded = false

    init(path: String) { self.path = path }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// `counted: false` adds only the tokens (the one-line violation summary
    /// is neither a check nor a second check).
    func record(model: String, usage: TokenUsage, secondCheck: Bool,
                counted: Bool = true, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        loadLocked()
        let key = Self.day(date)
        var totals = days[key, default: [:]][model, default: UsageTotals()]
        totals.checks += counted && !secondCheck ? 1 : 0
        totals.secondChecks += counted && secondCheck ? 1 : 0
        totals.inputTokens += usage.input
        totals.outputTokens += usage.output
        days[key, default: [:]][model] = totals
        // Keep the current and previous calendar month, relative to now, not
        // to the record's date (a back-dated record must not drop this month).
        pruneLocked(now: Date())
        saveLocked()
    }

    func setPrice(_ price: ModelPrice, for model: String) {
        lock.lock()
        prices[model] = price
        lock.unlock()
    }

    func price(for model: String) -> ModelPrice? {
        lock.lock()
        defer { lock.unlock() }
        return prices[model]
    }

    func summary(today date: Date = Date()) -> (today: UsageSummary, month: UsageSummary) {
        lock.lock()
        defer { lock.unlock() }
        loadLocked()
        let today = Self.day(date)
        let monthPrefix = String(today.prefix(7))
        return (summaryLocked(days.filter { $0.key == today }),
                summaryLocked(days.filter { $0.key.hasPrefix(monthPrefix) }))
    }

    private func summaryLocked(_ selected: [String: [String: UsageTotals]]) -> UsageSummary {
        var byModel: [String: UsageTotals] = [:]
        for models in selected.values {
            for (model, totals) in models { byModel[model] = byModel[model, default: UsageTotals()] + totals }
        }
        let totals = byModel.values.reduce(UsageTotals(), +)
        var cost: Double? = 0
        for (model, modelTotals) in byModel {
            guard let price = prices[model] else { cost = nil; break }
            cost = (cost ?? 0) + price.cost(modelTotals)
        }
        return UsageSummary(totals: totals, costUSD: byModel.isEmpty ? 0 : cost,
                            models: byModel.keys.sorted())
    }

    private func pruneLocked(now: Date) {
        let calendar = Calendar(identifier: .gregorian)
        guard let previous = calendar.date(byAdding: .month, value: -1, to: now) else { return }
        let keep = [String(Self.day(now).prefix(7)), String(Self.day(previous).prefix(7))]
        days = days.filter { day, _ in keep.contains { day.hasPrefix($0) } }
    }

    private func loadLocked() {
        guard !loaded else { return }
        loaded = true
        guard let data = FileManager.default.contents(atPath: path),
              let decoded = try? JSONDecoder().decode(
                [String: [String: UsageTotals]].self, from: data) else { return }
        days = decoded
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(days) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}

/// Fetches the published per-token price for a backend's model once per launch.
func fetchModelPrice(for backend: DriftBackend, completion: @escaping () -> Void = {}) {
    guard UsageStore.shared.price(for: backend.label) == nil,
          var components = URLComponents(url: backend.url, resolvingAgainstBaseURL: false)
    else { completion(); return }
    // .../v1/chat/completions → .../v1/models/{model}
    components.path = components.path.replacingOccurrences(
        of: "/chat/completions", with: "/models/" + backend.model)
    guard let url = components.url else { completion(); return }
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("Bearer " + backend.key, forHTTPHeaderField: "Authorization")
    URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data,
           let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let price = ModelPrice(modelResponse: root) {
            UsageStore.shared.setPrice(price, for: backend.label)
        }
        DispatchQueue.main.async(execute: completion)
    }.resume()
}
