// A short note under the menu-bar icon after a violation, shown when "Flash
// Red, Then Show Bubble" is on. It never activates Thinkpeek or reopens a
// hidden window; clicking it opens the violation.

import AppKit

final class ViolationBubble {
    static let width: CGFloat = 300
    private let panel: NSPanel
    private let content = ViolationBubbleView()
    var clicked: (() -> Void)? {
        get { content.clicked }
        set { content.clicked = newValue }
    }

    var isVisible: Bool { panel.isVisible }
    var title: String { content.titleLabel.stringValue }
    var quote: String { content.quoteLabel.stringValue }
    var frame: NSRect { panel.frame }
    var contentView: NSView { content }

    /// The view a click at `point` (in the bubble's coordinates) reaches.
    func viewHit(at point: NSPoint) -> NSView? {
        content.hitTest(content.convert(point, to: content.superview))
    }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 72),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = content
    }

    /// Where the last bubble was placed: "under-icon", or "top-right" when the
    /// menu-bar icon is not visible on any screen (macOS hides status items
    /// that do not fit in the menu bar and parks their window off-screen).
    private(set) var placement = ""

    /// Shows the bubble below `anchor` (the status item's window frame, in
    /// screen coordinates) when that is visible on a screen, otherwise at the
    /// top right of the main screen below the menu bar; always inside it.
    func show(title: String, quote: String, below anchor: NSRect?) {
        content.set(title: title, quote: quote, width: Self.width)
        let size = NSSize(width: Self.width, height: content.fittingHeight(width: Self.width))
        let anchorScreen = anchor.flatMap { rect in
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }
        }
        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin: NSPoint
        if let anchor, anchorScreen != nil {
            placement = "under-icon"
            origin = NSPoint(x: anchor.midX - size.width / 2,
                             y: anchor.minY - 6 - size.height)
        } else {
            placement = "top-right"
            origin = NSPoint(x: visible.maxX - size.width - 8,
                             y: visible.maxY - 6 - size.height)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// True when the whole bubble lies inside a screen's visible area.
    var isOnScreen: Bool {
        NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) }
    }

    func hide() { panel.orderOut(nil) }
}

private final class ViolationBubbleView: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let quoteLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "Click to open")
    private let stripe = NSView()
    private let stack: NSStackView
    var clicked: (() -> Void)?

    override init(frame frameRect: NSRect) {
        stack = NSStackView(views: [titleLabel, quoteLabel, hintLabel])
        super.init(frame: frameRect)
        // A plain layer surface, so `/screenshot/bubble` renders it.
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        quoteLabel.font = .systemFont(ofSize: 12)
        // Two lines, the second ending in "…" (truncating-tail mode would
        // keep it to a single line).
        quoteLabel.maximumNumberOfLines = 2
        quoteLabel.lineBreakMode = .byWordWrapping
        quoteLabel.cell?.truncatesLastVisibleLine = true
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        for label in [titleLabel, quoteLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        stripe.wantsLayer = true
        stripe.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stripe)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stripe.leadingAnchor.constraint(equalTo: leadingAnchor),
            stripe.topAnchor.constraint(equalTo: topAnchor),
            stripe.bottomAnchor.constraint(equalTo: bottomAnchor),
            stripe.widthAnchor.constraint(equalToConstant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }

    func set(title: String, quote: String, width: CGFloat) {
        titleLabel.stringValue = title
        quoteLabel.stringValue = quote
        quoteLabel.preferredMaxLayoutWidth = width - 26
        setAccessibilityLabel("\(title). \(quote). Opens the violation.")
        toolTip = quote
    }

    func fittingHeight(width: CGFloat) -> CGFloat {
        frame.size.width = width
        layoutSubtreeIfNeeded()
        return ceil(stack.fittingSize.height) + 18
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        stripe.layer?.backgroundColor = NSColor.systemRed.cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    /// The whole bubble is one button: its labels must not take the click
    /// (only the empty bottom strip used to open it, BUG-101).
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil   // `point` is in the superview's space
    }

    override func mouseDown(with event: NSEvent) { clicked?() }

    override func accessibilityPerformPress() -> Bool {
        clicked?()
        return true
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
