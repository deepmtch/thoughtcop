// One-click commands for the ticker's primary task and secondary controls.

import AppKit

final class TickerPrimaryActions: NSStackView {
    var checkRulesRequested: (() -> Void)?
    var controlsRequested: (() -> Void)?

    private let checkRulesButton: NSButton
    private let controlsButton: NSButton

    var accessibilityNames: [String] {
        arrangedSubviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }
    }

    var foregroundColor: NSColor? {
        didSet {
            checkRulesButton.contentTintColor = foregroundColor
            controlsButton.contentTintColor = foregroundColor
        }
    }

    override init(frame frameRect: NSRect) {
        checkRulesButton = NSButton(
            image: NSImage(systemSymbolName: "checklist",
                           accessibilityDescription: "Edit what to check") ?? NSImage(),
            target: nil, action: nil)
        controlsButton = NSButton(
            image: NSImage(systemSymbolName: "slider.horizontal.3",
                           accessibilityDescription: "Open controls") ?? NSImage(),
            target: nil, action: nil)
        super.init(frame: frameRect)

        orientation = .horizontal
        alignment = .centerY
        spacing = 2
        for button in [checkRulesButton, controlsButton] {
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            addArrangedSubview(button)
        }
        checkRulesButton.target = self
        checkRulesButton.action = #selector(openCheckRules(_:))
        checkRulesButton.toolTip = "Edit what Thinkpeek checks"
        checkRulesButton.setAccessibilityLabel("Edit what to check")
        controlsButton.target = self
        controlsButton.action = #selector(openControls(_:))
        controlsButton.toolTip = "Open navigation and ticker settings"
        controlsButton.setAccessibilityLabel("Open controls and settings")
    }

    required init?(coder: NSCoder) { nil }

    @objc private func openCheckRules(_ sender: Any?) { checkRulesRequested?() }
    @objc private func openControls(_ sender: Any?) { controlsRequested?() }

    func requestCheckRulesForTest() { openCheckRules(nil) }
    func requestControlsForTest() { openControls(nil) }
}
