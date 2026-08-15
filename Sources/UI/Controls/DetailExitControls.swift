// Explicit lifecycle controls for the borderless detail presentations.

import AppKit

final class DetailExitControls: NSStackView {
    private let closeButton: NSButton
    private let moreButton: NSButton
    private let overflowMenu = NSMenu()
    var closeRequested: (() -> Void)?
    var quitRequested: (() -> Void)?

    var buttonTitles: [String] { ["Done", "More"] }
    var accessibilityNames: [String] {
        [closeButton.accessibilityLabel() ?? "", moreButton.accessibilityLabel() ?? ""]
    }
    var overflowMenuTitles: [String] { overflowMenu.items.map(\.title) }

    override init(frame frameRect: NSRect) {
        closeButton = NSButton(title: "Done", target: nil, action: nil)
        moreButton = NSButton(title: "", target: nil, action: nil)
        super.init(frame: frameRect)

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        closeButton.target = self
        closeButton.action = #selector(requestClose(_:))
        closeButton.toolTip = "Return to the one-line ticker (Esc)"
        closeButton.setAccessibilityLabel("Close details and return to ticker")
        closeButton.keyEquivalent = "\u{1b}"

        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .small
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        addArrangedSubview(closeButton)

        let quitItem = NSMenuItem(title: "Quit Thinkpeek",
                                  action: #selector(requestQuit(_:)),
                                  keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        overflowMenu.addItem(quitItem)
        moreButton.image = NSImage(systemSymbolName: "ellipsis.circle",
                                   accessibilityDescription: "More application actions")
        moreButton.imagePosition = .imageOnly
        moreButton.bezelStyle = .accessoryBarAction
        moreButton.isBordered = false
        moreButton.target = self
        moreButton.action = #selector(showOverflow(_:))
        moreButton.toolTip = "More application actions"
        moreButton.setAccessibilityLabel("More application actions")
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        addArrangedSubview(moreButton)
    }

    required init?(coder: NSCoder) { nil }

    @objc func requestClose(_ sender: Any?) { closeRequested?() }
    @objc func requestQuit(_ sender: Any?) { quitRequested?() }

    @objc private func showOverflow(_ sender: NSButton) {
        overflowMenu.popUp(positioning: nil,
                           at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                           in: sender)
    }
}
