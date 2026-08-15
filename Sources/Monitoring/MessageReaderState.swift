// Deterministic selection rules for reading one message while new events arrive.

struct MessageReaderSnapshot {
    let source: String
    let text: String
    let kind: String
}

enum MessageReaderSelection {
    static func shouldAdvanceForNewMessage(isReaderOpen: Bool,
                                           wasFollowingLatest: Bool) -> Bool {
        !isReaderOpen && wasFollowingLatest
    }

    static func latestIndex(eventCount: Int) -> Int {
        eventCount > 0 ? eventCount - 1 : -1
    }
}
