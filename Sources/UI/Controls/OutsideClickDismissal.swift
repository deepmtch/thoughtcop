// Popover-style outside-click handling shared by every detail presentation and
// its headless regression test.

import AppKit

func shouldDismissDetails(isShowingDetails: Bool, isEditorVisible: Bool,
                          windowFrame: NSRect, clickLocation: NSPoint) -> Bool {
    isShowingDetails && !isEditorVisible && !windowFrame.contains(clickLocation)
}

final class OutsideClickMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var shouldDismiss: ((NSPoint) -> Bool)?
    private var dismiss: (() -> Void)?

    /// `shouldDismiss` is evaluated when the click happens, against the
    /// window as it is then. Evaluating it later saw the reader the click had
    /// just opened (narrower than the ticker) and closed it again.
    func start(shouldDismiss: @escaping (NSPoint) -> Bool, dismiss: @escaping () -> Void) {
        stop()
        self.shouldDismiss = shouldDismiss
        self.dismiss = dismiss
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleClick(at: NSEvent.mouseLocation)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handleClick(at: NSEvent.mouseLocation)
        }
    }

    func handleClick(at location: NSPoint) {
        guard shouldDismiss?(location) == true, let dismiss else { return }
        DispatchQueue.main.async(execute: dismiss)
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    deinit { stop() }
}
