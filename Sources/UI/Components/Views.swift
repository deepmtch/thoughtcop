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

/// Intrinsically sized rich text for card bodies. NSTextField can retain the
/// full attributed string while drawing only its first paragraph; NSTextView's
/// text layout manager renders every paragraph and exposes its exact height.
final class IntrinsicTextView: NSTextView {
    private var measuredWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 1 ? bounds.width : 496
        textContainer?.containerSize = NSSize(
            width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager?.ensureLayout(for: textContainer!)
        let height = layoutManager.map { ceil($0.usedRect(for: textContainer!).height) } ?? 0
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func layout() {
        super.layout()
        guard bounds.width > 1, abs(bounds.width - measuredWidth) > 0.5 else { return }
        measuredWidth = bounds.width
        textContainer?.containerSize = NSSize(
            width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        invalidateIntrinsicContentSize()
    }
}

final class ConstrainedPanel: NSPanel {
    var escapeRequested: (() -> Void)?
    var previousRequested: (() -> Void)?
    var nextRequested: (() -> Void)?
    var firstRequested: (() -> Void)?
    var latestRequested: (() -> Void)?
    var openMessageRequested: (() -> Void)?
    var violationsRequested: (() -> Void)?
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown && event.keyCode == 53 {
            escapeRequested?()
            return true
        }
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains([.command, .shift]), characters == "v" {
            violationsRequested?(); return true
        }
        guard !flags.contains(.command), !flags.contains(.control),
              !flags.contains(.option) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.keyCode {
        case 123, 126: previousRequested?(); return true
        case 124, 125: nextRequested?(); return true
        case 115: firstRequested?(); return true
        case 119: latestRequested?(); return true
        case 36, 49: openMessageRequested?(); return true
        default: break
        }
        if characters == "k" { previousRequested?(); return true }
        if characters == "j" { nextRequested?(); return true }
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

    /// Native macOS window backgrounds keep the standard arrow even when the
    /// surface can initiate a window drag. Hand cursors are reserved for links.
    var backgroundCursor: NSCursor { .arrow }

    override var mouseDownCanMoveWindow: Bool { dragOnly }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard dragOnly, bounds.contains(point) else { return super.hitTest(point) }
        let hit = super.hitTest(point)
        return hit is NSControl ? hit : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if dragOnly { addCursorRect(bounds, cursor: backgroundCursor) }
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
        window?.performDrag(with: event)
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
        // Codex summary_text entries are emitted as bold Markdown headings.
        // In a reasoning card they are body paragraphs, so analysis uses the
        // app's regular body font instead of turning every entry into a title.
        if kind != "analysis" && intent.contains(.stronglyEmphasized) {
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
    private let body = IntrinsicTextView(frame: .zero)
    private let stack = NSStackView()
    private let violationBadge = NSTextField(labelWithString: "VIOLATION")
    private let violationAccent = NSView(frame: .zero)
    private let violationGradient = CAGradientLayer()

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

        violationBadge.font = .systemFont(ofSize: 9, weight: .bold)
        violationBadge.textColor = .white
        violationBadge.alignment = .center
        violationBadge.wantsLayer = true
        violationBadge.layer?.backgroundColor = NSColor.systemRed.cgColor
        violationBadge.layer?.cornerRadius = 5
        violationBadge.isHidden = true
        violationBadge.translatesAutoresizingMaskIntoConstraints = false
        violationBadge.widthAnchor.constraint(equalToConstant: 70).isActive = true
        violationBadge.heightAnchor.constraint(equalToConstant: 20).isActive = true

        header.addArrangedSubview(violationBadge)
        header.addArrangedSubview(sourceLabel)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(timeLabel)

        body.isEditable = false
        body.isSelectable = true
        body.drawsBackground = false
        body.isRichText = true
        body.textContainerInset = .zero
        body.textContainer?.lineFragmentPadding = 0
        body.isHorizontallyResizable = false
        body.isVerticallyResizable = true
        body.textContainer?.widthTracksTextView = true
        body.textContainer?.containerSize = NSSize(
            width: 496, height: CGFloat.greatestFiniteMagnitude)
        body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        body.setContentHuggingPriority(.defaultLow, for: .horizontal)
        body.setContentCompressionResistancePriority(.required, for: .vertical)
        body.setContentHuggingPriority(.required, for: .vertical)
        body.textStorage?.setAttributedString(renderedBody(event.text, kind: event.kind))

        footer.font = .systemFont(ofSize: 11, weight: .medium)
        footer.textColor = .secondaryLabelColor
        footer.isHidden = true
        footer.lineBreakMode = .byWordWrapping
        footer.maximumNumberOfLines = 0
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
        violationAccent.translatesAutoresizingMaskIntoConstraints = false
        violationAccent.wantsLayer = true
        violationAccent.layer?.backgroundColor = NSColor.systemRed.cgColor
        violationAccent.isHidden = true
        addSubview(violationAccent, positioned: .above, relativeTo: nil)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            violationAccent.leadingAnchor.constraint(equalTo: leadingAnchor),
            violationAccent.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            violationAccent.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            violationAccent.widthAnchor.constraint(equalToConstant: 5),
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

    override func layout() {
        super.layout()
        violationGradient.frame = bounds
    }

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

    var displayedText: String { body.string }

    func setAlert(_ text: String) {
        violationBadge.isHidden = false
        violationAccent.isHidden = false
        violationGradient.colors = [
            NSColor.systemRed.withAlphaComponent(0.16).cgColor,
            NSColor.systemOrange.withAlphaComponent(0.09).cgColor,
            NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor,
        ]
        violationGradient.locations = [0, 0.42, 1]
        violationGradient.startPoint = CGPoint(x: 0, y: 0)
        violationGradient.endPoint = CGPoint(x: 1, y: 1)
        violationGradient.cornerRadius = 12
        if violationGradient.superlayer == nil {
            layer?.insertSublayer(violationGradient, at: 0)
        }
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.78).cgColor
        layer?.borderWidth = 2
        layer?.shadowColor = NSColor.systemRed.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 10
        layer?.shadowOffset = .zero
        setFooter(text, color: .systemRed)
    }

    func setError(_ text: String) {
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.14).cgColor
        layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.72).cgColor
        layer?.borderWidth = 2
        setFooter(text, color: .systemRed)
    }
}
