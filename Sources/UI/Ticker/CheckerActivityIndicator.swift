// Compact, explicit signal that reasoning is currently being checked externally.

import AppKit

final class CheckerActivityIndicator: NSImageView {
    private(set) var isChecking = false
    private(set) var destination: String?

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
        self.destination = destination
        isChecking = true
        isHidden = false
        toolTip = "Checking reasoning with \(destination)"
        setAccessibilityLabel("Checking reasoning with \(destination)")
    }

    func finish() {
        destination = nil
        isChecking = false
        isHidden = true
        toolTip = nil
        setAccessibilityLabel("Checker idle")
    }
}
