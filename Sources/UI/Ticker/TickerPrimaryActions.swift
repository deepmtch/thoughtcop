// One-click commands for the ticker's primary task and secondary controls.

import AppKit

final class TickerPrimaryActions: NSStackView {
    var checkRulesRequested: (() -> Void)?
    var controlsRequested: (() -> Void)?
    var hideRequested: (() -> Void)?

    private let checkRulesButton: NSButton
    private(set) var displaySettingsButton: NSButton
    private let controlsButton: NSButton
    private let hideButton: NSButton

    var accessibilityNames: [String] {
        arrangedSubviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }
    }

    var foregroundColor: NSColor? {
        didSet {
            checkRulesButton.contentTintColor = foregroundColor
            displaySettingsButton.contentTintColor = foregroundColor
            controlsButton.contentTintColor = foregroundColor
            hideButton.contentTintColor = foregroundColor
        }
    }

    override init(frame frameRect: NSRect) {
        checkRulesButton = NSButton(
            image: NSImage(systemSymbolName: "text.bubble",
                           accessibilityDescription: "Edit check prompt") ?? NSImage(),
            target: nil, action: nil)
        displaySettingsButton = NSButton(frame: .zero)
        controlsButton = NSButton(
            image: NSImage(systemSymbolName: "slider.horizontal.3",
                           accessibilityDescription: "Open controls") ?? NSImage(),
            target: nil, action: nil)
        hideButton = NSButton(
            image: NSImage(systemSymbolName: "xmark",
                           accessibilityDescription: "Hide Thinkpeek") ?? NSImage(),
            target: nil, action: nil)
        super.init(frame: frameRect)

        orientation = .horizontal
        alignment = .centerY
        spacing = 2
        for button in [checkRulesButton, displaySettingsButton, controlsButton, hideButton] {
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            addArrangedSubview(button)
        }
        checkRulesButton.target = self
        checkRulesButton.action = #selector(openCheckRules(_:))
        checkRulesButton.toolTip = "Edit check prompt"
        checkRulesButton.setAccessibilityLabel("Edit check prompt")
        displaySettingsButton.toolTip = "Display settings"
        displaySettingsButton.setAccessibilityLabel("Display settings")
        controlsButton.target = self
        controlsButton.action = #selector(openControls(_:))
        controlsButton.toolTip = "Open message navigation"
        controlsButton.setAccessibilityLabel("Open message navigation")
        hideButton.target = self
        hideButton.action = #selector(hideTicker(_:))
        hideButton.toolTip = "Hide Thinkpeek — show it again from the menu bar"
        hideButton.setAccessibilityLabel("Hide Thinkpeek")
    }

    required init?(coder: NSCoder) { nil }

    @objc private func openCheckRules(_ sender: Any?) { checkRulesRequested?() }
    @objc private func openControls(_ sender: Any?) { controlsRequested?() }
    @objc private func hideTicker(_ sender: Any?) { hideRequested?() }

    func requestCheckRulesForTest() { openCheckRules(nil) }
    func requestControlsForTest() { openControls(nil) }
    func requestHideForTest() { hideTicker(nil) }
}
