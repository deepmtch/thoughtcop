// Explicit lifecycle controls for the borderless detail presentations.

import AppKit

final class DetailExitControls: NSStackView {
    private let closeButton: NSButton
    var closeRequested: (() -> Void)?

    var buttonTitles: [String] { [closeButton.title] }
    var accessibilityNames: [String] {
        [closeButton.accessibilityLabel() ?? ""]
    }

    override init(frame frameRect: NSRect) {
        closeButton = NSButton(title: "Hide Thinkpeek", target: nil, action: nil)
        super.init(frame: frameRect)

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        closeButton.target = self
        closeButton.action = #selector(requestClose(_:))
        closeButton.toolTip = "Hide Thinkpeek — show it again from the menu bar"
        closeButton.setAccessibilityLabel("Hide Thinkpeek")
        closeButton.keyEquivalent = "\u{1b}"

        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .small
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        addArrangedSubview(closeButton)

    }

    required init?(coder: NSCoder) { nil }

    @objc func requestClose(_ sender: Any?) { closeRequested?() }
}
