// Small reusable AppKit pieces: window chrome, hover/drag handling, markdown
// rendering, and the reasoning-summary card.

import AppKit

enum CompactInteractionUX {
    static let clickDecisionDelay: TimeInterval = 0.22
    static let dragTolerance: CGFloat = 2
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A wrapping label whose intrinsic width never pushes its container wider.
/// AppKit's stock wrapping label can report the unwrapped text width before
/// Auto Layout assigns its real width, which stretches or collapses card rows.
final class WrappingTextField: NSTextField {
    private var measuredWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 1 ? bounds.width : preferredMaxLayoutWidth
        guard width > 1 else {
            return NSSize(width: NSView.noIntrinsicMetric,
                          height: super.intrinsicContentSize.height)
        }
        let rect = attributedStringValue.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(rect.height))
    }

    override func layout() {
        super.layout()
        guard bounds.width > 1, abs(measuredWidth - bounds.width) > 0.5 else { return }
        measuredWidth = bounds.width
        preferredMaxLayoutWidth = bounds.width
        invalidateIntrinsicContentSize()
    }
}

final class ConstrainedPanel: NSPanel {
    var escapeRequested: (() -> Void)?
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown && event.keyCode == 53 {
            escapeRequested?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        escapeRequested?()
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = (screen ?? self.screen ?? NSScreen.main)?.visibleFrame else {
            return frameRect
        }
        var frame = frameRect
        frame.size.width = min(frame.width, min(visible.width, maxSize.width))
        frame.size.height = min(frame.height, min(visible.height, maxSize.height))
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        return frame
    }
}

final class CompactInteractionView: NSView {
    var clicked: (() -> Void)?
    var doubleClicked: (() -> Void)?
    var draggingChanged: ((Bool) -> Void)?
    var dragOnly = false {
        didSet { discardCursorRects(); resetCursorRects() }
    }
    private var dragging = false
    private var pendingClick: DispatchWorkItem?

    override var mouseDownCanMoveWindow: Bool { dragOnly }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard dragOnly, bounds.contains(point) else { return super.hitTest(point) }
        let hit = super.hitTest(point)
        return hit is NSControl ? hit : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if dragOnly { addCursorRect(bounds, cursor: .openHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard dragOnly else { super.mouseDown(with: event); return }
        if event.clickCount == 2 {
            pendingClick?.cancel()
            doubleClicked?()
            return
        }
        dragging = true
        draggingChanged?(true)
        let startOrigin = window?.frame.origin
        NSCursor.closedHand.push()
        window?.performDrag(with: event)
        NSCursor.pop()
        let endOrigin = window?.frame.origin
        dragging = false
        draggingChanged?(false)
        if let startOrigin, let endOrigin,
           hypot(endOrigin.x - startOrigin.x, endOrigin.y - startOrigin.y)
              < CompactInteractionUX.dragTolerance {
            let work = DispatchWorkItem { [weak self] in self?.clicked?() }
            pendingClick?.cancel()
            pendingClick = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + CompactInteractionUX.clickDecisionDelay,
                execute: work)
        }
    }
}

func renderedBody(_ text: String, kind: String) -> NSAttributedString {
    let size: CGFloat = kind == "analysis" ? 15 : 13
    let weight: NSFont.Weight = kind == "activity" ? .semibold : .regular
    let baseFont = NSFont.systemFont(ofSize: size, weight: weight)
    let color: NSColor = kind == "omitted-analysis" ? .secondaryLabelColor : .labelColor
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 3
    paragraph.lineBreakMode = .byWordWrapping

    let result: NSMutableAttributedString
    if kind == "analysis" {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            result = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        } else {
            result = NSMutableAttributedString(string: text)
        }
    } else {
        result = NSMutableAttributedString(string: text)
    }

    let full = NSRange(location: 0, length: result.length)
    result.addAttributes([.font: baseFont, .foregroundColor: color,
                          .paragraphStyle: paragraph], range: full)
    result.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
        guard let number = value as? NSNumber else { return }
        let intent = InlinePresentationIntent(rawValue: number.uintValue)
        var font = baseFont
        if intent.contains(.stronglyEmphasized) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if intent.contains(.emphasized) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        if intent.contains(.code) {
            font = .monospacedSystemFont(ofSize: size - 1, weight: .regular)
        }
        result.addAttribute(.font, value: font, range: range)
        if intent.contains(.strikethrough) {
            result.addAttribute(.strikethroughStyle,
                                value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }
    result.removeAttribute(.inlinePresentationIntent, range: full)
    return result
}

final class EventCard: NSView {
    var contentChanged: (() -> Void)?
    private let footer = NSTextField(labelWithString: "")
    private let body = WrappingTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()

    init(source: String, time: String, event: UIEvent) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let sourceLabel = NSTextField(labelWithString: source)
        sourceLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let timeLabel = NSTextField(labelWithString: time)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        header.addArrangedSubview(sourceLabel)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(timeLabel)

        body.isSelectable = true
        body.maximumNumberOfLines = 0
        body.usesSingleLineMode = false
        body.lineBreakMode = .byWordWrapping
        body.preferredMaxLayoutWidth = 500
        body.cell?.wraps = true
        body.cell?.isScrollable = false
        body.cell?.truncatesLastVisibleLine = false
        body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        body.setContentHuggingPriority(.defaultLow, for: .horizontal)
        body.setContentCompressionResistancePriority(.required, for: .vertical)
        body.setContentHuggingPriority(.required, for: .vertical)
        body.attributedStringValue = renderedBody(event.text, kind: event.kind)

        footer.font = .systemFont(ofSize: 11, weight: .medium)
        footer.textColor = .secondaryLabelColor
        footer.isHidden = true
        footer.lineBreakMode = .byTruncatingMiddle
        footer.preferredMaxLayoutWidth = 500
        footer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.setContentCompressionResistancePriority(.required, for: .vertical)

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(body)
        stack.addArrangedSubview(footer)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(stack)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        switch event.kind {
        case "activity":
            layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.10).cgColor
            layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.28).cgColor
        case "omitted-analysis":
            layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.08).cgColor
            layer?.borderColor = NSColor.systemPurple.withAlphaComponent(0.22).cgColor
            body.textColor = .secondaryLabelColor
        default:
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        }
    }

    required init?(coder: NSCoder) { nil }

    func setFooter(_ text: String, color: NSColor = .secondaryLabelColor) {
        footer.stringValue = text
        footer.textColor = color
        footer.isHidden = false
        stack.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
        DispatchQueue.main.async { [weak self] in self?.contentChanged?() }
    }

    var layoutMetrics: (card: NSRect, body: NSRect, footer: NSRect) {
        (frame, body.convert(body.bounds, to: self), footer.convert(footer.bounds, to: self))
    }

    func setAlert(_ text: String) {
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.38).cgColor
        setFooter(text, color: .systemRed)
    }
}
