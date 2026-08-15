// Main AppKit controller for the floating reasoning HUD.

import AppKit
import Foundation
import QuartzCore

func controlsExpansionTitle(compactMode: Bool) -> String? {
    compactMode ? "Show all" : nil
}

enum MessageEvaluationState {
    case pending
    case clear
    case alert(EvaluationDecision)
    case failed(String)
}

final class MessagePreview {
    let source: String
    let text: String
    let kind: String
    var evaluation: MessageEvaluationState = .pending

    init(source: String, text: String, kind: String) {
        self.source = source
        self.text = text
        self.kind = kind
    }

    var tickerText: String {
        switch evaluation {
        case .alert(let decision):
            return "⚠ \(decision.reason) — \(text)"
        case .failed:
            return "⛔ Thinkpeek check failed — \(text)"
        default:
            return text
        }
    }

    var displaySource: String {
        switch evaluation {
        case .alert:
            return "Thinkpeek · Warning"
        case .failed:
            return "Thinkpeek · Check error"
        default:
            return source
        }
    }

    var readerTone: MessageReaderTone {
        switch evaluation {
        case .alert: return .warning
        case .failed: return .error
        default: return .normal
        }
    }

    var detailText: String {
        switch evaluation {
        case .alert(let decision):
            let proof = decision.evidence.isEmpty ? "" : "\nEvidence: \(decision.evidence)"
            return "⚠ **WARNING**\n\(decision.reason)\(proof)\n\n" +
                "Triggered by \(source):\n\(text)"
        case .failed(let message):
            return "⛔ **THINKPEEK CHECK ERROR**\nThe checker could not evaluate this item.\n" +
                "\(message)\n\nOriginal item from \(source):\n\(text)"
        default:
            return text
        }
    }
}

final class HUD: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private var scrollView: NSScrollView!
    private var feedView: FlippedView!
    private var feedStack: NSStackView!
    private var detailHeader: NSVisualEffectView!
    private var detailHeaderLayout: DetailHeaderLayout!
    private var detailExitControls: DetailExitControls!
    private var peekBar: NSVisualEffectView!
    private var tickerBackgroundView: TickerBackgroundView!
    private var tickerBackgroundColor: NSColor?
    private var fullMessageView: FullMessageView!
    private var peekProviderIcon: ProviderIconView!
    private var peekSourceLabel: NSTextField!
    private var peekTicker: TickerView!
    private var peekCornerControls: TickerCornerControls!
    private var peekPrimaryActions: TickerPrimaryActions!
    private var peekToolbar: NSStackView!
    private var latestButton: NSButton!
    private var previousButton: NSButton!
    private var nextButton: NSButton!
    private var restartTickerButton: NSButton!
    private var positionLabel: NSTextField!
    private var positionButton: NSPopUpButton!
    private var tickerSettingsMenu: TickerSettingsMenu!
    private var checkRulesEditor: CheckRulesEditor?
    private var expandButton: NSButton!
    private var eventCards: [EventCard] = []
    private var eventPreviews: [MessagePreview] = []
    private var systemCards: [EventCard] = []
    private var compactIndex = -1
    private var compactMode = true
    private var peekMode = true
    private var messageMode = false
    private var messageReaderSnapshot: MessageReaderSnapshot?
    private let peekWidth: CGFloat = 460
    private let peekHeight: CGFloat = 70
    private var compactWidth = CompactWindowSizing.savedWidth()
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
    private let outsideClickMonitor = OutsideClickMonitor()
    private var previouslyActiveApplication: NSRunningApplication?
    private var apiEvents: [[String: Any]] = []
    private var discardedEmptySummaryCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = ConstrainedPanel(
            contentRect: NSRect(x: 60, y: 140, width: 560, height: 210),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Thinkpeek"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.minSize = NSSize(width: 340, height: 54)
        panel.maxSize = NSSize(width: 560, height: 360)
        panel.setFrameAutosaveName("thinkpeek.main-window")
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = true
        (panel as? ConstrainedPanel)?.escapeRequested = { [weak self] in
            guard let self, !self.peekMode else { return }
            self.dismissDetailsToTicker()
        }

        let content = CompactInteractionView(
            frame: NSRect(x: 0, y: 0, width: compactWidth, height: 210))
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.layer?.cornerRadius = 14
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        content.clicked = { [weak self] in self?.showCurrentMessage() }
        content.doubleClicked = { [weak self] in self?.applyPeekMode(false) }

        peekBar = NSVisualEffectView()
        peekBar.material = .headerView
        peekBar.blendingMode = .withinWindow
        peekBar.state = .active
        peekBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(peekBar)

        tickerBackgroundView = TickerBackgroundView()
        tickerBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        peekBar.addSubview(tickerBackgroundView)

        peekProviderIcon = ProviderIconView(frame: .zero)
        peekProviderIcon.translatesAutoresizingMaskIntoConstraints = false

        peekSourceLabel = NSTextField(labelWithString: "Thinkpeek")
        peekSourceLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        peekSourceLabel.textColor = .secondaryLabelColor
        peekSourceLabel.lineBreakMode = .byTruncatingMiddle
        peekSourceLabel.maximumNumberOfLines = 1
        peekSourceLabel.translatesAutoresizingMaskIntoConstraints = false
        peekSourceLabel.setContentCompressionResistancePriority(.defaultLow,
                                                                 for: .horizontal)

        peekTicker = TickerView()
        peekTicker.translatesAutoresizingMaskIntoConstraints = false
        let savedSpeed = UserDefaults.standard.string(forKey: "tickerSpeed")
            .flatMap(TickerSpeed.init(rawValue:)) ?? .normal
        peekTicker.speed = savedSpeed
        peekTicker.text = "Watching Claude and Codex…"

        peekCornerControls = TickerCornerControls(frame: .zero)
        peekCornerControls.cornerRequested = { [weak self] corner in
            self?.movePanel(toCorner: corner)
        }
        peekPrimaryActions = TickerPrimaryActions(frame: .zero)
        peekPrimaryActions.checkRulesRequested = { [weak self] in
            self?.showCheckRulesEditor()
        }
        peekPrimaryActions.controlsRequested = { [weak self] in
            self?.applyPeekMode(false)
        }
        peekToolbar = NSStackView(views: [peekCornerControls, peekPrimaryActions])
        peekToolbar.orientation = .horizontal
        peekToolbar.alignment = .centerY
        peekToolbar.spacing = 2
        peekToolbar.translatesAutoresizingMaskIntoConstraints = false
        peekToolbar.setContentHuggingPriority(.required, for: .horizontal)
        peekToolbar.setContentCompressionResistancePriority(.required, for: .horizontal)
        peekToolbar.widthAnchor.constraint(equalToConstant: 140).isActive = true
        applyTickerBackground(TickerBackgroundPreference.load())
        peekBar.addSubview(peekProviderIcon)
        peekBar.addSubview(peekSourceLabel)
        peekBar.addSubview(peekTicker)
        // Keep interactive controls above every text/image layer. AppKit's cached
        // rendering can otherwise omit them after a provider/source transition.
        peekBar.addSubview(peekToolbar)

        fullMessageView = FullMessageView(frame: .zero)
        fullMessageView.closeRequested = { [weak self] in
            self?.dismissDetailsToTicker()
        }
        fullMessageView.controlsRequested = { [weak self] in
            self?.showControlsFromMessageReader()
        }
        fullMessageView.quitRequested = { [weak self] in self?.quitApplication() }
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
        picker.setAccessibilityLabel("Monitored session")
        detailHeader.addSubview(picker)

        status = NSTextField(labelWithString: "")
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.setAccessibilityLabel("Drift check status")
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.isHidden = true
        detailHeader.addSubview(status)

        detailExitControls = DetailExitControls(frame: .zero)
        detailExitControls.closeRequested = { [weak self] in
            self?.dismissDetailsToTicker()
        }
        detailExitControls.quitRequested = { [weak self] in
            self?.quitApplication()
        }
        detailHeader.addSubview(detailExitControls)

        latestButton = NSButton(title: "Latest ↓", target: self,
                                action: #selector(scrollToLatest(_:)))
        latestButton.bezelStyle = .rounded
        latestButton.controlSize = .small
        latestButton.translatesAutoresizingMaskIntoConstraints = false
        latestButton.setContentHuggingPriority(.required, for: .horizontal)
        latestButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        latestButton.toolTip = "Scroll to the latest history item"
        latestButton.setAccessibilityLabel("Scroll to latest history item")
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        previousButton = NSButton(title: "", target: self, action: #selector(showPrevious(_:)))
        nextButton = NSButton(title: "", target: self, action: #selector(showNext(_:)))
        previousButton.image = NSImage(systemSymbolName: "chevron.left",
                                       accessibilityDescription: "Previous message")
        nextButton.image = NSImage(systemSymbolName: "chevron.right",
                                   accessibilityDescription: "Next message")
        previousButton.toolTip = "Previous message"
        previousButton.setAccessibilityLabel("Previous message")
        nextButton.toolTip = "Next message"
        nextButton.setAccessibilityLabel("Next message")
        for button in [previousButton!, nextButton!] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.imagePosition = .imageOnly
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        }
        restartTickerButton = NSButton(title: "", target: self,
                                       action: #selector(restartTickerAtBeginning(_:)))
        restartTickerButton.bezelStyle = .rounded
        restartTickerButton.controlSize = .small
        restartTickerButton.image = NSImage(systemSymbolName: "backward.end",
                                             accessibilityDescription: "Restart summary")
        restartTickerButton.imagePosition = .imageOnly
        restartTickerButton.toolTip = "Return to the beginning of this summary"
        restartTickerButton.setAccessibilityLabel("Restart summary ticker")
        restartTickerButton.translatesAutoresizingMaskIntoConstraints = false
        restartTickerButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        positionLabel = NSTextField(labelWithString: "—")
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.alignment = .center
        positionLabel.setAccessibilityLabel("Current message position")
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true

        expandButton = NSButton(title: "Show all", target: self,
                                action: #selector(toggleExpanded(_:)))
        expandButton.bezelStyle = .rounded
        expandButton.controlSize = .small
        expandButton.title = ""
        expandButton.image = NSImage(systemSymbolName: "rectangle.stack",
                                     accessibilityDescription: "Show message history")
        expandButton.imagePosition = .imageOnly
        expandButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        expandButton.toolTip = "Show complete message history"
        expandButton.setAccessibilityLabel("Show complete message history")
        latestButton.isHidden = true

        positionButton = NSPopUpButton(frame: .zero, pullsDown: true)
        tickerSettingsMenu = TickerSettingsMenu()
        tickerSettingsMenu.speedRequested = { [weak self] speed in
            self?.setTickerSpeed(speed.rawValue)
        }
        tickerSettingsMenu.widthRequested = { [weak self] width in
            self?.setCompactWidth(width)
        }
        tickerSettingsMenu.positionRequested = { [weak self] preset in
            self?.movePanel(to: preset)
        }
        tickerSettingsMenu.backgroundRequested = { [weak self] in
            self?.showTickerBackgroundPicker(nil)
        }
        tickerSettingsMenu.systemBackgroundRequested = { [weak self] in
            self?.setTickerBackground(nil)
        }
        tickerSettingsMenu.checkRulesRequested = { [weak self] in
            self?.showCheckRulesEditor()
        }
        tickerSettingsMenu.install(on: positionButton)
        positionButton.controlSize = .small
        positionButton.toolTip = "Ticker appearance and window settings"
        positionButton.setAccessibilityLabel("Ticker appearance and window settings")
        positionButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        updateSettingsMenuChecks(savedSpeed)

        let controls = NSStackView(views: [previousButton, positionLabel, nextButton,
                                           restartTickerButton,
                                           positionButton, expandButton, latestButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 4
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.setContentHuggingPriority(.required, for: .horizontal)
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailHeader.addSubview(controls)
        detailHeaderLayout = DetailHeaderLayout(header: detailHeader, picker: picker,
                                                controls: controls,
                                                actions: detailExitControls)

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
            tickerBackgroundView.topAnchor.constraint(equalTo: peekBar.topAnchor),
            tickerBackgroundView.leadingAnchor.constraint(equalTo: peekBar.leadingAnchor),
            tickerBackgroundView.trailingAnchor.constraint(equalTo: peekBar.trailingAnchor),
            tickerBackgroundView.bottomAnchor.constraint(equalTo: peekBar.bottomAnchor),
            peekProviderIcon.leadingAnchor.constraint(equalTo: peekBar.leadingAnchor,
                                                       constant: 12),
            peekProviderIcon.topAnchor.constraint(equalTo: peekBar.topAnchor, constant: 8),
            peekProviderIcon.widthAnchor.constraint(equalToConstant: 20),
            peekProviderIcon.heightAnchor.constraint(equalToConstant: 20),
            peekSourceLabel.leadingAnchor.constraint(equalTo: peekProviderIcon.trailingAnchor,
                                                      constant: 6),
            peekSourceLabel.trailingAnchor.constraint(equalTo: peekToolbar.leadingAnchor,
                                                       constant: -8),
            peekSourceLabel.topAnchor.constraint(equalTo: peekBar.topAnchor, constant: 10),
            peekSourceLabel.heightAnchor.constraint(equalToConstant: 16),
            peekTicker.leadingAnchor.constraint(equalTo: peekBar.leadingAnchor, constant: 14),
            peekTicker.trailingAnchor.constraint(equalTo: peekBar.trailingAnchor, constant: -14),
            peekTicker.bottomAnchor.constraint(equalTo: peekBar.bottomAnchor, constant: -7),
            peekTicker.heightAnchor.constraint(equalToConstant: 26),
            peekToolbar.trailingAnchor.constraint(equalTo: peekBar.trailingAnchor,
                                                   constant: -10),
            peekToolbar.topAnchor.constraint(equalTo: peekBar.topAnchor, constant: 7),
            peekToolbar.heightAnchor.constraint(equalToConstant: 24),
            fullMessageView.topAnchor.constraint(equalTo: content.topAnchor),
            fullMessageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            fullMessageView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            fullMessageView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            detailHeader.topAnchor.constraint(equalTo: content.topAnchor),
            detailHeader.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            detailHeader.trailingAnchor.constraint(equalTo: content.trailingAnchor),

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
        api.refreshHandler = { [weak self] in self?.publishAPI() }
        api.start()
        outsideClickMonitor.start { [weak self] location in
            DispatchQueue.main.async {
                guard let self,
                      shouldDismissDetails(isShowingDetails: !self.peekMode,
                                           isEditorVisible:
                                            self.checkRulesEditor?.window?.isVisible == true,
                                           windowFrame: self.panel.frame,
                                           clickLocation: location) else { return }
                self.dismissDetailsToTicker()
            }
        }
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
        let tickerPresentation = peekTicker.presentationMetrics
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
            "windowChromeHeight": Int(round(panel.frame.height -
                panel.contentRect(forFrameRect: panel.frame).height)),
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
                    : (!compactMode &&
                       feedView.bounds.height > scrollView.contentView.bounds.height)),
            "smartAutoscroll": true,
            "unseenCount": unseenCount,
            "cardCount": feedStack.arrangedSubviews.count,
            "visibleCardCount": (peekMode || messageMode || compactMode)
                ? 0 : eventCards.filter { !$0.isHidden }.count,
            "compactMode": compactMode,
            "peekMode": peekMode,
            "messageMode": messageMode,
            "messageReaderFrozen": messageMode && messageReaderSnapshot != nil,
            "messageReaderIndex": messageMode ? compactIndex : NSNull(),
            "closeControlVisible": messageMode || (!detailHeader.isHidden &&
                !detailExitControls.isHidden),
            "quitControlVisible": messageMode || (!detailHeader.isHidden &&
                !detailExitControls.isHidden),
            "peekProvider": peekProviderIcon?.provider.rawValue ?? "unknown",
            "peekSource": peekSourceLabel?.stringValue ?? "",
            "peekText": peekTicker?.text ?? "",
            "tickerOverflowing": peekTicker?.isOverflowing ?? false,
            "tickerPresentationOffset": Double(tickerPresentation.translation),
            "tickerMeasuredTextWidth": Double(tickerPresentation.textWidth),
            "tickerVisibleTextWidth": Double(tickerPresentation.visibleWidth),
            "tickerTextVisible": !peekTicker.text.isEmpty &&
                tickerPresentation.visibleWidth >= 1,
            "tickerReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "tickerSpeed": peekTicker.speed.rawValue,
            "tickerPointsPerSecond": Int(peekTicker.speed.pointsPerSecond),
            "tickerBackgroundMode": tickerBackgroundColor == nil ? "system" : "custom",
            "tickerBackgroundRGBA": tickerBackgroundColor.flatMap(
                TickerBackgroundPreference.components(of:))?.map(Double.init) ?? NSNull(),
            "tickerUsesDarkForeground": tickerBackgroundColor.map(
                TickerBackgroundPreference.usesDarkForeground(on:)) ?? false,
            "operationPending": operationState.operationPending,
            "pendingSource": operationState.latestPendingSource ?? NSNull(),
            "hoverDisclosure": false,
            "singleClickOpensMessage": true,
            "doubleClickOpensControls": true,
            "tickerCornerButtons": peekCornerControls.accessibilityNames,
            "tickerPrimaryActions": peekPrimaryActions.accessibilityNames,
            "settingsMenuStructure": tickerSettingsMenu?.structure ?? [:],
            "settingsMenuItems": tickerSettingsMenu?.topLevelTitles ?? [],
            "checkRulesText": CheckRulesStore.loadRaw(),
            "checkRuleCount": loadEvaluationInstructions().count,
            "checkInstructionMode": CheckRulesStore.mode().rawValue,
            "checkRulesStorage": "local-app-preferences",
            "checkRulesCustomized": CheckRulesStore.isCustomized(),
            "checkRulesEditorVisible": checkRulesEditor?.window?.isVisible ?? false,
            "outsideClickDismissesDetails": true,
            "discardedEmptySummaryCount": discardedEmptySummaryCount,
            "userResizableWidth": true,
            "compactPreferredWidth": Int(compactWidth),
            "compactMinimumWidth": Int(CompactWindowSizing.minimumWidth),
            "compactMaximumWidth": Int(CompactWindowSizing.maximumWidth),
            "compactHeaderStyle": CompactWindowSizing.headerStyle(
                for: compactWidth).rawValue,
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
            compactWidth = CompactWindowSizing.clamped(panel.frame.width)
        } else if compactMode {
            compactWidth = CompactWindowSizing.clamped(panel.frame.width)
            detailHeaderLayout.apply(width: compactWidth)
        } else {
            expandedHeight = panel.frame.height
            detailHeaderLayout.apply(width: panel.frame.width)
        }
        publishAPI()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if compactMode, !peekMode {
            UserDefaults.standard.set(Double(compactWidth),
                                      forKey: CompactWindowSizing.defaultsKey)
            updateSettingsMenuChecks(peekTicker.speed)
        }
        publishAPI()
    }

    func windowDidMove(_ notification: Notification) {
        publishAPI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        outsideClickMonitor.stop()
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
        case "close": dismissDetailsToTicker()
        case "quit": quitApplication()
        case "check-rules": showCheckRulesEditor()
        case let value where value.hasPrefix("corner/"):
            if let corner = TickerWindowCorner.allCases.first(where: {
                $0.routeName == String(value.dropFirst("corner/".count))
            }) {
                movePanel(toCorner: corner)
            }
        case let value where value.hasPrefix("speed/"):
            setTickerSpeed(String(value.dropFirst("speed/".count)))
        case "width/narrow": setCompactWidth(CompactWindowSizing.narrowWidth)
        case "width/standard": setCompactWidth(CompactWindowSizing.standardWidth)
        case "background/blue":
            setTickerBackground(NSColor(srgbRed: 0.16, green: 0.38,
                                        blue: 0.68, alpha: 1))
        case "background/system": setTickerBackground(nil)
        case "reveal":
            applyPeekMode(false)
        case "hide":
            applyPeekMode(true)
        case let value where value.hasPrefix("position/"):
            movePanel(to: String(value.dropFirst("position/".count)))
        default: break
        }
    }

    private func setTickerSpeed(_ rawValue: String) {
        guard let speed = TickerSpeed(rawValue: rawValue) else { return }
        peekTicker.speed = speed
        updateSettingsMenuChecks(speed)
        UserDefaults.standard.set(speed.rawValue, forKey: "tickerSpeed")
        publishAPI()
    }

    @objc private func showTickerBackgroundPicker(_ sender: Any?) {
        let colorPanel = NSColorPanel.shared
        colorPanel.showsAlpha = true
        colorPanel.isContinuous = true
        colorPanel.color = tickerBackgroundColor ?? .controlAccentColor
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(tickerBackgroundChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        colorPanel.orderFront(nil)
    }

    @objc private func tickerBackgroundChanged(_ sender: NSColorPanel) {
        setTickerBackground(sender.color)
    }

    private func setTickerBackground(_ color: NSColor?) {
        TickerBackgroundPreference.save(color)
        applyTickerBackground(color)
        updateSettingsMenuChecks(peekTicker.speed)
        publishAPI()
    }

    private func showCheckRulesEditor() {
        if let checkRulesEditor {
            checkRulesEditor.present()
            return
        }
        let editor = CheckRulesEditor(contents: CheckRulesStore.loadRaw(),
                                      mode: CheckRulesStore.mode(),
                                      save: { [weak self] text, mode in
            CheckRulesStore.saveRaw(text)
            CheckRulesStore.saveMode(mode)
            self?.refreshStatus()
            self?.publishAPI()
        }, closed: { [weak self] in
            self?.checkRulesEditor = nil
            self?.publishAPI()
        })
        checkRulesEditor = editor
        editor.present()
        publishAPI()
    }

    private func applyTickerBackground(_ color: NSColor?) {
        tickerBackgroundColor = color
        tickerBackgroundView?.color = color
        guard let color else {
            peekTicker?.foregroundColor = .labelColor
            peekSourceLabel?.textColor = .secondaryLabelColor
            peekPrimaryActions?.foregroundColor = nil
            peekCornerControls?.foregroundColor = nil
            return
        }
        let foreground: NSColor = TickerBackgroundPreference.usesDarkForeground(on: color)
            ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : NSColor.white
        peekTicker?.foregroundColor = foreground
        peekSourceLabel?.textColor = foreground.withAlphaComponent(0.72)
        peekPrimaryActions?.foregroundColor = foreground.withAlphaComponent(0.78)
        peekCornerControls?.foregroundColor = foreground.withAlphaComponent(0.78)
    }

    private func updateSettingsMenuChecks(_ speed: TickerSpeed) {
        tickerSettingsMenu?.update(speed: speed, width: compactWidth,
                                   usesSystemBackground: tickerBackgroundColor == nil)
    }

    private func setCompactWidth(_ requestedWidth: CGFloat) {
        compactWidth = CompactWindowSizing.clamped(requestedWidth)
        UserDefaults.standard.set(Double(compactWidth),
                                  forKey: CompactWindowSizing.defaultsKey)
        updateSettingsMenuChecks(peekTicker.speed)
        guard compactMode, !peekMode else { publishAPI(); return }
        detailHeaderLayout.apply(width: compactWidth)
        let minimumHeight: CGFloat = messageMode
            ? 180 : CompactWindowSizing.controlsHeight(for: compactWidth)
        let maximumHeight: CGFloat = messageMode ? 520 : minimumHeight
        transitionPanel(to: messageMode ? max(minimumHeight, panel.frame.height)
                                        : minimumHeight,
                        width: compactWidth,
                        minSize: NSSize(width: CompactWindowSizing.minimumWidth,
                                        height: minimumHeight),
                        maxSize: NSSize(width: CompactWindowSizing.maximumWidth,
                                        height: maximumHeight))
        publishAPI()
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

    private func movePanel(toCorner corner: TickerWindowCorner) {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrame(movedWindowFrame(panel.frame, to: corner, within: visible),
                       display: true)
        publishAPI()
    }

    private func applyPeekMode(_ peek: Bool, animated: Bool = false) {
        peekMode = peek
        messageMode = false
        messageReaderSnapshot = nil
        panel.becomesKeyOnlyIfNeeded = peek
        (panel.contentView as? CompactInteractionView)?.dragOnly = peek
        peekBar.isHidden = !peek
        fullMessageView.isHidden = true
        detailHeader.isHidden = peek
        scrollView.isHidden = !shouldShowHistoryFeed(peekMode: peek,
                                                     messageMode: messageMode,
                                                     compactMode: compactMode)
        peekTicker.setActive(peek)
        if peek {
            detailHeaderLayout.setActive(false, width: compactWidth)
            transitionPanel(to: peekHeight, width: peekWidth,
                            minSize: NSSize(width: 340, height: 54),
                            maxSize: NSSize(width: peekWidth, height: peekHeight),
                            animated: animated)
            releaseDetailFocus()
        } else {
            detailHeaderLayout.setActive(true,
                width: compactMode ? compactWidth : expandedWidth)
            let controlsHeight = CompactWindowSizing.controlsHeight(for: compactWidth)
            let minSize = compactMode
                ? NSSize(width: CompactWindowSizing.minimumWidth,
                         height: controlsHeight)
                : NSSize(width: 520, height: 360)
            let maxSize: NSSize
            if compactMode {
                maxSize = NSSize(width: CompactWindowSizing.maximumWidth,
                                 height: controlsHeight)
            } else if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                maxSize = NSSize(width: min(expandedWidth, visible.width),
                                 height: visible.height)
            } else {
                maxSize = NSSize(width: expandedWidth, height: expandedHeight)
            }
            transitionPanel(to: compactMode ? controlsHeight
                                            : max(520, expandedHeight),
                            width: compactMode ? compactWidth : expandedWidth,
                            minSize: minSize, maxSize: maxSize, animated: animated)
            focusDetails()
        }
        publishAPI()
    }

    private func focusDetails() {
        let current = NSRunningApplication.current
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != current.processIdentifier {
            previouslyActiveApplication = frontmost
        }
        current.activate(options: [])
        panel.makeKey()
    }

    private func releaseDetailFocus() {
        if panel.isKeyWindow { panel.resignKey() }
        previouslyActiveApplication?.activate(options: [])
        previouslyActiveApplication = nil
    }

    private func dismissDetailsToTicker() {
        let shouldResumeLatest = messageMode || !compactMode
        if !compactMode {
            expandedHeight = panel.frame.height
            compactMode = true
        }
        if shouldResumeLatest {
            compactIndex = MessageReaderSelection.latestIndex(eventCount: eventCards.count)
        }
        applyPeekMode(true)
        updateCardVisibility()
    }

    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func showControlsFromMessageReader() {
        if messageMode {
            compactIndex = MessageReaderSelection.latestIndex(eventCount: eventCards.count)
        }
        applyPeekMode(false)
        updateCardVisibility()
    }

    private func showCurrentMessage() {
        guard compactIndex >= 0, compactIndex < eventPreviews.count else { return }
        let preview = eventPreviews[compactIndex]
        let snapshot = MessageReaderSnapshot(source: preview.displaySource,
                                             text: preview.detailText,
                                             kind: preview.kind,
                                             tone: preview.readerTone)
        messageReaderSnapshot = snapshot
        fullMessageView.show(source: snapshot.source, text: snapshot.text,
                             kind: snapshot.kind, tone: snapshot.tone)
        peekMode = false
        messageMode = true
        (panel.contentView as? CompactInteractionView)?.dragOnly = false
        peekBar.isHidden = true
        fullMessageView.isHidden = false
        detailHeader.isHidden = true
        scrollView.isHidden = true
        detailHeaderLayout.setActive(false, width: compactWidth)
        peekTicker.setActive(false)
        panel.becomesKeyOnlyIfNeeded = false
        let readerHeight = fullMessageView.preferredHeight(forWidth: compactWidth)
        transitionPanel(to: readerHeight, width: compactWidth,
                        minSize: NSSize(width: CompactWindowSizing.minimumWidth, height: 150),
                        maxSize: NSSize(width: CompactWindowSizing.maximumWidth, height: 520))
        focusDetails()
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
        guard compactMode else { return }
        if peekMode || messageMode { applyPeekMode(false) }
        compactMode = false
        scrollView.isHidden = false
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
                peekTicker.text = normalizedTickerText(preview.tickerText)
                updatePeekHeader(source: preview.displaySource)
            }
            previousButton.isEnabled = compactIndex > 0
            nextButton.isEnabled = compactIndex >= 0 && compactIndex + 1 < eventCards.count
            expandButton.title = expandButton.image == nil
                ? (controlsExpansionTitle(compactMode: true) ?? "") : ""
            expandButton.isHidden = false
            restartTickerButton.isEnabled = !eventCards.isEmpty
            latestButton.isHidden = true
        } else {
            for card in eventCards { card.isHidden = false }
            for card in systemCards { card.isHidden = !eventCards.isEmpty }
            positionLabel.stringValue = "All \(eventCards.count)"
            previousButton.isEnabled = false
            nextButton.isEnabled = false
            expandButton.isHidden = true
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

    private func updatePeekHeader(source: String) {
        peekProviderIcon.update(source: source)
        peekSourceLabel.stringValue = source
        peekSourceLabel.toolTip = source
        peekBar.layoutSubtreeIfNeeded()
        peekToolbar.needsDisplay = true
        peekBar.needsDisplay = true
        peekBar.displayIfNeeded()
        CATransaction.flush()
    }

    private func captureWindowPNG() -> Data? {
        let captureWindow = checkRulesEditor?.window?.isVisible == true
            ? checkRulesEditor?.window : panel
        guard let window = captureWindow, let view = window.contentView else { return nil }
        let scale = window.backingScaleFactor
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
            eventPreviews.append(MessagePreview(source: source, text: event.text,
                                                kind: event.kind))
            if MessageReaderSelection.shouldAdvanceForNewMessage(
                isReaderOpen: messageMode, wasFollowingLatest: wasFollowingLatest) {
                compactIndex = eventCards.count - 1
            }
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
        status.toolTip = status.stringValue
        picker.toolTip = status.stringValue
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

    private func refreshPreview(_ preview: MessagePreview) {
        guard compactIndex >= 0, compactIndex < eventPreviews.count,
              eventPreviews[compactIndex] === preview else { return }
        peekTicker.text = normalizedTickerText(preview.tickerText)
        updatePeekHeader(source: preview.displaySource)
        // The reader displays an immutable snapshot. Async evaluator updates
        // remain on the underlying message and appear after the reader closes.
    }

    private func showAlert(_ decision: EvaluationDecision, provider: String,
                           _ ms: Double, card: EventCard,
                           preview: MessagePreview) {
        preview.evaluation = .alert(decision)
        let proof = decision.evidence.isEmpty ? "" : "\n\(decision.evidence)"
        card.setAlert("⚠ Alert · \(provider) · \(Int(ms)) ms\n\(decision.reason)\(proof)")
        NSSound.beep()
        alertCount += 1
        panel.title = "⚠ Thinkpeek alert — \(alertCount)"
        apiEvents.append([
            "kind": "drift-alert", "text": decision.reason,
            "evidence": decision.evidence, "source": preview.source,
            "provider": provider, "latencyMs": Int(ms),
        ])
        refreshPreview(preview)
        publishAPI()
    }

    private func showCheckFailure(_ message: String, _ ms: Double,
                                  card: EventCard, preview: MessagePreview) {
        preview.evaluation = .failed(message)
        card.setError("Thinkpeek check error · \(message) · \(Int(ms)) ms")
        apiEvents.append([
            "kind": "drift-error", "text": message, "source": preview.source,
            "latencyMs": Int(ms),
        ])
        refreshPreview(preview)
        publishAPI()
    }

    private func evaluate(_ block: Block, source: String,
                          card existingCard: EventCard?,
                          preview existingPreview: MessagePreview?) {
        let destination = checkLabel()
        existingCard?.setFooter("Sending evidence to \(destination)…")
        apiEvents.append([
            "kind": "drift-request-started", "text": "sent for evaluation",
            "destination": destination, "source": source,
            "evidenceType": block.evaluationRecord.eventType,
        ])
        publishAPI()
        checkDrift(block.evaluationRecord) { [weak self] outcome, ms in
            guard let self else { return }
            var card = existingCard
            var preview = existingPreview
            switch outcome {
            case .scored(let decision, let provider) where decision.alert:
                if card == nil || preview == nil {
                    let event = UIEvent(timestamp: block.ts, kind: "analysis",
                                        text: block.text, readableAnalysis: true)
                    card = self.addCard(source: source, event: event)
                    preview = self.eventPreviews.last
                }
                guard let card, let preview else { return }
                self.showAlert(decision, provider: provider, ms,
                               card: card, preview: preview)
            case .scored(_, let provider):
                existingPreview?.evaluation = .clear
                existingCard?.setFooter("✓ \(provider) checked · no alert · \(Int(ms)) ms",
                                        color: .systemGreen)
                self.apiEvents.append([
                    "kind": "drift-clean", "text": "no alert", "provider": provider,
                    "source": source, "latencyMs": Int(ms),
                ])
                self.publishAPI()
            case .failed(let message):
                if card == nil || preview == nil {
                    let event = UIEvent(timestamp: block.ts, kind: "analysis",
                                        text: block.text, readableAnalysis: true)
                    card = self.addCard(source: source, event: event)
                    preview = self.eventPreviews.last
                }
                guard let card, let preview else { return }
                self.showCheckFailure(message, ms, card: card, preview: preview)
            }
        }
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
            let timestampPart = event.block.kind == .thinking ? "" : "\u{1f}" + event.block.ts
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
            if block.kind == .evidence {
                guard !block.backfilled else { continue }
                let state = driftStatus()
                guard state.ready else { continue }
                // Factual tool records remain out of the feed when clean. An
                // alert or failed check creates its own navigable origin card.
                evaluate(block, source: source, card: nil, preview: nil)
                continue
            }
            let ui = uiEvent(for: block)
            if ui.kind == "activity" {
                operationStarted(source: source)
                continue
            }
            if ui.readableAnalysis, presentableTickerText(ui.text) == nil {
                discardedEmptySummaryCount += 1
                publishAPI()
                continue
            }
            readableContentArrived(source: source)
            var apiItem = ui.json
            apiItem["source"] = source
            apiEvents.append(apiItem)
            let card = addCard(source: source, event: ui,
                               deferScrollAndLayout: isInitialHistoryBatch)
            let preview = eventPreviews.last
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
            evaluate(block, source: source, card: card, preview: preview)
        }
        if isInitialHistoryBatch {
            feedView.layoutSubtreeIfNeeded()
            scrollToLatest(nil)
        }
        publishAPI()
    }
}
