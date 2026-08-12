// Small reusable AppKit pieces: window chrome, hover/drag handling, markdown
// rendering, and the reasoning-summary card.

import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class ConstrainedPanel: NSPanel {
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

final class HoverView: NSView {
    var hoverChanged: ((Bool) -> Void)?
    var doubleClicked: (() -> Void)?
    var draggingChanged: ((Bool) -> Void)?
    var dragOnly = false {
        didSet { discardCursorRects(); resetCursorRects() }
    }
    private var hoverArea: NSTrackingArea?
    private var dragging = false

    override var mouseDownCanMoveWindow: Bool { dragOnly }

    override func hitTest(_ point: NSPoint) -> NSView? {
        dragOnly && bounds.contains(point) ? self : super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if dragOnly { addCursorRect(bounds, cursor: .openHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard dragOnly else { super.mouseDown(with: event); return }
        if event.clickCount == 2 {
            doubleClicked?()
            return
        }
        dragging = true
        draggingChanged?(true)
        NSCursor.closedHand.push()
        window?.performDrag(with: event)
        NSCursor.pop()
        dragging = false
        draggingChanged?(false)
    }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways,
                                            .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        if !dragging { hoverChanged?(true) }
    }
    override func mouseExited(with event: NSEvent) {
        if !dragging { hoverChanged?(false) }
    }
}

func renderedBody(_ text: String, kind: String) -> NSAttributedString {
    let size: CGFloat = kind == "analysis" ? 15 : 13
    let weight: NSFont.Weight = kind == "activity" ? .semibold : .regular
    let baseFont = NSFont.systemFont(ofSize: size, weight: weight)
    let color: NSColor = kind == "omitted-analysis" ? .secondaryLabelColor : .labelColor
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 3

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
    private let footer = NSTextField(labelWithString: "")

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

        let body = NSTextField(wrappingLabelWithString: event.text)
        body.isSelectable = true
        body.maximumNumberOfLines = 0
        body.lineBreakMode = .byWordWrapping
        body.preferredMaxLayoutWidth = 500
        body.cell?.wraps = true
        body.cell?.isScrollable = false
        body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        body.setContentHuggingPriority(.defaultLow, for: .horizontal)
        body.attributedStringValue = renderedBody(event.text, kind: event.kind)

        footer.font = .systemFont(ofSize: 11, weight: .medium)
        footer.textColor = .secondaryLabelColor
        footer.isHidden = true
        footer.lineBreakMode = .byTruncatingMiddle
        footer.preferredMaxLayoutWidth = 500
        footer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [header, body, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
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
    }

    func setAlert(_ text: String) {
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.38).cgColor
        setFooter(text, color: .systemRed)
    }
}
