// Main AppKit controller for the floating reasoning HUD.

import AppKit
import Foundation

final class HUD: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private var scrollView: NSScrollView!
    private var feedView: FlippedView!
    private var feedStack: NSStackView!
    private var detailHeader: NSVisualEffectView!
    private var peekBar: NSVisualEffectView!
    private var fullMessageView: FullMessageView!
    private var peekSourceLabel: NSTextField!
    private var peekTicker: TickerView!
    private var peekControlsButton: NSButton!
    private var latestButton: NSButton!
    private var previousButton: NSButton!
    private var nextButton: NSButton!
    private var restartTickerButton: NSButton!
    private var positionLabel: NSTextField!
    private var positionButton: NSPopUpButton!
    private var expandButton: NSButton!
    private var eventCards: [EventCard] = []
    private var eventPreviews: [(source: String, text: String, kind: String)] = []
    private var systemCards: [EventCard] = []
    private var compactIndex = -1
    private var compactMode = true
    private var peekMode = true
    private var messageMode = false
    private var compactHeight: CGFloat = 210
    private var messageHeight: CGFloat = 300
    private let peekWidth: CGFloat = 460
    private let peekHeight: CGFloat = 98
    private let compactWidth: CGFloat = 560
    private var expandedHeight: CGFloat = 620
    private let expandedWidth: CGFloat = 700
    private var presentationKeys = Set<String>()
    private var unseenCount = 0
    private var tailers: [String: Tailer] = [:]
    private var picker: NSPopUpButton!
    private var status: NSTextField!
    private var sessions: [SessionInfo] = []
    private var pinned: String? = INITIAL_TRANSCRIPT // nil = watch all active
    private var lastScan = Date.distantPast
    private var lastPickerRefresh = Date.distantPast
    private var monitorsReady = false
    private var names: [String: String] = [:]
    private var knownOffsets: [String: UInt64] = [:]
    private var alertCount = 0
    private var operationState = OperationPresentationState()
    private let api = UIStateServer()
    private var apiEvents: [[String: Any]] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = ConstrainedPanel(
            contentRect: NSRect(x: 60, y: 140, width: 560, height: 210),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Thinkpeek"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.minSize = NSSize(width: 340, height: 62)
        panel.maxSize = NSSize(width: 560, height: 360)
        panel.setFrameAutosaveName("thinkpeek.main-window")
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = true

        let content = CompactInteractionView(
            frame: NSRect(x: 0, y: 0, width: compactWidth, height: compactHeight))
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.clicked = { [weak self] in self?.showCurrentMessage() }
        content.doubleClicked = { [weak self] in self?.applyPeekMode(false) }

        peekBar = NSVisualEffectView()
        peekBar.material = .headerView
        peekBar.blendingMode = .withinWindow
        peekBar.state = .active
        peekBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(peekBar)

        peekSourceLabel = NSTextField(labelWithString: "Thinkpeek")
        peekSourceLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        peekSourceLabel.textColor = .secondaryLabelColor
        peekSourceLabel.lineBreakMode = .byTruncatingMiddle
        peekSourceLabel.maximumNumberOfLines = 1
        peekSourceLabel.setContentCompressionResistancePriority(.defaultLow,
                                                                 for: .horizontal)

        peekTicker = TickerView()
        let savedSpeed = UserDefaults.standard.string(forKey: "tickerSpeed")
            .flatMap(TickerSpeed.init(rawValue:)) ?? .normal
        peekTicker.speed = savedSpeed
        peekTicker.text = "Watching Claude and Codex…"

        peekControlsButton = NSButton(
            image: NSImage(systemSymbolName: "slider.horizontal.3",
                           accessibilityDescription: "Open controls") ?? NSImage(),
            target: self, action: #selector(showControls(_:)))
        peekControlsButton.bezelStyle = .accessoryBarAction
        peekControlsButton.isBordered = false
        peekControlsButton.toolTip = "Open navigation and ticker settings"
        peekControlsButton.translatesAutoresizingMaskIntoConstraints = false
        peekBar.addSubview(peekControlsButton)

        let peekStack = NSStackView(views: [peekSourceLabel, peekTicker])
        peekStack.orientation = .vertical
        peekStack.alignment = .leading
        peekStack.spacing = 3
        peekStack.translatesAutoresizingMaskIntoConstraints = false
        peekStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        peekBar.addSubview(peekStack)

        fullMessageView = FullMessageView(frame: .zero)
        fullMessageView.closeRequested = { [weak self] in self?.applyPeekMode(true) }
        fullMessageView.controlsRequested = { [weak self] in self?.applyPeekMode(false) }
        content.addSubview(fullMessageView)

        detailHeader = NSVisualEffectView()
        detailHeader.material = .headerView
        detailHeader.blendingMode = .withinWindow
        detailHeader.state = .active
        detailHeader.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(detailHeader)

        picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.target = self
        picker.action = #selector(sessionPicked(_:))
        picker.font = .systemFont(ofSize: 14, weight: .semibold)
        detailHeader.addSubview(picker)

        status = NSTextField(labelWithString: "")
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailHeader.addSubview(status)

        latestButton = NSButton(title: "Latest ↓", target: self,
                                action: #selector(scrollToLatest(_:)))
        latestButton.bezelStyle = .rounded
        latestButton.controlSize = .small
        latestButton.translatesAutoresizingMaskIntoConstraints = false
        latestButton.setContentHuggingPriority(.required, for: .horizontal)
        latestButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        previousButton = NSButton(title: "‹", target: self, action: #selector(showPrevious(_:)))
        nextButton = NSButton(title: "›", target: self, action: #selector(showNext(_:)))
        for button in [previousButton!, nextButton!] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 17, weight: .semibold)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        }
        restartTickerButton = NSButton(title: "↤", target: self,
                                       action: #selector(restartTickerAtBeginning(_:)))
        restartTickerButton.bezelStyle = .rounded
        restartTickerButton.controlSize = .small
        restartTickerButton.font = .systemFont(ofSize: 15, weight: .semibold)
        restartTickerButton.toolTip = "Return to the beginning of this summary"
        restartTickerButton.setAccessibilityLabel("Restart summary ticker")
        restartTickerButton.translatesAutoresizingMaskIntoConstraints = false
        restartTickerButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        positionLabel = NSTextField(labelWithString: "—")
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.alignment = .center
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true

        expandButton = NSButton(title: "Show all", target: self,
                                action: #selector(toggleExpanded(_:)))
        expandButton.bezelStyle = .rounded
        expandButton.controlSize = .small
        latestButton.isHidden = true

        positionButton = NSPopUpButton(frame: .zero, pullsDown: true)
        positionButton.addItems(withTitles: ["", "Ticker: Slow", "Ticker: Normal",
                                              "Ticker: Fast", "Top Left", "Top Center",
                                              "Top Right", "Bottom Left", "Bottom Center",
                                              "Bottom Right"])
        positionButton.item(at: 0)?.image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: "Ticker and window settings")
        for (index, speed) in TickerSpeed.allCases.enumerated() {
            positionButton.item(at: index + 1)?.toolTip = "\(speed.title) ticker speed"
        }
        let positionSymbols = [
            (4, "arrow.up.left", "Top Left"),
            (5, "arrow.up", "Top Center"),
            (6, "arrow.up.right", "Top Right"),
            (7, "arrow.down.left", "Bottom Left"),
            (8, "arrow.down", "Bottom Center"),
            (9, "arrow.down.right", "Bottom Right"),
        ]
        for (index, symbol, description) in positionSymbols {
            guard let item = positionButton.item(at: index) else { continue }
            item.toolTip = description
            item.image = NSImage(systemSymbolName: symbol,
                                 accessibilityDescription: description)
        }
        positionButton.target = self
        positionButton.action = #selector(positionPicked(_:))
        positionButton.controlSize = .small
        positionButton.toolTip = "Ticker speed and window position"
        positionButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        updateSettingsMenuChecks(savedSpeed)

        let controls = NSStackView(views: [previousButton, positionLabel, nextButton,
                                           restartTickerButton,
                                           positionButton, expandButton, latestButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.setContentHuggingPriority(.required, for: .horizontal)
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailHeader.addSubview(controls)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.addSubview(scrollView)

        feedView = FlippedView(frame: .zero)
        feedView.translatesAutoresizingMaskIntoConstraints = false
        feedView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.documentView = feedView

        feedStack = NSStackView()
        feedStack.orientation = .vertical
        feedStack.alignment = .leading
        feedStack.spacing = 12
        feedStack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 24, right: 18)
        feedStack.translatesAutoresizingMaskIntoConstraints = false
        feedStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        feedView.addSubview(feedStack)

        NSLayoutConstraint.activate([
            peekBar.topAnchor.constraint(equalTo: content.topAnchor),
            peekBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            peekBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            peekBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            peekStack.leadingAnchor.constraint(equalTo: peekBar.leadingAnchor, constant: 14),
            peekStack.trailingAnchor.constraint(equalTo: peekControlsButton.leadingAnchor,
                                                 constant: -8),
            peekStack.centerYAnchor.constraint(equalTo: peekBar.centerYAnchor),
            peekSourceLabel.widthAnchor.constraint(equalTo: peekStack.widthAnchor),
            peekSourceLabel.heightAnchor.constraint(equalToConstant: 16),
            peekTicker.widthAnchor.constraint(equalTo: peekStack.widthAnchor),
            peekTicker.heightAnchor.constraint(equalToConstant: 26),
            peekControlsButton.trailingAnchor.constraint(equalTo: peekBar.trailingAnchor,
                                                          constant: -10),
            peekControlsButton.centerYAnchor.constraint(equalTo: peekBar.centerYAnchor),
            peekControlsButton.widthAnchor.constraint(equalToConstant: 28),
            peekControlsButton.heightAnchor.constraint(equalToConstant: 28),

            fullMessageView.topAnchor.constraint(equalTo: content.topAnchor),
            fullMessageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            fullMessageView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            fullMessageView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            detailHeader.topAnchor.constraint(equalTo: content.topAnchor),
            detailHeader.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            detailHeader.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailHeader.heightAnchor.constraint(equalToConstant: 74),

            picker.topAnchor.constraint(equalTo: detailHeader.topAnchor, constant: 10),
            picker.heightAnchor.constraint(equalToConstant: 30),
            picker.leadingAnchor.constraint(equalTo: detailHeader.leadingAnchor, constant: 14),
            picker.trailingAnchor.constraint(equalTo: controls.leadingAnchor, constant: -12),
            status.leadingAnchor.constraint(equalTo: picker.leadingAnchor, constant: 2),
            status.trailingAnchor.constraint(equalTo: controls.leadingAnchor, constant: -12),
            status.heightAnchor.constraint(equalToConstant: 16),
            status.bottomAnchor.constraint(equalTo: detailHeader.bottomAnchor, constant: -8),
            controls.trailingAnchor.constraint(equalTo: detailHeader.trailingAnchor, constant: -14),
            controls.centerYAnchor.constraint(equalTo: detailHeader.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: detailHeader.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            feedStack.topAnchor.constraint(equalTo: feedView.topAnchor),
            feedStack.leadingAnchor.constraint(equalTo: feedView.leadingAnchor),
            feedStack.trailingAnchor.constraint(equalTo: feedView.trailingAnchor),
            feedStack.bottomAnchor.constraint(equalTo: feedView.bottomAnchor),
            feedStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        panel.orderFrontRegardless()
        applyPeekMode(true, animated: false)

        knownOffsets = transcriptSizes()
        api.captureHandler = { [weak self] in self?.captureWindowPNG() }
        api.actionHandler = { [weak self] action in self?.handleAction(action) }
        api.start()
        refreshPicker()
        refreshStatus()
        addSystemCard("Watching active Claude and Codex sessions",
                      detail: "New reasoning summaries appear here automatically.")
        Timer.scheduledTimer(withTimeInterval: POLL, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Let AppKit present the first frame before any transcript backfill.
        // The repeating timer performs the first scan after POLL seconds.
    }

    private func publishAPI() {
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
        api.publish([
            "schemaVersion": 1,
            "ready": true,
            "windowTitle": panel.title,
            "selection": picker.titleOfSelectedItem ?? "",
            "status": status.stringValue,
            "externalAnalysisEnabled": driftStatus().ready,
            "analysisDestination": driftStatus().ready ? checkLabel() : NSNull(),
            "historyCount": BACKFILL == Int.max ? "all" : String(BACKFILL),
            "showEncrypted": SHOW_ENCRYPTED,
            "alwaysOnTop": panel.level == .floating,
            "windowWidth": Int(panel.frame.width),
            "windowHeight": Int(panel.frame.height),
            "windowX": Int(panel.frame.minX),
            "windowY": Int(panel.frame.minY),
            "fullyOnScreen": visibleFrame.map { NSContainsRect($0, panel.frame) } ?? false,
            "contentViewWidth": Int(panel.contentView?.bounds.width ?? 0),
            "scrollViewportWidth": Int(scrollView.contentView.frame.width),
            "scrollable": scrollView.hasVerticalScroller,
            "contentHeight": Int(feedView.bounds.height),
            "viewportHeight": Int(scrollView.contentView.bounds.height),
            "scrollY": Int(scrollView.contentView.bounds.minY),
            "contentRequiresScroll": !peekMode &&
                (messageMode ? fullMessageView.requiresScroll
                    : feedView.bounds.height > scrollView.contentView.bounds.height),
            "smartAutoscroll": true,
            "unseenCount": unseenCount,
            "cardCount": feedStack.arrangedSubviews.count,
            "visibleCardCount": (peekMode || messageMode)
                ? 0 : eventCards.filter { !$0.isHidden }.count,
            "compactMode": compactMode,
            "peekMode": peekMode,
            "messageMode": messageMode,
            "peekSource": peekSourceLabel?.stringValue ?? "",
            "peekText": peekTicker?.text ?? "",
            "tickerOverflowing": peekTicker?.isOverflowing ?? false,
            "tickerReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "tickerSpeed": peekTicker.speed.rawValue,
            "tickerPointsPerSecond": Int(peekTicker.speed.pointsPerSecond),
            "operationPending": operationState.operationPending,
            "pendingSource": operationState.latestPendingSource ?? NSNull(),
            "hoverDisclosure": false,
            "singleClickOpensMessage": true,
            "doubleClickOpensControls": true,
            "currentIndex": compactIndex,
            "navigableCount": eventCards.count,
            "uiStyle": peekMode ? "single-line-ticker"
                : (messageMode ? "full-message"
                    : (compactMode ? "compact-controls" : "expanded-card-feed")),
            "events": Array(apiEvents.suffix(250)),
        ])
    }

    func windowDidResize(_ notification: Notification) {
        guard panel != nil else { return }
        if peekMode {
            publishAPI()
            return
        } else if messageMode {
            messageHeight = panel.frame.height
        } else if compactMode {
            compactHeight = panel.frame.height
        } else {
            expandedHeight = panel.frame.height
        }
        publishAPI()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        publishAPI()
    }

    func windowDidMove(_ notification: Notification) {
        publishAPI()
    }

    private func resizePanel(to height: CGFloat, width: CGFloat? = nil,
                             animated: Bool = true) {
        var frame = panel.frame
        var placement: WindowPlacement?
        var placementBounds: NSRect?
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            let captured = WindowPlacement(frame: frame, within: visible)
            placement = captured
            placementBounds = visible
            frame = captured.frame(
                for: NSSize(width: width ?? frame.width, height: height), within: visible)
        } else {
            let center = NSPoint(x: frame.midX, y: frame.midY)
            frame.size.height = height
            if let width { frame.size.width = width }
            frame.origin.x = center.x - frame.width / 2
            frame.origin.y = center.y - frame.height / 2
        }
        panel.setFrame(frame, display: true, animate: animated)
        guard let placement, let placementBounds else { return }

        let restorePlacement = { [weak self] in
            guard let self else { return }
            let corrected = placement.frame(for: self.panel.frame.size,
                                            within: placementBounds)
            if abs(corrected.minX - self.panel.frame.minX) > 0.5 ||
               abs(corrected.minY - self.panel.frame.minY) > 0.5 {
                self.panel.setFrameOrigin(corrected.origin)
            }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        restorePlacement()
        if !animated { DispatchQueue.main.async(execute: restorePlacement) }
    }

    /// AppKit may resize a window immediately when minSize/maxSize stop
    /// containing its current frame. Keep both the current and target sizes
    /// legal during the transition, perform our edge-aware resize, then install
    /// the final mode constraints.
    private func transitionPanel(to height: CGFloat, width: CGFloat,
                                 minSize: NSSize, maxSize: NSSize,
                                 animated: Bool = true) {
        let current = panel.frame.size
        panel.minSize = NSSize(width: min(current.width, min(width, minSize.width)),
                               height: min(current.height, min(height, minSize.height)))
        panel.maxSize = NSSize(width: max(current.width, max(width, maxSize.width)),
                               height: max(current.height, max(height, maxSize.height)))
        resizePanel(to: height, width: width, animated: animated)
        panel.minSize = minSize
        panel.maxSize = maxSize
    }

    private func handleAction(_ action: String) {
        switch action {
        case "previous": showPrevious(nil)
        case "next": showNext(nil)
        case "toggle-expanded": toggleExpanded(nil)
        case "restart-ticker": restartTickerAtBeginning(nil)
        case "message": showCurrentMessage()
        case "controls": applyPeekMode(false)
        case let value where value.hasPrefix("speed/"):
            setTickerSpeed(String(value.dropFirst("speed/".count)))
        case "reveal":
            applyPeekMode(false)
        case "hide":
            applyPeekMode(true)
        case let value where value.hasPrefix("position/"):
            movePanel(to: String(value.dropFirst("position/".count)))
        default: break
        }
    }

    @objc private func positionPicked(_ sender: NSPopUpButton) {
        let presets = ["top-left", "top-center", "top-right", "bottom-left",
                       "bottom-center", "bottom-right"]
        let selected = sender.indexOfSelectedItem
        if (1...3).contains(selected) {
            setTickerSpeed(TickerSpeed.allCases[selected - 1].rawValue)
        } else if (4...9).contains(selected) {
            movePanel(to: presets[selected - 4])
        }
        sender.selectItem(at: 0)
    }

    private func setTickerSpeed(_ rawValue: String) {
        guard let speed = TickerSpeed(rawValue: rawValue) else { return }
        peekTicker.speed = speed
        updateSettingsMenuChecks(speed)
        UserDefaults.standard.set(speed.rawValue, forKey: "tickerSpeed")
        publishAPI()
    }

    private func updateSettingsMenuChecks(_ speed: TickerSpeed) {
        for (index, candidate) in TickerSpeed.allCases.enumerated() {
            positionButton.item(at: index + 1)?.state = candidate == speed ? .on : .off
        }
    }

    private func movePanel(to preset: String) {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let inset: CGFloat = 12
        var frame = panel.frame
        if preset.hasSuffix("left") { frame.origin.x = visible.minX + inset }
        else if preset.hasSuffix("right") { frame.origin.x = visible.maxX - frame.width - inset }
        else { frame.origin.x = visible.midX - frame.width / 2 }
        if preset.hasPrefix("top") { frame.origin.y = visible.maxY - frame.height - inset }
        else { frame.origin.y = visible.minY + inset }
        panel.setFrame(panel.constrainFrameRect(frame, to: panel.screen), display: true)
        publishAPI()
    }

    private func applyPeekMode(_ peek: Bool, animated: Bool = false) {
        peekMode = peek
        messageMode = false
        (panel.contentView as? CompactInteractionView)?.dragOnly = peek
        peekBar.isHidden = !peek
        fullMessageView.isHidden = true
        detailHeader.isHidden = peek
        scrollView.isHidden = peek
        peekTicker.setActive(peek)
        if peek {
            transitionPanel(to: peekHeight, width: peekWidth,
                            minSize: NSSize(width: 340, height: 62),
                            maxSize: NSSize(width: peekWidth, height: peekHeight),
                            animated: animated)
        } else {
            let minSize = compactMode ? NSSize(width: 430, height: 190)
                : NSSize(width: 520, height: 360)
            let maxSize: NSSize
            if compactMode {
                maxSize = NSSize(width: compactWidth, height: 360)
            } else if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                maxSize = NSSize(width: min(expandedWidth, visible.width),
                                 height: visible.height)
            } else {
                maxSize = NSSize(width: expandedWidth, height: expandedHeight)
            }
            transitionPanel(to: compactMode ? max(190, compactHeight)
                                            : max(520, expandedHeight),
                            width: compactMode ? compactWidth : expandedWidth,
                            minSize: minSize, maxSize: maxSize, animated: animated)
        }
        publishAPI()
    }

    private func showCurrentMessage() {
        guard compactIndex >= 0, compactIndex < eventPreviews.count else { return }
        let preview = eventPreviews[compactIndex]
        fullMessageView.show(source: preview.source, text: preview.text, kind: preview.kind)
        peekMode = false
        messageMode = true
        (panel.contentView as? CompactInteractionView)?.dragOnly = false
        peekBar.isHidden = true
        fullMessageView.isHidden = false
        detailHeader.isHidden = true
        scrollView.isHidden = true
        peekTicker.setActive(false)
        transitionPanel(to: max(220, messageHeight), width: compactWidth,
                        minSize: NSSize(width: 430, height: 180),
                        maxSize: NSSize(width: compactWidth, height: 520))
        publishAPI()
    }

    @objc private func showControls(_ sender: Any?) { applyPeekMode(false) }

    @objc private func showPrevious(_ sender: Any?) {
        guard compactMode, compactIndex > 0 else { return }
        compactIndex -= 1
        updateCardVisibility()
    }

    @objc private func showNext(_ sender: Any?) {
        guard compactMode, compactIndex + 1 < eventCards.count else { return }
        compactIndex += 1
        updateCardVisibility()
    }

    @objc private func restartTickerAtBeginning(_ sender: Any?) {
        guard compactMode else { return }
        peekTicker.restart()
        if !peekMode { applyPeekMode(true) }
    }

    @objc private func toggleExpanded(_ sender: Any?) {
        if peekMode || messageMode { applyPeekMode(false) }
        if compactMode {
            compactHeight = panel.frame.height
            compactMode = false
            let maxSize: NSSize
            if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                maxSize = NSSize(width: min(expandedWidth, visible.width),
                                 height: visible.height)
            } else {
                maxSize = NSSize(width: expandedWidth, height: expandedHeight)
            }
            transitionPanel(to: max(520, expandedHeight), width: expandedWidth,
                            minSize: NSSize(width: 520, height: 360),
                            maxSize: maxSize)
        } else {
            expandedHeight = panel.frame.height
            compactMode = true
            compactIndex = max(0, eventCards.count - 1)
            transitionPanel(to: min(320, max(190, compactHeight)), width: compactWidth,
                            minSize: NSSize(width: 430, height: 190),
                            maxSize: NSSize(width: compactWidth, height: 360))
        }
        updateCardVisibility()
    }

    private func updateCardVisibility() {
        if compactMode {
            if !eventCards.isEmpty {
                compactIndex = min(max(0, compactIndex), eventCards.count - 1)
            }
            for (index, card) in eventCards.enumerated() {
                card.isHidden = index != compactIndex
            }
            for card in systemCards { card.isHidden = !eventCards.isEmpty }
            positionLabel.stringValue = eventCards.isEmpty
                ? "—" : "\(compactIndex + 1) / \(eventCards.count)"
            if compactIndex >= 0 && compactIndex < eventPreviews.count {
                let preview = eventPreviews[compactIndex]
                peekSourceLabel.stringValue = preview.source
                peekSourceLabel.toolTip = preview.source
                peekTicker.text = normalizedTickerText(preview.text)
                if messageMode {
                    fullMessageView.show(source: preview.source, text: preview.text,
                                         kind: preview.kind)
                }
            }
            previousButton.isEnabled = compactIndex > 0
            nextButton.isEnabled = compactIndex >= 0 && compactIndex + 1 < eventCards.count
            expandButton.title = "Show all"
            restartTickerButton.isEnabled = !eventCards.isEmpty
            latestButton.isHidden = true
        } else {
            for card in eventCards { card.isHidden = false }
            for card in systemCards { card.isHidden = !eventCards.isEmpty }
            positionLabel.stringValue = "All \(eventCards.count)"
            previousButton.isEnabled = false
            nextButton.isEnabled = false
            expandButton.title = "Collapse"
            restartTickerButton.isEnabled = false
            latestButton.isHidden = false
        }
        feedView.layoutSubtreeIfNeeded()
        if compactMode {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        publishAPI()
    }

    private func captureWindowPNG() -> Data? {
        guard let view = panel.contentView else { return nil }
        let scale = panel.backingScaleFactor
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(view.bounds.width * scale)),
            pixelsHigh: max(1, Int(view.bounds.height * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private func displayTime(_ timestamp: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: timestamp) else { return timestamp }
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    private func nearBottom() -> Bool {
        let visible = scrollView.contentView.bounds
        return feedView.bounds.maxY - visible.maxY < 64
    }

    @objc private func scrollToLatest(_ sender: Any?) {
        feedView.layoutSubtreeIfNeeded()
        // A compact carousel shows one card, so it must open at that card's
        // beginning. Scrolling to the feed bottom hid its header and body as
        // soon as a footer appeared. Expanded mode still follows the latest.
        let y = compactMode
            ? 0
            : max(0, feedView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        unseenCount = 0
        latestButton.title = "Latest ↓"
        publishAPI()
    }

    @discardableResult
    private func addCard(source: String, event: UIEvent,
                         deferScrollAndLayout: Bool = false,
                         navigable: Bool = true) -> EventCard {
        let follow = !deferScrollAndLayout &&
            (nearBottom() || feedStack.arrangedSubviews.isEmpty)
        let card = EventCard(source: source, time: displayTime(event.timestamp), event: event)
        card.contentChanged = { [weak self, weak card] in
            guard let self, let card else { return }
            self.cardContentDidChange(card)
        }
        feedStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: feedStack.widthAnchor,
                                    constant: -feedStack.edgeInsets.left - feedStack.edgeInsets.right)
            .isActive = true
        if navigable {
            let wasFollowingLatest = eventCards.isEmpty || compactIndex == eventCards.count - 1
            eventCards.append(card)
            eventPreviews.append((source: source, text: event.text, kind: event.kind))
            if wasFollowingLatest { compactIndex = eventCards.count - 1 }
        } else {
            systemCards.append(card)
        }
        updateCardVisibility()
        if deferScrollAndLayout { return card }
        feedView.layoutSubtreeIfNeeded()
        if follow {
            DispatchQueue.main.async { [weak self] in self?.scrollToLatest(nil) }
        } else {
            unseenCount += 1
            latestButton.title = "\(unseenCount) new ↓"
        }
        return card
    }

    private func cardContentDidChange(_ card: EventCard) {
        feedView.layoutSubtreeIfNeeded()
        if compactMode,
           compactIndex >= 0,
           compactIndex < eventCards.count,
           eventCards[compactIndex] === card {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        publishAPI()
    }

    private func addSystemCard(_ title: String, detail: String) {
        let text = detail.isEmpty ? title : "\(title)\n\(detail)"
        let event = UIEvent(timestamp: ISO8601DateFormatter().string(from: Date()),
                            kind: "activity", text: text, readableAnalysis: false)
        _ = addCard(source: "Thinkpeek", event: event, navigable: false)
    }

    private func clearFeed() {
        for view in feedStack.arrangedSubviews {
            feedStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        unseenCount = 0
        latestButton.title = "Latest ↓"
        apiEvents.removeAll()
        eventCards.removeAll()
        eventPreviews.removeAll()
        systemCards.removeAll()
        presentationKeys.removeAll()
        operationState.resetPending()
        compactIndex = -1
        updateCardVisibility()
    }

    /// Operation-start records are progress signals, not useful content. Keep
    /// the last readable summary in the card/peek/history and signal work only
    /// through the window title and state API.
    private func operationStarted(source: String) {
        operationState.operationStarted(source: source)
        updateWindowTitle()
        publishAPI()
    }

    private func readableContentArrived(source: String) {
        operationState.readableContentArrived(source: source)
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        panel.title = operationState.windowTitle
    }

    // MARK: session picker

    @objc private func sessionPicked(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        pinned = (i <= 0 || i - 1 >= sessions.count) ? nil : sessions[i - 1].path
        for (path, tailer) in tailers { knownOffsets[path] = tailer.resumeOffset }
        tailers.removeAll()
        clearFeed()
        if let pinned {
            tailers[pinned] = Tailer(path: pinned)
            let name = sourceName(for: pinned)
            addSystemCard(name, detail: "Pinned session · sub-agents included")
            panel.title = name
            monitorsReady = true
        } else {
            addSystemCard("Auto mode", detail: "Watching all active sessions and sub-agents")
            monitorsReady = false
        }
        lastScan = .distantPast
    }

    private func refreshPicker() {
        sessions = recentSessions()
        let keep = pinned
        picker.removeAllItems()
        picker.addItem(withTitle: "Auto — all active sessions")
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        for s in sessions {
            picker.addItem(withTitle: "\(fmt.string(from: s.modified))  \(s.project) · \(s.title)")
            names[s.path] = s.title
        }
        if let keep, let i = sessions.firstIndex(where: { sameTranscript($0.path, keep) }) {
            picker.selectItem(at: i + 1)
        } else {
            picker.selectItem(at: 0)
        }
    }

    private func refreshStatus() {
        let d = driftStatus()
        status.stringValue = d.ready ? "drift check: \(d.detail)" : "drift check OFF — \(d.detail)"
        status.textColor = d.ready ? .secondaryLabelColor : .systemPurple
    }

    private func sourceName(for path: String) -> String {
        let root = rootSessionPath(for: path)
        let rootID = sessionID(for: root)
        let rawTitle = names[root] ?? sessionTitle(of: root) ?? rootID
        names[root] = rawTitle
        let title = "\(platformName(for: root)) · \(rawTitle)"
        guard root != path else { return title }
        let agent = String((path as NSString).lastPathComponent
            .replacingOccurrences(of: "agent-", with: "").prefix(8))
        return "\(title) · agent \(agent)"
    }

    /// Keep a tailer for every recently active transcript. On the first scan we
    /// start old files at EOF (apart from three blocks of useful context). Files
    /// discovered later resume from the launch snapshot, so complete or partial
    /// reasoning written between discovery scans cannot be missed.
    private func refreshMonitors() {
        var wanted = activeTranscriptPaths()
        if let pinned {
            wanted = wanted.filter { sameTranscript(rootSessionPath(for: $0), pinned) }
            if !wanted.contains(where: { sameTranscript($0, pinned) }) { wanted.append(pinned) }
        }
        let wantedSet = Set(wanted)
        for path in tailers.keys.filter({ !wantedSet.contains($0) }) {
            knownOffsets[path] = tailers[path]?.resumeOffset
            tailers.removeValue(forKey: path)
        }

        for path in wanted where tailers[path] == nil {
            if !monitorsReady {
                // Read a few extra summaries so presentation deduplication can
                // still deliver the configured number of unique history cards.
                let scanLimit = BACKFILL == Int.max ? Int.max
                    : (BACKFILL >= 13 ? 100 : BACKFILL * 8)
                tailers[path] = Tailer(path: path, backfill: scanLimit)
            } else {
                // Existing files resume from the launch/removal snapshot. Brand
                // new files start at byte zero. Both paths preserve partial lines.
                tailers[path] = Tailer(path: path, backfill: 0,
                    startOffset: knownOffsets[path] ?? 0)
            }
        }
        monitorsReady = true
    }

    private func showAlert(_ hits: [Fired], _ ms: Double, card: EventCard) {
        let reasons = hits.map { hit in
            hit.why.isEmpty ? hit.trigger : "\(hit.trigger) — \(hit.why)"
        }.joined(separator: "\n")
        card.setAlert("⚠ Drift detected · \(Int(ms)) ms\n\(reasons)")
        NSSound.beep()
        alertCount += 1
        panel.title = "⚠ AI reasoning — \(alertCount)"
        apiEvents.append([
            "kind": "drift-alert", "text": hits.map(\.trigger).joined(separator: "; "),
            "latencyMs": Int(ms),
        ])
        publishAPI()
    }

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(lastPickerRefresh) > 5 {
            lastPickerRefresh = now
            refreshPicker()
            refreshStatus()
        }
        if now.timeIntervalSince(lastScan) > RESCAN {
            lastScan = now
            refreshMonitors()
        }

        var arrived: [(path: String, block: Block)] = []
        for (path, tailer) in tailers {
            arrived += tailer.drain().map { (path, $0) }
        }
        if !SHOW_ENCRYPTED {
            arrived.removeAll { $0.block.sealed }
        }
        arrived.sort { $0.block.ts < $1.block.ts }
        arrived.removeAll { event in
            let normalized = event.block.text
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let timestampPart = event.block.kind == .activity ? "\u{1f}" + event.block.ts : ""
            let key = sourceName(for: event.path) + "\u{1f}" + normalized + timestampPart
            if presentationKeys.contains(key) { return true }
            presentationKeys.insert(key)
            return false
        }
        if BACKFILL != Int.max {
            let history = arrived.filter {
                $0.block.backfilled && $0.block.kind != .activity
            }
                .sorted { $0.block.ts < $1.block.ts }
            let live = arrived.filter { !$0.block.backfilled }
            arrived = live + Array(history.suffix(BACKFILL))
        } else {
            // Old operation-start records are neither content nor current status.
            arrived.removeAll { $0.block.backfilled && $0.block.kind == .activity }
        }
        let isInitialHistoryBatch = arrived.count > 20 && feedStack.arrangedSubviews.count <= 1
        for event in arrived {
            let block = event.block
            let source = sourceName(for: event.path)
            let ui = uiEvent(for: block)
            if ui.kind == "activity" {
                operationStarted(source: source)
                continue
            }
            readableContentArrived(source: source)
            var apiItem = ui.json
            apiItem["source"] = source
            apiEvents.append(apiItem)
            let card = addCard(source: source, event: ui,
                               deferScrollAndLayout: isInitialHistoryBatch)
            if ui.kind == "omitted-analysis" {
                continue
            }
            // Backfilled history is not re-checked: it would alert on reasoning
            // the user has already seen, on every launch.
            guard !block.backfilled else {
                card.setFooter("History · already seen")
                continue
            }

            let state = driftStatus()
            guard state.ready else {
                card.setFooter("Local display only · \(state.detail)")
                continue
            }
            let destination = checkLabel()
            card.setFooter("Sending \(block.text.count) characters to \(destination)…")
            apiEvents.append([
                "kind": "drift-request-started", "text": "sent for analysis",
                "destination": destination,
            ])
            publishAPI()
            checkDrift(block.text) { [weak self] outcome, ms in
                guard let self else { return }
                switch outcome {
                case .scored(let hits, let provider) where hits.isEmpty:
                    card.setFooter("✓ \(provider) checked · no drift · \(Int(ms)) ms",
                                   color: .systemGreen)
                    self.apiEvents.append([
                        "kind": "drift-clean", "text": "no drift", "provider": provider,
                        "latencyMs": Int(ms),
                    ])
                    self.publishAPI()
                case .scored(let hits, _):
                    self.showAlert(hits, ms, card: card)
                case .failed(let message):
                    card.setFooter("AI check failed · \(message) · \(Int(ms)) ms",
                                   color: .systemRed)
                    self.apiEvents.append([
                        "kind": "drift-error", "text": message, "latencyMs": Int(ms),
                    ])
                    self.publishAPI()
                }
            }
        }
        if isInitialHistoryBatch {
            feedView.layoutSubtreeIfNeeded()
            scrollToLatest(nil)
        }
        publishAPI()
    }
}
