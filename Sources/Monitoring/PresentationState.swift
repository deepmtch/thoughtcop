// Presentation policy for transcript progress records versus useful content.

struct OperationPresentationState {
    private(set) var pendingSources = Set<String>()
    private(set) var waitingSourceSet = Set<String>()
    private(set) var latestPendingSource: String?
    private(set) var latestWaitingSource: String?
    private(set) var lastUsefulTitle = "Thinkpeek"

    var operationPending: Bool { !pendingSources.isEmpty }
    var operationWaiting: Bool { !waitingSourceSet.isEmpty }
    var activeSources: [String] { pendingSources.sorted() }
    var waitingSources: [String] { waitingSourceSet.sorted() }
    var latestActivitySource: String? {
        latestPendingSource ?? latestWaitingSource
    }
    var windowTitle: String {
        if !pendingSources.isEmpty {
            return activityTitle(sources: pendingSources,
                                 latestSource: latestPendingSource,
                                 marker: "●", suffix: "working…")
        }
        if !waitingSourceSet.isEmpty {
            return activityTitle(sources: waitingSourceSet,
                                 latestSource: latestWaitingSource,
                                 marker: "◐", suffix: "waiting for you")
        }
        return lastUsefulTitle
    }

    private func activityTitle(sources: Set<String>, latestSource: String?,
                               marker: String, suffix: String) -> String {
        let providers = Set(sources.map {
            $0.split(separator: "·", maxSplits: 1).first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? $0
        }).sorted()
        if providers.count > 1 {
            return "\(marker) \(providers.joined(separator: " + ")) · \(suffix)"
        }
        guard let source = latestSource, sources.contains(source) else {
            return "\(marker) AI provider · \(suffix)"
        }
        return "\(marker) \(source) · \(suffix)"
    }

    mutating func operationStarted(source: String) {
        waitingSourceSet.remove(source)
        if latestWaitingSource == source {
            latestWaitingSource = waitingSourceSet.sorted().first
        }
        pendingSources.insert(source)
        latestPendingSource = source
    }

    mutating func operationUpdated(source: String) {
        // Claude emits trailing stream frames after AskUserQuestion. They are
        // part of the same turn and must not turn "waiting" back into work.
        guard !waitingSourceSet.contains(source) else { return }
        pendingSources.insert(source)
        latestPendingSource = source
    }

    mutating func operationWaitingForUser(source: String) {
        pendingSources.remove(source)
        if latestPendingSource == source {
            latestPendingSource = pendingSources.sorted().first
        }
        waitingSourceSet.insert(source)
        latestWaitingSource = source
    }

    mutating func operationFinished(source: String) {
        pendingSources.remove(source)
        waitingSourceSet.remove(source)
        if latestPendingSource == source {
            latestPendingSource = pendingSources.sorted().first
        }
        if latestWaitingSource == source {
            latestWaitingSource = waitingSourceSet.sorted().first
        }
    }

    mutating func readableContentArrived(source: String) {
        pendingSources.remove(source)
        waitingSourceSet.remove(source)
        if latestPendingSource == source {
            latestPendingSource = pendingSources.sorted().first
        }
        if latestWaitingSource == source {
            latestWaitingSource = waitingSourceSet.sorted().first
        }
        lastUsefulTitle = source
    }

    mutating func resetPending() {
        pendingSources.removeAll()
        waitingSourceSet.removeAll()
        latestPendingSource = nil
        latestWaitingSource = nil
    }
}
