// Dedicated full-text presentation. It intentionally contains no history or
// settings controls, so reading a summary never mutates the navigation UI.

import AppKit

final class FullMessageView: NSVisualEffectView {
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
    var controlsRequested: (() -> Void)?
    var tabSelected: ((Int) -> Void)?
    var jumpToLatestRequested: (() -> Void)?
    /// One tab per recent session plus All; empty hides the row.
    private let tabs = NSSegmentedControl(labels: [], trackingMode: .selectOne,
                                          target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let jumpButton = NSButton(title: "Jump to latest ↑", target: nil, action: nil)
    private var scrollTopToHeader: NSLayoutConstraint!
    private var scrollTopToStatus: NSLayoutConstraint!
    var tabTitles: [String] { (0..<tabs.segmentCount).map { tabs.label(forSegment: $0) ?? "" } }
    var selectedTab: Int { tabs.selectedSegment }
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
            image: NSImage(systemSymbolName: "rectangle.grid.1x2",
                           accessibilityDescription: "Show controls") ?? NSImage(),
            target: self, action: #selector(showControls(_:)))
        controlsButton.bezelStyle = .accessoryBarAction
        controlsButton.isBordered = false
        controlsButton.controlSize = .small
        controlsButton.imagePosition = .imageOnly
        controlsButton.toolTip = "Show navigation and history controls"
        controlsButton.setAccessibilityLabel("Show navigation and history controls")
        controlsButton.translatesAutoresizingMaskIntoConstraints = false
        controlsButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        addSubview(controlsButton)

        exitControls.closeRequested = { [weak self] in self?.closeRequested?() }
        addSubview(exitControls)

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

        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        tabs.controlSize = .small
        tabs.segmentDistribution = .fillEqually
        tabs.setAccessibilityLabel("Sessions")
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.isHidden = true
        addSubview(tabs)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
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
            tabs.topAnchor.constraint(equalTo: exitControls.bottomAnchor, constant: 8),
            tabs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 7),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            jumpButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            jumpButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: jumpButton.leadingAnchor,
                                                  constant: -8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        scrollTopToHeader = scrollView.topAnchor.constraint(
            equalTo: exitControls.bottomAnchor, constant: 10)
        scrollTopToStatus = scrollView.topAnchor.constraint(
            equalTo: statusLabel.bottomAnchor, constant: 4)
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

    /// Session tabs (titles already include any "N new" count) and the
    /// Live / Paused status line. Empty titles hide both rows.
    func setSessions(_ titles: [String], selected: Int, status: String,
                     live: Bool, showJump: Bool) {
        let visible = !titles.isEmpty
        tabs.segmentCount = titles.count
        for (index, title) in titles.enumerated() {
            tabs.setLabel(title, forSegment: index)
            tabs.setToolTip(title, forSegment: index)
        }
        if titles.indices.contains(selected) { tabs.selectedSegment = selected }
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

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        tabSelected?(sender.selectedSegment)
    }

    @objc private func jumpToLatest(_ sender: Any?) { jumpToLatestRequested?() }

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
        let sessionRows: CGFloat = tabs.isHidden ? 0 : 50
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

    @objc private func showControls(_ sender: Any?) { controlsRequested?() }
}
