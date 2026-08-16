// Presentation policy for transcript progress records versus useful content.

struct OperationPresentationState {
    private(set) var pendingSources = Set<String>()
    private(set) var latestPendingSource: String?
    private(set) var lastUsefulTitle = "Thinkpeek"

    var operationPending: Bool { !pendingSources.isEmpty }
    var activeSources: [String] { pendingSources.sorted() }
    var windowTitle: String {
        guard !pendingSources.isEmpty else {
            return lastUsefulTitle
        }
        let providers = Set(pendingSources.map {
            $0.split(separator: "·", maxSplits: 1).first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? $0
        }).sorted()
        if providers.count > 1 {
            return "● \(providers.joined(separator: " + ")) · working…"
        }
        guard let source = latestPendingSource, pendingSources.contains(source) else {
            return "● AI provider · working…"
        }
        return "● \(source) · working…"
    }

    mutating func operationStarted(source: String) {
        pendingSources.insert(source)
        latestPendingSource = source
    }

    mutating func operationUpdated(source: String) {
        pendingSources.insert(source)
        latestPendingSource = source
    }

    mutating func operationFinished(source: String) {
        pendingSources.remove(source)
        if latestPendingSource == source {
            latestPendingSource = pendingSources.sorted().first
        }
    }

    mutating func readableContentArrived(source: String) {
        pendingSources.remove(source)
        if latestPendingSource == source {
            latestPendingSource = pendingSources.sorted().first
        }
        lastUsefulTitle = source
    }

    mutating func resetPending() {
        pendingSources.removeAll()
        latestPendingSource = nil
    }
}
