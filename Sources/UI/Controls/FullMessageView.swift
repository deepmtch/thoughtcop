// Dedicated full-text presentation. It intentionally contains no history or
// settings controls, so reading a summary never mutates the navigation UI.

import AppKit

final class FullMessageView: NSVisualEffectView, NSTextViewDelegate {
    private static let minimumReaderHeight: CGFloat = 118
    private static let maximumReaderHeight: CGFloat = 420
    private static let headerAndMarginsHeight: CGFloat = 62
    private let toneWash = NSView()
    private let toneStripe = NSView()
    private let providerIcon = ProviderIconView(frame: .zero)
    private let sourceLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let exitControls = DetailExitControls(frame: .zero)
    var closeRequested: (() -> Void)?
    var historyRequested: (() -> Void)?
    /// A doublethink:// link in the text, such as "Why and full message ▸".
    var linkRequested: ((URL) -> Void)?
    var tabSelected: ((Int) -> Void)?
    var jumpToLatestRequested: (() -> Void)?
    /// One tab per recent session plus All; empty hides the row.
    private let tabs = SessionChipsView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let jumpButton = NSButton(title: "Jump to latest ↑", target: nil, action: nil)
    private var scrollTopToHeader: NSLayoutConstraint!
    private var scrollTopToStatus: NSLayoutConstraint!
    var tabTitles: [String] { tabs.titles }
    var tabFrames: [NSRect] { tabs.chipFrames }
    var tabContentFrames: [NSRect] { tabs.chipContentFrames }
    var tabAreaWidth: CGFloat { tabs.frame.width }
    var selectedTab: Int { tabs.selected }
    var statusText: String { statusLabel.stringValue }
    var jumpVisible: Bool { !jumpButton.isHidden }

    var source: String { sourceLabel.stringValue }
    var text: String { textView.string }
    private(set) var tone: MessageReaderTone = .normal
    var lifecycleButtonTitles: [String] { exitControls.buttonTitles }
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

        providerIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(providerIcon)

        sourceLabel.font = .systemFont(ofSize: 12, weight: .medium)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(sourceLabel)

        let controlsButton = NSButton(
            image: NSImage(systemSymbolName: "clock.arrow.circlepath",
                           accessibilityDescription: "Open history") ?? NSImage(),
            target: self, action: #selector(showHistory(_:)))
        controlsButton.bezelStyle = .accessoryBarAction
        controlsButton.isBordered = false
        controlsButton.controlSize = .small
        controlsButton.imagePosition = .imageOnly
        controlsButton.toolTip = "History: all items, violations and archive"
        controlsButton.setAccessibilityLabel("Open history")
        controlsButton.translatesAutoresizingMaskIntoConstraints = false
        controlsButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        addSubview(controlsButton)

        exitControls.closeRequested = { [weak self] in self?.closeRequested?() }
        addSubview(exitControls)

        textView.delegate = self
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 14, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)

        tabs.chipSelected = { [weak self] index in self?.chipPressed(index) }
        tabs.setAccessibilityLabel("Sessions")
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.isHidden = true
        addSubview(tabs)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        addSubview(statusLabel)
        jumpButton.target = self
        jumpButton.action = #selector(jumpToLatest(_:))
        jumpButton.isBordered = false
        jumpButton.font = .systemFont(ofSize: 11)
        jumpButton.contentTintColor = .linkColor
        jumpButton.setAccessibilityLabel("Jump to the latest message of this session")
        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        jumpButton.isHidden = true
        addSubview(jumpButton)

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
            providerIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            providerIcon.centerYAnchor.constraint(equalTo: exitControls.centerYAnchor),
            providerIcon.widthAnchor.constraint(equalToConstant: 18),
            providerIcon.heightAnchor.constraint(equalToConstant: 18),
            sourceLabel.leadingAnchor.constraint(equalTo: providerIcon.trailingAnchor,
                                                   constant: 6),
            sourceLabel.centerYAnchor.constraint(equalTo: exitControls.centerYAnchor),
            sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: controlsButton.leadingAnchor,
                                                   constant: -12),
            exitControls.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            exitControls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            controlsButton.centerYAnchor.constraint(equalTo: exitControls.centerYAnchor),
            controlsButton.trailingAnchor.constraint(equalTo: exitControls.leadingAnchor,
                                                      constant: -6),
            // One row of tabs under the header; the Live / Paused status sits
            // in the header row beside History and Done.
            tabs.topAnchor.constraint(equalTo: exitControls.bottomAnchor, constant: 8),
            tabs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: exitControls.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            jumpButton.centerYAnchor.constraint(equalTo: exitControls.centerYAnchor),
            jumpButton.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            jumpButton.trailingAnchor.constraint(lessThanOrEqualTo: controlsButton.leadingAnchor,
                                                 constant: -8),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: controlsButton.leadingAnchor,
                                                  constant: -8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        scrollTopToHeader = scrollView.topAnchor.constraint(
            equalTo: exitControls.bottomAnchor, constant: 10)
        scrollTopToStatus = scrollView.topAnchor.constraint(
            equalTo: tabs.bottomAnchor, constant: 6)
        scrollTopToHeader.isActive = true
        applyTone(.normal)
    }

    required init?(coder: NSCoder) { nil }

    func show(source: String, text: String, kind: String,
              tone: MessageReaderTone = .normal) {
        sourceLabel.stringValue = source
        sourceLabel.toolTip = source
        providerIcon.update(source: source)
        textView.textStorage?.setAttributedString(renderedBody(text, kind: kind))
        textView.scrollToBeginningOfDocument(nil)
        applyTone(tone)
    }

    /// Session tabs in one row (titles already include any "N new" count):
    /// All, the shown chats, then "+N ▾" when `overflowTitles` is not empty.
    /// Picking chat k of the "+N" menu reports tab `titles.count - 1 + k`.
    /// Empty titles hide the tabs and the Live / Paused status.
    func setSessions(_ titles: [String], selected: Int, status: String,
                     live: Bool, showJump: Bool, width: CGFloat,
                     toolTips: [String] = [], working: [Bool] = [],
                     overflowTitles: [String] = [], overflowWorking: [Bool] = []) {
        let visible = !titles.isEmpty
        self.overflowTitles = overflowTitles
        self.overflowWorking = overflowWorking
        tabs.update(titles: titles, toolTips: toolTips, working: working,
                    selected: selected, width: width - 32,
                    lastIsOverflow: !overflowTitles.isEmpty)
        tabs.isHidden = !visible
        statusLabel.stringValue = status
        statusLabel.textColor = live ? .systemGreen : .secondaryLabelColor
        statusLabel.isHidden = !visible
        jumpButton.isHidden = !visible || !showJump
        scrollTopToHeader.isActive = !visible
        scrollTopToStatus.isActive = visible
        // The tabs replace the single source line.
        providerIcon.isHidden = visible
        sourceLabel.isHidden = visible
    }

    @objc private func jumpToLatest(_ sender: Any?) { jumpToLatestRequested?() }

    private var overflowTitles: [String] = []
    private var overflowWorking: [Bool] = []
    var overflowMenuTitles: [String] { overflowTitles }

    private func chipPressed(_ index: Int) {
        guard !overflowTitles.isEmpty, index == tabs.titles.count - 1 else {
            tabSelected?(index)
            return
        }
        let menu = NSMenu()
        for (k, title) in overflowTitles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(overflowPicked(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index + k
            if overflowWorking.indices.contains(k), overflowWorking[k] {
                item.image = NSImage(systemSymbolName: "circle.fill",
                                     accessibilityDescription: "Working")?
                    .withSymbolConfiguration(.init(pointSize: 7, weight: .regular)
                        .applying(.init(paletteColors: [.systemGreen])))
            }
            menu.addItem(item)
        }
        if let chip = tabs.chip(at: index) {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: chip.bounds.maxY + 4), in: chip)
        }
    }

    @objc private func overflowPicked(_ sender: NSMenuItem) { tabSelected?(sender.tag) }

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
        let sessionRows: CGFloat = tabs.isHidden ? 0 : tabs.contentHeight + 4
        return min(Self.maximumReaderHeight,
                   max(Self.minimumReaderHeight,
                       Self.headerAndMarginsHeight + sessionRows + renderedHeight))
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
            sourceLabel.textColor = .secondaryLabelColor
        case .error:
            // A thin red stripe marks a violation; the surface stays the
            // normal window background like every other view.
            toneWash.layer?.backgroundColor = NSColor.clear.cgColor
            toneStripe.layer?.backgroundColor = NSColor.systemRed.cgColor
            sourceLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func showHistory(_ sender: Any?) { historyRequested?() }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url, url.scheme == "doublethink" else { return false }
        linkRequested?(url)
        return true
    }
}

/// Session chips in one row: All and "+N ▾" at their natural width, the chats
/// sharing the rest (each as wide as its name, then truncated). Replaces a
/// segmented control whose equal slices made long names unreadable.
final class SessionChipsView: NSView {
    static let chipHeight: CGFloat = 22
    static let spacing: CGFloat = 6
    var chipSelected: ((Int) -> Void)?
    private(set) var titles: [String] = []
    private(set) var selected = -1
    private var chips: [NSButton] = []
    private var heightConstraint: NSLayoutConstraint!
    private var availableWidth: CGFloat = 0
    private var lastIsOverflow = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        setAccessibilityRole(.tabGroup)
    }

    required init?(coder: NSCoder) { nil }

    var contentHeight: CGFloat { heightConstraint.constant }

    func update(titles: [String], toolTips: [String], working: [Bool],
                selected: Int, width: CGFloat, lastIsOverflow: Bool = false) {
        self.titles = titles
        self.selected = selected
        self.lastIsOverflow = lastIsOverflow
        availableWidth = width
        chips.forEach { $0.removeFromSuperview() }
        chips = titles.enumerated().map { index, title in
            let chip = NSButton(title: "", target: self, action: #selector(chipPressed(_:)))
            chip.cell = ChipCell(textCell: "")
            chip.target = self
            chip.action = #selector(chipPressed(_:))
            chip.tag = index
            chip.isBordered = false
            chip.wantsLayer = true
            chip.layer?.cornerRadius = Self.chipHeight / 2
            chip.layer?.borderWidth = 0.5
            let isSelected = index == selected
            chip.layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor
                : NSColor.clear).cgColor
            chip.layer?.borderColor = (isSelected ? NSColor.controlAccentColor
                : NSColor.separatorColor).cgColor
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            chip.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? NSColor.white : NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
            let isWorking = working.indices.contains(index) && working[index]
            (chip.cell as? ChipCell)?.showsDot = isWorking
            let tip = toolTips.indices.contains(index) ? toolTips[index] : title
            chip.toolTip = tip
            chip.setAccessibilityLabel(tip + (isWorking ? ", working" : ""))
            chip.setAccessibilitySelected(isSelected)
            addSubview(chip)
            return chip
        }
        layoutChips()
    }

    private func naturalWidth(_ chip: NSButton) -> CGFloat {
        let text = chip.attributedTitle.size().width
        let dot = (chip.cell as? ChipCell)?.showsDot == true ? ChipCell.dotSpace : 0
        return max(36, ceil(text + dot + ChipCell.padding * 2))
    }

    /// All (first) and "+N ▾" (last, when present) keep their natural width;
    /// the chats share what is left, none wider than its name.
    private func layoutChips() {
        let natural = chips.map(naturalWidth)
        let fixed = Set([0] + (lastIsOverflow ? [chips.count - 1] : []))
            .filter { chips.indices.contains($0) }
        let flexible = chips.indices.filter { !fixed.contains($0) }
        let spacing = Self.spacing * CGFloat(max(0, chips.count - 1))
        var remaining = availableWidth - spacing - fixed.map { natural[$0] }.reduce(0, +)
        var widths = natural
        // Water-fill: narrow names keep their width, wide ones share the rest.
        var open = flexible.sorted { natural[$0] < natural[$1] }
        while !open.isEmpty {
            let share = floor(max(0, remaining) / CGFloat(open.count))
            let index = open.removeFirst()
            widths[index] = min(natural[index], share)
            remaining -= widths[index]
        }
        var x: CGFloat = 0
        for (index, chip) in chips.enumerated() {
            chip.frame = NSRect(x: x, y: 0, width: widths[index], height: Self.chipHeight)
            x += widths[index] + Self.spacing
        }
        heightConstraint.constant = chips.isEmpty ? 0 : Self.chipHeight
    }

    func chip(at index: Int) -> NSButton? { chips.indices.contains(index) ? chips[index] : nil }

    var chipFrames: [NSRect] { chips.map(\.frame) }
    /// Each chip's drawn content (dot through title end), in chip coordinates.
    var chipContentFrames: [NSRect] {
        chips.map { chip in
            guard let cell = chip.cell as? ChipCell else { return .zero }
            let layout = cell.contentLayout(in: chip.bounds)
            return layout.dot.map { $0.union(layout.title) } ?? layout.title
        }
    }

    @objc private func chipPressed(_ sender: NSButton) { chipSelected?(sender.tag) }
}

/// Draws a chip's optional working dot and its title inside fixed side
/// padding, centred; a borderless NSButton would draw them flush left.
final class ChipCell: NSButtonCell {
    static let padding: CGFloat = 10
    static let dotSize: CGFloat = 7
    static let dotSpace: CGFloat = 12
    var showsDot = false

    /// Where the dot and title are drawn inside `bounds`; also reported by
    /// `/ui` so tests can check the padding.
    func contentLayout(in bounds: NSRect) -> (dot: NSRect?, title: NSRect) {
        let inner = bounds.insetBy(dx: Self.padding, dy: 0)
        let size = attributedTitle.size()
        let dot = showsDot ? Self.dotSpace : 0
        let textWidth = min(ceil(size.width), inner.width - dot)
        var x = inner.minX + max(0, (inner.width - dot - textWidth) / 2)
        var dotRect: NSRect?
        if showsDot {
            dotRect = NSRect(x: x, y: bounds.midY - Self.dotSize / 2,
                             width: Self.dotSize, height: Self.dotSize)
            x += dot
        }
        let height = ceil(size.height)
        return (dotRect, NSRect(x: x, y: bounds.midY - height / 2,
                                width: textWidth, height: height))
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let layout = contentLayout(in: cellFrame)
        if let dot = layout.dot {
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        attributedTitle.draw(with: layout.title,
                             options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
