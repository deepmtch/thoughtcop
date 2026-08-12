// Popover-style outside-click handling shared by the message presentation and
// its headless regression test.

import AppKit

func shouldDismissFullMessage(isShowing: Bool, windowFrame: NSRect,
                              clickLocation: NSPoint) -> Bool {
    isShowing && !windowFrame.contains(clickLocation)
}

final class OutsideClickMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start(handler: @escaping (NSPoint) -> Void) {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            handler(NSEvent.mouseLocation)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in
            handler(NSEvent.mouseLocation)
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    deinit { stop() }
}
