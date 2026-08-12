// Dedicated full-text presentation. It intentionally contains no history or
// settings controls, so reading a summary never mutates the navigation UI.

import AppKit

final class FullMessageView: NSVisualEffectView {
    private let sourceLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    var closeRequested: (() -> Void)?
    var controlsRequested: (() -> Void)?

    var source: String { sourceLabel.stringValue }
    var text: String { textView.string }
    var requiresScroll: Bool {
        textView.bounds.height > scrollView.contentView.bounds.height + 0.5
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        translatesAutoresizingMaskIntoConstraints = false

        sourceLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(sourceLabel)

        let controlsButton = NSButton(title: "Controls…", target: self,
                                      action: #selector(showControls(_:)))
        controlsButton.bezelStyle = .rounded
        controlsButton.controlSize = .small
        controlsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controlsButton)

        let doneButton = NSButton(title: "Done", target: self,
                                  action: #selector(close(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.keyEquivalent = "\u{1b}"
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(doneButton)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            sourceLabel.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
            sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: controlsButton.leadingAnchor,
                                                   constant: -12),
            controlsButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            controlsButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor,
                                                      constant: -8),
            doneButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: doneButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func show(source: String, text: String, kind: String) {
        sourceLabel.stringValue = source
        sourceLabel.toolTip = source
        textView.textStorage?.setAttributedString(renderedBody(text, kind: kind))
        textView.scrollToBeginningOfDocument(nil)
    }

    @objc private func close(_ sender: Any?) { closeRequested?() }
    @objc private func showControls(_ sender: Any?) { controlsRequested?() }
}
