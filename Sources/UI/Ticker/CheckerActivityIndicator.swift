// Compact, explicit signal that reasoning is currently being checked externally.

import AppKit

final class CheckerActivityIndicator: NSImageView {
    static let minimumVisibleDuration: TimeInterval = 0.8

    private(set) var isChecking = false
    private(set) var destination: String?
    private var visibleSince: Date?
    private var pendingHide: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = NSImage(systemSymbolName: "lightbulb.fill",
                        accessibilityDescription: "Checker request in progress")
        imageScaling = .scaleProportionallyDown
        contentTintColor = .systemOrange
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Checker idle")
    }

    required init?(coder: NSCoder) { nil }

    func begin(destination: String) {
        pendingHide?.cancel()
        pendingHide = nil
        self.destination = destination
        visibleSince = Date()
        isChecking = true
        isHidden = false
        toolTip = "Checking reasoning with \(destination)"
        setAccessibilityLabel("Checking reasoning with \(destination)")
    }

    func finish(minimumVisibleDuration: TimeInterval = minimumVisibleDuration) {
        isChecking = false
        let elapsed = Date().timeIntervalSince(visibleSince ?? Date())
        let delay = max(0, minimumVisibleDuration - elapsed)
        let hide = DispatchWorkItem { [weak self] in
            self?.hideCompletedRequest()
        }
        pendingHide = hide
        if delay == 0 {
            hide.perform()
        } else {
            toolTip = "Checker request completed"
            setAccessibilityLabel("Checker request completed")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: hide)
        }
    }

    private func hideCompletedRequest() {
        pendingHide = nil
        destination = nil
        visibleSince = nil
        isHidden = true
        toolTip = nil
        setAccessibilityLabel("Checker idle")
    }
}
