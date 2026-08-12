// Presentation policy for transcript progress records versus useful content.

struct OperationPresentationState {
    private(set) var pendingSources = Set<String>()
    private(set) var latestPendingSource: String?
    private(set) var lastUsefulTitle = "Thinkpeek"

    var operationPending: Bool { !pendingSources.isEmpty }
    var windowTitle: String {
        guard let source = latestPendingSource, pendingSources.contains(source) else {
            return lastUsefulTitle
        }
        return "● \(source) · working…"
    }

    mutating func operationStarted(source: String) {
        pendingSources.insert(source)
        latestPendingSource = source
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
