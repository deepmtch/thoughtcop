// Deterministic selection rules for reading one message while new events arrive.

enum MessageReaderTone: String {
    case normal
    case warning
    case error
}

struct MessageReaderSnapshot {
    let source: String
    let text: String
    let kind: String
    let tone: MessageReaderTone
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
