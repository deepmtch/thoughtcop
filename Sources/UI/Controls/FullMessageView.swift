// Dedicated full-text presentation. It intentionally contains no history or
// settings controls, so reading a summary never mutates the navigation UI.

import AppKit

final class FullMessageView: NSVisualEffectView {
    private static let minimumReaderHeight: CGFloat = 150
    private static let maximumReaderHeight: CGFloat = 520
    private static let headerAndMarginsHeight: CGFloat = 84
    private let toneWash = NSView()
    private let toneStripe = NSView()
    private let sourceLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    var closeRequested: (() -> Void)?
    var controlsRequested: (() -> Void)?
    var quitRequested: (() -> Void)?

    var source: String { sourceLabel.stringValue }
    var text: String { textView.string }
    private(set) var tone: MessageReaderTone = .normal
    var lifecycleButtonTitles: [String] { ["Done", quitButton.title] }
    var requiresScroll: Bool {
        textView.bounds.height > scrollView.contentView.bounds.height + 0.5
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        translatesAutoresizingMaskIntoConstraints = false

        toneWash.wantsLayer = true
        toneWash.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toneWash)

        toneStripe.wantsLayer = true
        toneStripe.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toneStripe)

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
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(doneButton)

        quitButton.target = self
        quitButton.action = #selector(quit(_:))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.toolTip = "Quit Thinkpeek (Command-Q)"
        quitButton.setAccessibilityLabel("Quit Thinkpeek")
        quitButton.keyEquivalent = "q"
        quitButton.keyEquivalentModifierMask = [.command]
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quitButton)

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
            toneWash.topAnchor.constraint(equalTo: topAnchor),
            toneWash.leadingAnchor.constraint(equalTo: leadingAnchor),
            toneWash.trailingAnchor.constraint(equalTo: trailingAnchor),
            toneWash.bottomAnchor.constraint(equalTo: bottomAnchor),
            toneStripe.topAnchor.constraint(equalTo: topAnchor),
            toneStripe.leadingAnchor.constraint(equalTo: leadingAnchor),
            toneStripe.bottomAnchor.constraint(equalTo: bottomAnchor),
            toneStripe.widthAnchor.constraint(equalToConstant: 6),
            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            sourceLabel.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
            sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: controlsButton.leadingAnchor,
                                                   constant: -12),
            controlsButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            controlsButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor,
                                                      constant: -8),
            doneButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            doneButton.trailingAnchor.constraint(equalTo: quitButton.leadingAnchor,
                                                  constant: -8),
            quitButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            quitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: doneButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyTone(.normal)
    }

    required init?(coder: NSCoder) { nil }

    func show(source: String, text: String, kind: String,
              tone: MessageReaderTone = .normal) {
        sourceLabel.stringValue = source
        sourceLabel.toolTip = source
        textView.textStorage?.setAttributedString(renderedBody(text, kind: kind))
        textView.scrollToBeginningOfDocument(nil)
        applyTone(tone)
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString:
            textView.textStorage ?? NSAttributedString())
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(
            width: max(1, width - textView.textContainerInset.width * 2),
            height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 5
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let renderedHeight = ceil(layout.usedRect(for: container).height)
        return min(Self.maximumReaderHeight,
                   max(Self.minimumReaderHeight,
                       Self.headerAndMarginsHeight + renderedHeight))
    }

    private func applyTone(_ tone: MessageReaderTone) {
        self.tone = tone
        switch tone {
        case .normal:
            toneWash.layer?.backgroundColor = NSColor.clear.cgColor
            toneStripe.layer?.backgroundColor = NSColor.clear.cgColor
            sourceLabel.textColor = .secondaryLabelColor
        case .warning:
            toneWash.layer?.backgroundColor = NSColor.systemOrange
                .withAlphaComponent(0.10).cgColor
            toneStripe.layer?.backgroundColor = NSColor.systemOrange.cgColor
            sourceLabel.textColor = .systemOrange
        case .error:
            toneWash.layer?.backgroundColor = NSColor.systemRed
                .withAlphaComponent(0.12).cgColor
            toneStripe.layer?.backgroundColor = NSColor.systemRed.cgColor
            sourceLabel.textColor = .systemRed
        }
    }

    @objc private func close(_ sender: Any?) { closeRequested?() }
    @objc private func showControls(_ sender: Any?) { controlsRequested?() }
    @objc private func quit(_ sender: Any?) { quitRequested?() }
}
