// Explicit lifecycle controls for the borderless detail presentations.

import AppKit

final class DetailExitControls: NSStackView {
    private let closeButton: NSButton
    private let quitButton: NSButton
    var closeRequested: (() -> Void)?
    var quitRequested: (() -> Void)?

    var buttonTitles: [String] { [closeButton.title, quitButton.title] }
    var accessibilityNames: [String] {
        [closeButton.accessibilityLabel() ?? "", quitButton.accessibilityLabel() ?? ""]
    }

    override init(frame frameRect: NSRect) {
        closeButton = NSButton(title: "Close", target: nil, action: nil)
        quitButton = NSButton(title: "Quit", target: nil, action: nil)
        super.init(frame: frameRect)

        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        closeButton.target = self
        closeButton.action = #selector(requestClose(_:))
        closeButton.toolTip = "Return to the one-line ticker (Esc)"
        closeButton.setAccessibilityLabel("Close details and return to ticker")
        closeButton.keyEquivalent = "\u{1b}"

        quitButton.target = self
        quitButton.action = #selector(requestQuit(_:))
        quitButton.toolTip = "Quit Thinkpeek (Command-Q)"
        quitButton.setAccessibilityLabel("Quit Thinkpeek")
        quitButton.keyEquivalent = "q"
        quitButton.keyEquivalentModifierMask = [.command]

        for button in [closeButton, quitButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            addArrangedSubview(button)
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc func requestClose(_ sender: Any?) { closeRequested?() }
    @objc func requestQuit(_ sender: Any?) { quitRequested?() }
}
