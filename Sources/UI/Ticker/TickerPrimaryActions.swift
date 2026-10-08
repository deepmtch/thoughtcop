// The ticker's three actions: History, Settings and Hide. Clicking the text
// opens the reader.

import AppKit

final class TickerPrimaryActions: NSStackView {
    var historyRequested: (() -> Void)?
    var hideRequested: (() -> Void)?

    private let historyButton: NSButton
    private(set) var displaySettingsButton: NSButton
    private let hideButton: NSButton

    var accessibilityNames: [String] {
        arrangedSubviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }
    }

    var foregroundColor: NSColor? {
        didSet {
            historyButton.contentTintColor = foregroundColor
            displaySettingsButton.contentTintColor = foregroundColor
            hideButton.contentTintColor = foregroundColor
        }
    }

    override init(frame frameRect: NSRect) {
        historyButton = NSButton(
            image: NSImage(systemSymbolName: "clock.arrow.circlepath",
                           accessibilityDescription: "Open history") ?? NSImage(),
            target: nil, action: nil)
        displaySettingsButton = NSButton(frame: .zero)
        hideButton = NSButton(
            image: NSImage(systemSymbolName: "xmark",
                           accessibilityDescription: "Hide ThoughtCop") ?? NSImage(),
            target: nil, action: nil)
        super.init(frame: frameRect)

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        for button in [historyButton, displaySettingsButton, hideButton] {
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            addArrangedSubview(button)
        }
        historyButton.target = self
        historyButton.action = #selector(openHistory(_:))
        historyButton.toolTip = "History: all items, violations and archive"
        historyButton.setAccessibilityLabel("Open history")
        displaySettingsButton.toolTip = "Settings"
        displaySettingsButton.setAccessibilityLabel("Settings")
        hideButton.target = self
        hideButton.action = #selector(hideTicker(_:))
        hideButton.toolTip = "Hide ThoughtCop — show it again from the menu bar"
        hideButton.setAccessibilityLabel("Hide ThoughtCop")
    }

    required init?(coder: NSCoder) { nil }

    @objc private func openHistory(_ sender: Any?) { historyRequested?() }
    @objc private func hideTicker(_ sender: Any?) { hideRequested?() }

    func requestHistoryForTest() { openHistory(nil) }
    func requestHideForTest() { hideTicker(nil) }
}
