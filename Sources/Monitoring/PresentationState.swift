// Presentation policy for transcript progress records versus useful content.

struct OperationPresentationState {
    private var pendingByIdentity: [String: String] = [:]
    private var waitingByIdentity: [String: String] = [:]
    private var latestPendingIdentity: String?
    private var latestWaitingIdentity: String?
    private(set) var lastUsefulTitle = "Thinkpeek"

    var operationPending: Bool { !pendingByIdentity.isEmpty }
    var operationWaiting: Bool { !waitingByIdentity.isEmpty }
    var activeSources: [String] { pendingByIdentity.values.sorted() }
    var waitingSources: [String] { waitingByIdentity.values.sorted() }
    var latestPendingSource: String? {
        latestPendingIdentity.flatMap { pendingByIdentity[$0] }
    }
    var latestWaitingSource: String? {
        latestWaitingIdentity.flatMap { waitingByIdentity[$0] }
    }
    var latestActivitySource: String? {
        latestPendingSource ?? latestWaitingSource
    }
    var activityDisplaySource: String? {
        let sources = activeSources + waitingSources
        guard !sources.isEmpty else { return nil }
        if sources.count == 1 { return sources[0] }
        let providers = Set(sources.map {
            $0.split(separator: "·", maxSplits: 1).first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? $0
        }).sorted()
        return "\(providers.joined(separator: " + ")) · \(sources.count) active"
    }
    var activityDisplayText: String? {
        let sourceCount = pendingByIdentity.count + waitingByIdentity.count
        guard sourceCount > 0 else { return nil }
        if sourceCount == 1 {
            return pendingByIdentity.isEmpty ? "Waiting for you…" : "Working…"
        }
        var groups: [String] = []
        if !activeSources.isEmpty {
            groups.append("Working: " + activeSources.joined(separator: " • "))
        }
        if !waitingSources.isEmpty {
            groups.append("Waiting: " + waitingSources.joined(separator: " • "))
        }
        return groups.joined(separator: " • ")
    }
    var windowTitle: String {
        if !pendingByIdentity.isEmpty {
            return activityTitle(sources: Set(pendingByIdentity.values),
                                 latestSource: latestActivitySource,
                                 marker: "●", suffix: "working…")
        }
        if !waitingByIdentity.isEmpty {
            return activityTitle(sources: Set(waitingByIdentity.values),
                                 latestSource: latestActivitySource,
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

    private func identity(_ explicit: String?, source: String) -> String {
        explicit ?? source
    }

    mutating func operationStarted(source: String, identity explicit: String? = nil) {
        let key = identity(explicit, source: source)
        waitingByIdentity.removeValue(forKey: key)
        if latestWaitingIdentity == key {
            latestWaitingIdentity = waitingByIdentity.keys.sorted().first
        }
        pendingByIdentity[key] = source
        latestPendingIdentity = key
    }

    mutating func operationUpdated(source: String, identity explicit: String? = nil) {
        let key = identity(explicit, source: source)
        // Claude emits trailing stream frames after AskUserQuestion. They are
        // part of the same turn and must not turn "waiting" back into work.
        guard waitingByIdentity[key] == nil else { return }
        pendingByIdentity[key] = source
        latestPendingIdentity = key
    }

    mutating func operationWaitingForUser(source: String,
                                          identity explicit: String? = nil) {
        let key = identity(explicit, source: source)
        pendingByIdentity.removeValue(forKey: key)
        if latestPendingIdentity == key {
            latestPendingIdentity = pendingByIdentity.keys.sorted().first
        }
        waitingByIdentity[key] = source
        latestWaitingIdentity = key
    }

    mutating func operationFinished(source: String, identity explicit: String? = nil) {
        let key = identity(explicit, source: source)
        pendingByIdentity.removeValue(forKey: key)
        waitingByIdentity.removeValue(forKey: key)
        if latestPendingIdentity == key {
            latestPendingIdentity = pendingByIdentity.keys.sorted().first
        }
        if latestWaitingIdentity == key {
            latestWaitingIdentity = waitingByIdentity.keys.sorted().first
        }
    }

    mutating func readableContentArrived(source: String,
                                         identity explicit: String? = nil) {
        let key = identity(explicit, source: source)
        pendingByIdentity.removeValue(forKey: key)
        waitingByIdentity.removeValue(forKey: key)
        if latestPendingIdentity == key {
            latestPendingIdentity = pendingByIdentity.keys.sorted().first
        }
        if latestWaitingIdentity == key {
            latestWaitingIdentity = waitingByIdentity.keys.sorted().first
        }
        lastUsefulTitle = source
    }

    mutating func resetPending() {
        pendingByIdentity.removeAll()
        waitingByIdentity.removeAll()
        latestPendingIdentity = nil
        latestWaitingIdentity = nil
    }
}
