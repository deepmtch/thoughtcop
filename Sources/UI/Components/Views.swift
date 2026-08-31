// Small reusable AppKit pieces: window chrome, hover/drag handling, markdown
// rendering, and the reasoning-summary card.

import AppKit

enum CompactInteractionUX {
    static let dragTolerance: CGFloat = 2
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class HistoryEmptyStateView: NSView {
    var editPromptRequested: (() -> Void)?
    private let icon: NSImageView
    private let title: NSTextField
    private let detail: NSTextField
    private let edit: NSButton

    override init(frame frameRect: NSRect) {
        icon = NSImageView(image: NSImage())
        title = NSTextField(labelWithString: "")
        detail = NSTextField(labelWithString: "")
        edit = NSButton(title: "Edit Check Prompt…", target: nil, action: nil)
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        icon.image = NSImage(
            systemSymbolName: "checkmark.shield",
            accessibilityDescription: "No violations") ?? NSImage()
        icon.contentTintColor = .systemGreen
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)

        title.stringValue = "No violations recorded"
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.alignment = .center

        detail.stringValue =
            "Matches to your check prompt will appear here and remain available after restart."
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping

        edit.target = self
        edit.action = #selector(editPrompt(_:))
        edit.bezelStyle = .rounded
        edit.controlSize = .regular
        edit.setAccessibilityLabel("Edit the prompt used to detect violations")

        let stack = NSStackView(views: [icon, title, detail, edit])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(14, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 42),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -42),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 390),
        ])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func editPrompt(_ sender: Any?) { editPromptRequested?() }

    func showStorageError(_ message: String?) {
        let hasError = message != nil
        icon.image = NSImage(systemSymbolName: hasError
            ? "exclamationmark.shield" : "checkmark.shield",
            accessibilityDescription: hasError ? "Violation history unavailable"
                                               : "No violations")
        icon.contentTintColor = hasError ? .systemOrange : .systemGreen
        title.stringValue = hasError ? "Violation history unavailable"
                                     : "No violations recorded"
        detail.stringValue = message ??
            "Matches to your check prompt will appear here and remain available after restart."
        edit.isHidden = hasError
    }
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
        let focusedControl = firstResponder is NSTextView || firstResponder is NSControl
        if !focusedControl {
            switch event.keyCode {
            case 123, 126: previousRequested?(); return true
            case 124, 125: nextRequested?(); return true
            case 115: firstRequested?(); return true
            case 119: latestRequested?(); return true
            case 36, 49: openMessageRequested?(); return true
            default: break
            }
        }
        if !focusedControl, characters == "k" { previousRequested?(); return true }
        if !focusedControl, characters == "j" { nextRequested?(); return true }
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
    var draggingChanged: ((Bool) -> Void)?
    var dragOnly = false {
        didSet { discardCursorRects(); resetCursorRects() }
    }
    private var dragging = false

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
            clicked?()
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
    var selectedRequested: (() -> Void)?
    var openRequested: (() -> Void)?
    private let footer = NSTextField(labelWithString: "")
    private let body = IntrinsicTextView(frame: .zero)
    private let stack = NSStackView()
    private let violationBadge = NSTextField(labelWithString: "VIOLATION")
    private var violationBadgeWidth: NSLayoutConstraint!
    private let violationAccent = NSView(frame: .zero)
    private let providerIcon = ProviderIconView(frame: .zero)
    private var selected = false

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

        violationBadge.stringValue = "Violation"
        violationBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        violationBadge.textColor = .white
        violationBadge.alignment = .center
        violationBadge.wantsLayer = true
        violationBadge.layer?.backgroundColor = NSColor.systemRed.cgColor
        violationBadge.layer?.cornerRadius = 5
        violationBadge.isHidden = true
        violationBadge.translatesAutoresizingMaskIntoConstraints = false
        violationBadgeWidth = violationBadge.widthAnchor.constraint(equalToConstant: 78)
        violationBadgeWidth.isActive = true
        violationBadge.heightAnchor.constraint(equalToConstant: 20).isActive = true

        providerIcon.update(source: source)
        providerIcon.translatesAutoresizingMaskIntoConstraints = false
        providerIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        providerIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        header.addArrangedSubview(violationBadge)
        header.addArrangedSubview(providerIcon)
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
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel("Message from \(source), \(time)")

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
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
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

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectedRequested?()
        if event.clickCount == 2 { openRequested?() }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { setSelected(true) }
        return accepted
    }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        setAccessibilitySelected(selected)
        layer?.borderWidth = selected ? 2 : 1
        if selected {
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        } else if violationBadge.isHidden {
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        } else {
            layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.48).cgColor
        }
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
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.48).cgColor
        layer?.borderWidth = selected ? 2 : 1
        setFooter(text, color: .secondaryLabelColor)
    }

    func setViolation(reason: String, evidence: String, provider: String,
                      latencyMs: Int, checkPrompt: String) {
        let content = NSMutableAttributedString()
        content.append(NSAttributedString(
            string: reason,
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                         .foregroundColor: NSColor.labelColor]))
        if !evidence.isEmpty {
            content.append(NSAttributedString(
                string: "\n\nEvidence\n",
                attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                             .foregroundColor: NSColor.secondaryLabelColor]))
            content.append(NSAttributedString(
                string: "“\(evidence)”",
                attributes: [.font: NSFont.systemFont(ofSize: 13),
                             .foregroundColor: NSColor.labelColor]))
        }
        body.textStorage?.setAttributedString(content)
        setAlert("Checked by \(provider) · \(latencyMs) ms")
        footer.toolTip = "Check prompt: \(checkPrompt)"
        setAccessibilityLabel("Violation. \(reason). Source: \(provider).")
    }

    func setViolationReviewed(_ reviewed: Bool) {
        violationBadge.stringValue = reviewed ? "Violation" : "New violation"
        violationBadgeWidth.constant = reviewed ? 78 : 96
        violationBadge.layer?.backgroundColor = (reviewed
            ? NSColor.systemRed.withAlphaComponent(0.82) : NSColor.systemRed).cgColor
    }

    func setError(_ text: String) {
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
        layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.45).cgColor
        layer?.borderWidth = 1
        setFooter(text, color: .labelColor)
    }
}
