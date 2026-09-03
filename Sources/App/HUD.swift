// Main AppKit controller for the floating reasoning HUD.

import AppKit
import Foundation
import QuartzCore

func restoreNativeStatusItemForeground(_ button: NSStatusBarButton) {
    button.contentTintColor = nil
}

enum ViolationAlertsPreference {
    static let defaultsKey = "violationAlertsEnabled"
    static let displayDuration: TimeInterval = 10

    static func load(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func save(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}

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
    var violationID: String?
    var violationReviewed = false

    init(source: String, text: String, kind: String) {
        self.source = source
        self.text = text
        self.kind = kind
    }

    var tickerText: String {
        switch evaluation {
        case .alert(let decision):
            return "Violation: \(decision.reason)"
        case .failed:
            return "Check unavailable — this message was not evaluated"
        default:
            return text
        }
    }

    var displaySource: String {
        source
    }

    var readerTone: MessageReaderTone {
        switch evaluation {
        case .alert: return .error
        case .failed: return .warning
        default: return .normal
        }
    }

    var alarmActive: Bool {
        if case .alert = evaluation { return true }
        return false
    }

    var detailText: String {
        switch evaluation {
        case .alert(let decision):
            let proof = decision.evidence.isEmpty ? "" : "\nEvidence: \(decision.evidence)"
            return "**Violation**\n\(decision.reason)\(proof)\n\n" +
                "Triggered by \(source):\n\(text)"
        case .failed(let message):
            return "**Check unavailable**\nThis message was not evaluated.\n" +
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
    private var tickerAlarmColor: NSColor?
    private var tickerAlarmActive = false
    private var tickerActiveBackgroundColor = TickerAppearance.normalBackground
    private var fullMessageView: FullMessageView!
    private var peekProviderIcon: ProviderIconView!
    private var peekSourceLabel: NSTextField!
    private var checkerActivityIndicator: CheckerActivityIndicator!
    private var peekTicker: TickerView!
    private var peekCornerControls: TickerCornerControls!
    private var peekPrimaryActions: TickerPrimaryActions!
    private var peekToolbar: NSStackView!
    private var latestButton: NSButton!
    private var previousButton: NSButton!
    private var nextButton: NSButton!
    private var restartTickerButton: NSButton!
    private var positionLabel: NSTextField!
    private var positionButton: NSButton!
    private var checkRulesButton: NSButton!
    private var historyFilterControl: NSSegmentedControl!
    private var navigationGroup: DetailToolbarGroup!
    private var utilitiesGroup: DetailToolbarGroup!
    private var violationEmptyState: HistoryEmptyStateView!
    private var tickerSettingsMenu: TickerSettingsMenu!
    private var peekSettingsMenu: TickerSettingsMenu!
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
    // Match the stable AppKit content surface. A 460-point frame clipped the
    // final 50 points of the toolbar, including the Hide button.
    private let peekWidth: CGFloat = 510
    private let peekHeight: CGFloat = 70
    private var compactWidth = CompactWindowSizing.savedWidth()
    private var expandedHeight: CGFloat = 620
    private let expandedWidth: CGFloat = 700
    private var presentationKeys = Set<String>()
    private var unseenCount = 0
    private let transcriptMonitor = TranscriptMonitorWorker()
    private let claudeCloudActivityMonitor = ClaudeCloudActivityMonitor()
    private let claudeDesktopConversationMonitor = ClaudeDesktopConversationMonitor()
    private var picker: NSPopUpButton!
    private var status: NSTextField!
    private var sessions: [SessionInfo] = []
    private var pinned: String? = INITIAL_TRANSCRIPT // nil = watch all active
    private var lastScan = Date.distantPast
    private var lastPickerRefresh = Date.distantPast
    private let transcriptDiscovery = TranscriptDiscovery()
    private var monitorsReady = false
    private var initialScanComplete = false
    private var names: [String: String] = [:]
    private var alertCount = 0
    private let violationStore = ViolationStore()
    private var violationRecords: [ViolationRecord] = []
    private var violationsOnly = false
    private var unacknowledgedViolationIndex: Int?
    private var violationsMenuItem: NSMenuItem?
    private var checkerRequestTokens = Set<UUID>()
    private var checkerActivityDestination: String?
    private var operationState = OperationPresentationState()
    private let api = UIStateServer()
    private let outsideClickMonitor = OutsideClickMonitor()
    private var previouslyActiveApplication: NSRunningApplication?
    private var apiEvents: [[String: Any]] = []
    private var discardedEmptySummaryCount = 0
    private var statusItem: NSStatusItem?
    private var hiddenByUser = false
    private var violationAlertsEnabled = ViolationAlertsPreference.load()
    private var violationAlertDismissal: DispatchWorkItem?
    private var violationAlertRestoreIndex: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PrivacyAudit.shared.start()
        installStatusMenu()
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
            self.api.perform(.close, origin: .appKit)
        }
        (panel as? ConstrainedPanel)?.previousRequested = { [weak self] in
            self?.api.perform(.previous, origin: .appKit)
        }
        (panel as? ConstrainedPanel)?.nextRequested = { [weak self] in
            self?.api.perform(.next, origin: .appKit)
        }
        (panel as? ConstrainedPanel)?.firstRequested = { [weak self] in
            self?.api.perform(.first, origin: .appKit)
        }
        (panel as? ConstrainedPanel)?.latestRequested = { [weak self] in
            self?.api.perform(.latest, origin: .appKit)
        }
        (panel as? ConstrainedPanel)?.openMessageRequested = { [weak self] in
            self?.api.perform(.showMessage, origin: .appKit)
        }
        (panel as? ConstrainedPanel)?.violationsRequested = { [weak self] in
            self?.api.perform(.showViolations, origin: .appKit)
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
        if !ISOLATED_E2E {
            content.clicked = { [weak self] in
                self?.api.perform(.showMessage, origin: .appKit)
            }
        }

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

        checkerActivityIndicator = CheckerActivityIndicator(frame: .zero)
        checkerActivityIndicator.translatesAutoresizingMaskIntoConstraints = false

        peekTicker = TickerView()
        peekTicker.translatesAutoresizingMaskIntoConstraints = false
        let savedSpeed = UserDefaults.standard.string(forKey: "tickerSpeed")
            .flatMap(TickerSpeed.init(rawValue:)) ?? .normal
        peekTicker.speed = savedSpeed
        peekTicker.text = "Watching Claude and Codex…"

        peekCornerControls = TickerCornerControls(frame: .zero)
        peekCornerControls.cornerRequested = { [weak self] corner in
            self?.api.perform(.corner(corner.routeName), origin: .appKit)
        }
        peekPrimaryActions = TickerPrimaryActions(frame: .zero)
        peekPrimaryActions.checkRulesRequested = { [weak self] in
            self?.api.perform(.editCheckRules, origin: .appKit)
        }
        peekPrimaryActions.controlsRequested = { [weak self] in
            self?.api.perform(.showControls, origin: .appKit)
        }
        peekPrimaryActions.hideRequested = { [weak self] in self?.hideHUD() }
        peekSettingsMenu = TickerSettingsMenu()
        configureSettingsMenu(peekSettingsMenu)
        peekSettingsMenu.install(on: peekPrimaryActions.displaySettingsButton)
        peekToolbar = NSStackView(views: [peekCornerControls, peekPrimaryActions])
        peekToolbar.orientation = .horizontal
        peekToolbar.alignment = .centerY
        peekToolbar.spacing = 2
        peekToolbar.translatesAutoresizingMaskIntoConstraints = false
        peekToolbar.setContentHuggingPriority(.required, for: .horizontal)
        peekToolbar.setContentCompressionResistancePriority(.required, for: .horizontal)
        peekToolbar.widthAnchor.constraint(equalToConstant: 214).isActive = true
        tickerAlarmColor = TickerBackgroundPreference.load()
        applyTickerAppearance(alarmActive: false)
        peekBar.addSubview(peekProviderIcon)
        peekBar.addSubview(peekSourceLabel)
        peekBar.addSubview(checkerActivityIndicator)
        peekBar.addSubview(peekTicker)
        // Keep interactive controls above every text/image layer. AppKit's cached
        // rendering can otherwise omit them after a provider/source transition.
        peekBar.addSubview(peekToolbar)

        fullMessageView = FullMessageView(frame: .zero)
        fullMessageView.closeRequested = { [weak self] in
            self?.api.perform(.close, origin: .appKit)
        }
        fullMessageView.controlsRequested = { [weak self] in
            self?.api.perform(.showControls, origin: .appKit)
        }
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
        picker.action = #selector(requestSessionSelection(_:))
        picker.font = .systemFont(ofSize: 13, weight: .medium)
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
            self?.api.perform(.close, origin: .appKit)
        }
        detailHeader.addSubview(detailExitControls)

        latestButton = NSButton(title: "Latest ↓", target: self,
                                action: #selector(requestLatest(_:)))
        latestButton.bezelStyle = .rounded
        latestButton.controlSize = .small
        latestButton.translatesAutoresizingMaskIntoConstraints = false
        latestButton.setContentHuggingPriority(.required, for: .horizontal)
        latestButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        latestButton.toolTip = "Scroll to the latest history item"
        latestButton.setAccessibilityLabel("Scroll to latest history item")
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        previousButton = NSButton(title: "", target: self,
                                  action: #selector(requestPrevious(_:)))
        nextButton = NSButton(title: "", target: self,
                              action: #selector(requestNext(_:)))
        previousButton.image = NSImage(systemSymbolName: "chevron.left",
                                       accessibilityDescription: "Previous message")
        nextButton.image = NSImage(systemSymbolName: "chevron.right",
                                   accessibilityDescription: "Next message")
        previousButton.toolTip = "Previous message"
        previousButton.setAccessibilityLabel("Previous message")
        nextButton.toolTip = "Next message"
        nextButton.setAccessibilityLabel("Next message")
        for button in [previousButton!, nextButton!] {
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.controlSize = .small
            button.imagePosition = .imageOnly
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        restartTickerButton = NSButton(title: "", target: self,
                                       action: #selector(requestTickerRestart(_:)))
        restartTickerButton.bezelStyle = .accessoryBarAction
        restartTickerButton.isBordered = false
        restartTickerButton.controlSize = .small
        restartTickerButton.image = NSImage(systemSymbolName: "backward.end",
                                             accessibilityDescription: "Restart summary")
        restartTickerButton.imagePosition = .imageOnly
        restartTickerButton.toolTip = "Return to the beginning of this summary"
        restartTickerButton.setAccessibilityLabel("Restart summary ticker")
        restartTickerButton.translatesAutoresizingMaskIntoConstraints = false
        restartTickerButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        restartTickerButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        positionLabel = NSTextField(labelWithString: "—")
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.alignment = .center
        positionLabel.setAccessibilityLabel("Current message position")
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        expandButton = NSButton(title: "Show all", target: self,
                                action: #selector(requestHistory(_:)))
        expandButton.bezelStyle = .accessoryBarAction
        expandButton.isBordered = false
        expandButton.controlSize = .small
        expandButton.title = ""
        expandButton.image = NSImage(systemSymbolName: "clock.arrow.circlepath",
                                     accessibilityDescription: "Show message history")
        expandButton.imagePosition = .imageOnly
        expandButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        expandButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        expandButton.toolTip = "Show complete message history"
        expandButton.setAccessibilityLabel("Show complete message history")
        latestButton.isHidden = true

        checkRulesButton = NSButton(
            image: NSImage(systemSymbolName: "checkmark.shield",
                           accessibilityDescription: "Edit check prompt") ?? NSImage(),
            target: self, action: #selector(requestCheckRules(_:)))
        checkRulesButton.bezelStyle = .accessoryBarAction
        checkRulesButton.isBordered = false
        checkRulesButton.imagePosition = .imageLeading
        checkRulesButton.controlSize = .small
        checkRulesButton.toolTip = "Edit check prompt"
        checkRulesButton.setAccessibilityLabel("Edit check prompt")
        checkRulesButton.translatesAutoresizingMaskIntoConstraints = false
        checkRulesButton.heightAnchor.constraint(equalToConstant: 26).isActive = true

        historyFilterControl = NSSegmentedControl(
            labels: ["All", "Violations 0"], trackingMode: .selectOne,
            target: self, action: #selector(requestHistoryFilter(_:)))
        historyFilterControl.selectedSegment = 0
        historyFilterControl.controlSize = .small
        historyFilterControl.toolTip = "Filter message history"
        historyFilterControl.setAccessibilityLabel("History filter")
        historyFilterControl.translatesAutoresizingMaskIntoConstraints = false
        historyFilterControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 176).isActive = true
        historyFilterControl.isHidden = true

        positionButton = NSButton(frame: .zero)
        tickerSettingsMenu = TickerSettingsMenu()
        configureSettingsMenu(tickerSettingsMenu)
        tickerSettingsMenu.install(on: positionButton)
        positionButton.controlSize = .small
        positionButton.translatesAutoresizingMaskIntoConstraints = false
        positionButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        positionButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        updateSettingsMenuChecks(savedSpeed)

        navigationGroup = DetailToolbarGroup(
            views: [previousButton, positionLabel, nextButton, restartTickerButton])
        utilitiesGroup = DetailToolbarGroup(
            views: [historyFilterControl, checkRulesButton, positionButton,
                    expandButton, latestButton])
        let controls = NSStackView(views: [navigationGroup, utilitiesGroup])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
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

        violationEmptyState = HistoryEmptyStateView(frame: .zero)
        violationEmptyState.editPromptRequested = { [weak self] in
            self?.api.perform(.editCheckRules, origin: .appKit)
        }
        violationEmptyState.isHidden = true
        feedStack.addArrangedSubview(violationEmptyState)
        violationEmptyState.widthAnchor.constraint(
            equalTo: feedStack.widthAnchor,
            constant: -feedStack.edgeInsets.left - feedStack.edgeInsets.right).isActive = true

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
            peekSourceLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: checkerActivityIndicator.leadingAnchor,
                constant: -4),
            peekSourceLabel.topAnchor.constraint(equalTo: peekBar.topAnchor, constant: 10),
            peekSourceLabel.heightAnchor.constraint(equalToConstant: 16),
            checkerActivityIndicator.trailingAnchor.constraint(
                equalTo: peekToolbar.leadingAnchor, constant: -6),
            checkerActivityIndicator.topAnchor.constraint(
                equalTo: peekBar.topAnchor, constant: 9),
            checkerActivityIndicator.widthAnchor.constraint(equalToConstant: 16),
            checkerActivityIndicator.heightAnchor.constraint(equalToConstant: 16),
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

        api.captureHandler = { [weak self] in self?.captureWindowPNG() }
        api.actionHandler = { [weak self] command in self?.handleCommand(command) }
        api.start()
        if !ISOLATED_E2E {
            outsideClickMonitor.start { [weak self] location in
                DispatchQueue.main.async {
                    guard let self,
                          shouldDismissDetails(isShowingDetails: !self.peekMode,
                                               isEditorVisible:
                                                self.checkRulesEditor?.window?.isVisible == true,
                                               windowFrame: self.panel.frame,
                                               clickLocation: location) else { return }
                    self.api.perform(.close, origin: .appKit)
                }
            }
        }
        requestTranscriptDiscovery(includeSessions: true)
        refreshStatus()
        addSystemCard("Watching active Claude and Codex sessions",
                      detail: "New reasoning summaries appear here automatically.")
        violationRecords = violationStore.load()
        alertCount = violationRecords.count
        restoreViolationCards()
        updateViolationMenu()
        Timer.scheduledTimer(withTimeInterval: POLL, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Let AppKit present the first frame before any transcript backfill.
        // The repeating timer performs the first scan after POLL seconds.
    }

    private func publishAPI() {
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
        let tickerPresentation = peekTicker.presentationMetrics
        let tickerToolbarAttached = peekToolbar.arrangedSubviews.count == 2 &&
            peekToolbar.arrangedSubviews[0] === peekCornerControls &&
            peekToolbar.arrangedSubviews[1] === peekPrimaryActions
        api.publish([
            "schemaVersion": 1,
            "ready": true,
            "initialScanComplete": initialScanComplete,
            "windowTitle": panel.title,
            "selection": picker.titleOfSelectedItem ?? "",
            "status": status.stringValue,
            "externalAnalysisEnabled": driftStatus().ready,
            "analysisDestination": driftStatus().ready ? checkLabel() : NSNull(),
            "historyCount": BACKFILL == Int.max ? "all" : String(BACKFILL),
            "alwaysOnTop": panel.level == .floating,
            "windowVisible": panel.isVisible,
            "hiddenByUser": hiddenByUser,
            "violationAlertsEnabled": violationAlertsEnabled,
            "violationAlertVisible": violationAlertDismissal != nil,
            "menuBarViolationAlertActive": violationRecords.contains {
                $0.reviewedAt == nil
            },
            "menuBarAvailable": statusItem != nil,
            "statusItemUsesNativeForeground": statusItem?.button?.contentTintColor == nil,
            "statusMenuItems": statusItem?.menu?.items
                .filter { !$0.isSeparatorItem }.map(\.title) ?? [],
            "violationCount": violationRecords.count,
            "violationStorageError": violationStore.lastError ?? NSNull(),
            "violationRetentionLimit": ViolationStore.maximumRecords,
            "violationsVisible": violationsOnly && !peekMode && !messageMode,
            "violationEmptyStateVisible": violationEmptyState?.isHidden == false,
            "currentViolationVisible": unacknowledgedViolationIndex != nil,
            "historyFilter": violationsOnly ? "violations" : "all",
            "keyboardNavigation": ["left/up/k: previous", "right/down/j: next",
                                   "home: first", "end: latest",
                                   "return/space: open", "escape: ticker",
                                   "command-shift-v: violations"],
            "violationStorage": VIOLATIONS_PATH,
            "violations": violationRecords.map(\.json),
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
            "messageReaderSource": messageReaderSnapshot?.source ?? NSNull(),
            "messageReaderText": messageReaderSnapshot?.text ?? NSNull(),
            "closeControlVisible": messageMode || (!detailHeader.isHidden &&
                !detailExitControls.isHidden),
            "quitControlVisible": false,
            "quitControlInOverflow": false,
            "tickerSettingsControlVisible": peekMode &&
                !peekPrimaryActions.displaySettingsButton.isHidden,
            "detailCheckRulesControlVisible": !detailHeader.isHidden &&
                !checkRulesButton.isHidden,
            "detailSettingsControlVisible": !detailHeader.isHidden &&
                !positionButton.isHidden,
            "latestControlVisible": !detailHeader.isHidden &&
                !latestButton.isHidden,
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
            "tickerBackgroundMode": tickerAlarmActive ? "alarm" : "normal-semantic",
            "tickerBackgroundRGBA": TickerBackgroundPreference.components(
                of: tickerActiveBackgroundColor)?.map(Double.init) ?? NSNull(),
            "tickerAlarmActive": tickerAlarmActive,
            "checkerRequestInFlight": !checkerRequestTokens.isEmpty,
            "checkerActivityIndicatorVisible": !checkerActivityIndicator.isHidden,
            "checkerActivityDestination": checkerActivityDestination ?? NSNull(),
            "tickerAlarmColorMode": tickerAlarmColor == nil ? "default" : "custom",
            "tickerAlarmColorRGBA": tickerAlarmColor.flatMap(
                TickerBackgroundPreference.components(of:))?.map(Double.init) ?? NSNull(),
            "tickerUsesDarkForeground":
                TickerBackgroundPreference.usesDarkForeground(
                    on: tickerActiveBackgroundColor),
            "tickerTextWeight": "regular",
            "operationPending": operationState.operationPending,
            "operationWaiting": operationState.operationWaiting,
            "pendingSource": operationState.latestPendingSource ?? NSNull(),
            "activeSources": operationState.activeSources,
            "waitingSources": operationState.waitingSources,
            "activityDisplaySource": operationState.activityDisplaySource ?? NSNull(),
            "activityDisplayText": operationState.activityDisplayText ?? NSNull(),
            "hoverDisclosure": false,
            "singleClickOpensMessage": true,
            "doubleClickOpensControls": false,
            "tickerCornerButtons": peekCornerControls.accessibilityNames,
            "tickerCornerControlsVisible": peekMode &&
                tickerToolbarAttached &&
                !peekCornerControls.isHidden,
            "tickerToolbarActions": peekCornerControls.accessibilityNames +
                peekPrimaryActions.accessibilityNames,
            "availableWindowPositions": ["top-left", "top-center", "top-right",
                                         "bottom-left", "bottom-center", "bottom-right"],
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
                    : (compactMode ? "compact-controls"
                        : (violationsOnly ? "violations-list" : "expanded-card-feed"))),
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
        panel.setFrame(frame, display: true,
                       animate: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
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

    private func handleCommand(_ command: UICommand) {
        if case .violationAlerts = command {
            // Changing the preference handles an active transient itself.
        } else {
            cancelViolationAlertDismissal()
        }
        switch command {
        case .first: showFirst()
        case .previous: showPrevious()
        case .next: showNext()
        case .latest: scrollToLatest()
        case .showHistory: showHistory()
        case .showViolations: showViolations()
        case .historyFilter(let value):
            violationsOnly = value == "violations"
            unacknowledgedViolationIndex = nil
            showExpandedFeed()
        case .restartTicker: restartTickerAtBeginning()
        case .showMessage: showCurrentMessage()
        case .showControls: showControlsFromMessageReader()
        case .showHUD: showHUDFromMenu(nil)
        case .hideHUD: hideHUD()
        case .close: dismissDetailsToTicker()
        case .quit: quitApplication()
        case .editCheckRules: showCheckRulesEditor()
        case .closeCheckRules:
            checkRulesEditor?.close()
        case .saveCheckRules(let text, let rawMode):
            guard let mode = CheckInstructionMode(rawValue: rawMode) else { return }
            CheckRulesStore.saveRaw(text)
            CheckRulesStore.saveMode(mode)
            refreshStatus()
            publishAPI()
        case .selectSession(let path): applySessionSelection(path: path)
        case .corner(let name):
            guard let corner = TickerWindowCorner.allCases.first(where: {
                $0.routeName == name
            }) else { return }
            movePanel(toCorner: corner)
        case .speed(let raw): setTickerSpeed(raw)
        case .width(let width): setCompactWidth(width)
        case .position(let preset): movePanel(to: preset)
        case .chooseBackground: showTickerBackgroundPicker(nil)
        case .backgroundRGBA(let components):
            guard let components else { setTickerBackground(nil); return }
            guard components.count == 4 else { return }
            setTickerBackground(NSColor(srgbRed: components[0], green: components[1],
                                        blue: components[2], alpha: components[3]))
        case .violationAlerts(let enabled): setViolationAlerts(enabled)
        }
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble.fill",
                                     accessibilityDescription: "Thinkpeek")
        item.button?.toolTip = "Thinkpeek"
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Thinkpeek", action: #selector(showHUDFromMenu(_:)),
                              keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let violations = NSMenuItem(title: "Open Violation History…",
                                    action: #selector(showViolationsFromMenu(_:)),
                                    keyEquivalent: "v")
        violations.keyEquivalentModifierMask = [.command, .shift]
        violations.target = self
        menu.addItem(violations)
        violationsMenuItem = violations
        let checkPrompt = NSMenuItem(title: "Edit Check Prompt…",
                                     action: #selector(showCheckPromptFromMenu(_:)),
                                     keyEquivalent: ",")
        checkPrompt.target = self
        menu.addItem(checkPrompt)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Thinkpeek", action: #selector(quitFromMenu(_:)),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func hideHUD() {
        cancelViolationAlertDismissal()
        hiddenByUser = true
        panel.orderOut(nil)
        publishAPI()
    }

    @objc private func showHUDFromMenu(_ sender: Any?) {
        hiddenByUser = false
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        publishAPI()
    }

    @objc private func showViolationsFromMenu(_ sender: Any?) {
        api.perform(.showViolations, origin: .appKit)
    }

    @objc private func showCheckPromptFromMenu(_ sender: Any?) {
        api.perform(.editCheckRules, origin: .appKit)
    }

    @objc private func quitFromMenu(_ sender: Any?) { quitApplication() }

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
        colorPanel.color = tickerAlarmColor ?? TickerBackgroundPreference.stickyYellow
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(tickerBackgroundChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        colorPanel.orderFront(nil)
    }

    @objc private func tickerBackgroundChanged(_ sender: NSColorPanel) {
        let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
        api.perform(.backgroundRGBA([
            Double(color.redComponent), Double(color.greenComponent),
            Double(color.blueComponent), Double(color.alphaComponent),
        ]), origin: .appKit)
    }

    private func setTickerBackground(_ color: NSColor?) {
        TickerBackgroundPreference.save(color)
        tickerAlarmColor = color
        applyTickerAppearance(alarmActive: tickerAlarmActive)
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
            self?.api.perform(.saveCheckRules(text: text, mode: mode.rawValue),
                              origin: .appKit)
        }, closed: { [weak self] in
            self?.checkRulesEditor = nil
            self?.publishAPI()
        })
        checkRulesEditor = editor
        editor.present()
        publishAPI()
    }

    private func applyTickerAppearance(alarmActive: Bool) {
        tickerAlarmActive = alarmActive
        let background = TickerAppearance.background(
            alarmActive: alarmActive, configuredAlarmColor: tickerAlarmColor)
        tickerActiveBackgroundColor = background
        tickerBackgroundView?.color = background
        let foreground: NSColor = TickerBackgroundPreference.usesDarkForeground(on: background)
            ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : NSColor.white
        peekTicker?.foregroundColor = foreground
        peekSourceLabel?.textColor = foreground.withAlphaComponent(0.72)
        peekPrimaryActions?.foregroundColor = foreground.withAlphaComponent(0.78)
        peekCornerControls?.foregroundColor = foreground.withAlphaComponent(0.78)
    }

    private func updateSettingsMenuChecks(_ speed: TickerSpeed) {
        tickerSettingsMenu?.update(speed: speed, width: compactWidth,
                                   usesDefaultAlarmColor: tickerAlarmColor == nil,
                                   violationAlertsEnabled: violationAlertsEnabled)
        peekSettingsMenu?.update(speed: speed, width: compactWidth,
                                 usesDefaultAlarmColor: tickerAlarmColor == nil,
                                 violationAlertsEnabled: violationAlertsEnabled)
    }

    private func configureSettingsMenu(_ menu: TickerSettingsMenu) {
        menu.speedRequested = { [weak self] speed in
            self?.api.perform(.speed(speed.rawValue), origin: .appKit)
        }
        menu.widthRequested = { [weak self] width in
            self?.api.perform(.width(width), origin: .appKit)
        }
        menu.positionRequested = { [weak self] preset in
            self?.api.perform(.position(preset), origin: .appKit)
        }
        menu.backgroundRequested = { [weak self] in
            self?.api.perform(.chooseBackground, origin: .appKit)
        }
        menu.defaultAlarmColorRequested = { [weak self] in
            self?.api.perform(.backgroundRGBA(nil), origin: .appKit)
        }
        menu.violationAlertsRequested = { [weak self] enabled in
            self?.api.perform(.violationAlerts(enabled), origin: .appKit)
        }
    }

    private func setViolationAlerts(_ enabled: Bool) {
        violationAlertsEnabled = enabled
        ViolationAlertsPreference.save(enabled)
        if !enabled { dismissTemporaryViolation() }
        updateSettingsMenuChecks(peekTicker.speed)
        publishAPI()
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
        violationsOnly = false
        if !compactMode {
            expandedHeight = panel.frame.height
            compactMode = true
        }
        if shouldResumeLatest {
            compactIndex = MessageReaderSelection.latestIndex(eventCount: eventCards.count)
        }
        applyPeekMode(true)
        updateCardVisibility()
        updateWindowTitle()
    }

    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func showControlsFromMessageReader() {
        applyPeekMode(false)
        updateCardVisibility()
    }

    private func showCurrentMessage() {
        let snapshot: MessageReaderSnapshot
        var openedIndex: Int?
        if let index = unacknowledgedViolationIndex,
           index >= 0, index < eventPreviews.count {
            let preview = eventPreviews[index]
            compactIndex = index
            openedIndex = index
            snapshot = MessageReaderSnapshot(source: preview.displaySource,
                                             text: preview.detailText,
                                             kind: preview.kind,
                                             tone: preview.readerTone)
        } else if !compactMode, compactIndex >= 0,
                  compactIndex < eventPreviews.count {
            let preview = eventPreviews[compactIndex]
            openedIndex = compactIndex
            snapshot = MessageReaderSnapshot(source: preview.displaySource,
                                             text: preview.detailText,
                                             kind: preview.kind,
                                             tone: preview.readerTone)
        } else if let source = operationState.activityDisplaySource {
            let status = (operationState.activityDisplayText ?? "Working") +
                "\n\nReadable reasoning has not been written by the provider yet."
            snapshot = MessageReaderSnapshot(source: source, text: status,
                                             kind: "activity", tone: .normal)
        } else {
            guard compactIndex >= 0, compactIndex < eventPreviews.count else { return }
            let preview = eventPreviews[compactIndex]
            openedIndex = compactIndex
            snapshot = MessageReaderSnapshot(source: preview.displaySource,
                                             text: preview.detailText,
                                             kind: preview.kind,
                                             tone: preview.readerTone)
        }
        if let openedIndex { markViolationReviewed(at: openedIndex) }
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
                        minSize: NSSize(width: CompactWindowSizing.minimumWidth, height: 118),
                        maxSize: NSSize(width: CompactWindowSizing.maximumWidth, height: 420))
        focusDetails()
        publishAPI()
    }

    @objc private func requestPrevious(_ sender: Any?) {
        api.perform(.previous, origin: .appKit)
    }

    @objc private func requestNext(_ sender: Any?) {
        api.perform(.next, origin: .appKit)
    }

    @objc private func requestTickerRestart(_ sender: Any?) {
        api.perform(.restartTicker, origin: .appKit)
    }

    @objc private func requestHistory(_ sender: Any?) {
        api.perform(.showHistory, origin: .appKit)
    }

    @objc private func requestHistoryFilter(_ sender: NSSegmentedControl) {
        api.perform(.historyFilter(sender.selectedSegment == 1
            ? "violations" : "all"), origin: .appKit)
    }

    @objc private func requestCheckRules(_ sender: Any?) {
        api.perform(.editCheckRules, origin: .appKit)
    }

    private func showPrevious() {
        if !compactMode {
            let indexes = visibleEventIndexes
            guard let position = indexes.firstIndex(of: compactIndex), position > 0 else { return }
            selectExpandedMessage(at: indexes[position - 1])
            return
        }
        guard compactIndex > 0 else { return }
        unacknowledgedViolationIndex = nil
        compactIndex -= 1
        selectedMessageChanged()
    }

    private func showNext() {
        if !compactMode {
            let indexes = visibleEventIndexes
            guard let position = indexes.firstIndex(of: compactIndex),
                  position + 1 < indexes.count else { return }
            selectExpandedMessage(at: indexes[position + 1])
            return
        }
        guard compactIndex + 1 < eventCards.count else { return }
        unacknowledgedViolationIndex = nil
        compactIndex += 1
        selectedMessageChanged()
    }

    private func showFirst() {
        if !compactMode {
            guard let first = visibleEventIndexes.first else { return }
            selectExpandedMessage(at: first)
            return
        }
        guard !eventCards.isEmpty else { return }
        unacknowledgedViolationIndex = nil
        compactIndex = 0
        selectedMessageChanged()
    }

    private func selectedMessageChanged() {
        if messageMode, compactIndex >= 0, compactIndex < eventPreviews.count {
            let preview = eventPreviews[compactIndex]
            let snapshot = MessageReaderSnapshot(source: preview.displaySource,
                                                 text: preview.detailText,
                                                 kind: preview.kind,
                                                 tone: preview.readerTone)
            messageReaderSnapshot = snapshot
            fullMessageView.show(source: snapshot.source, text: snapshot.text,
                                 kind: snapshot.kind, tone: snapshot.tone)
            publishAPI()
        } else {
            updateCardVisibility()
        }
    }

    private func restartTickerAtBeginning() {
        guard compactMode else { return }
        peekTicker.restart()
        if !peekMode { applyPeekMode(true) }
    }

    private func showHistory() {
        violationsOnly = false
        unacknowledgedViolationIndex = nil
        showExpandedFeed()
    }

    private func showViolations() {
        hiddenByUser = false
        violationsOnly = true
        unacknowledgedViolationIndex = nil
        showExpandedFeed()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        updateViolationMenu()
    }

    private func showExpandedFeed() {
        guard compactMode else {
            updateCardVisibility()
            return
        }
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
        unseenCount = 0
        latestButton.title = "Latest ↓"
        if let latest = visibleEventIndexes.last { selectExpandedMessage(at: latest) }
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
                applyTickerAppearance(alarmActive: preview.alarmActive)
            } else {
                applyTickerAppearance(alarmActive: false)
            }
            previousButton.isEnabled = compactIndex > 0
            nextButton.isEnabled = compactIndex >= 0 && compactIndex + 1 < eventCards.count
            expandButton.title = expandButton.image == nil
                ? (controlsExpansionTitle(compactMode: true) ?? "") : ""
            expandButton.isHidden = false
            restartTickerButton.isEnabled = !eventCards.isEmpty
            latestButton.isHidden = true
        } else {
            for (index, card) in eventCards.enumerated() {
                card.isHidden = violationsOnly && !eventPreviews[index].alarmActive
            }
            for card in systemCards { card.isHidden = !eventCards.isEmpty }
            let visibleCount = violationsOnly
                ? eventPreviews.filter(\.alarmActive).count : eventCards.count
            positionLabel.stringValue = violationsOnly
                ? "Violations \(visibleCount)" : "All \(visibleCount)"
            previousButton.isEnabled = false
            nextButton.isEnabled = false
            expandButton.isHidden = true
            restartTickerButton.isEnabled = false
            latestButton.isHidden = false
            let indexes = visibleEventIndexes
            if !indexes.contains(compactIndex), let latest = indexes.last {
                compactIndex = latest
            }
        }
        violationEmptyState.showStorageError(violationStore.lastError)
        let showViolationEmptyState = !compactMode && violationsOnly &&
            (violationRecords.isEmpty || violationStore.lastError != nil)
        violationEmptyState.isHidden = !showViolationEmptyState
        navigationGroup.isHidden = !compactMode
        historyFilterControl.isHidden = compactMode
        // History is a reading/filtering surface. Prompt configuration and
        // display settings belong to the dedicated controls/ticker surfaces;
        // placing them beside history filters makes their actions ambiguous.
        checkRulesButton.isHidden = !compactMode
        positionButton.isHidden = !compactMode
        historyFilterControl.selectedSegment = violationsOnly ? 1 : 0
        historyFilterControl.setLabel("All \(eventCards.count)", forSegment: 0)
        historyFilterControl.setLabel("Violations \(violationRecords.count)", forSegment: 1)
        for (index, card) in eventCards.enumerated() {
            card.setSelected(!compactMode && index == compactIndex && !card.isHidden)
        }
        feedView.layoutSubtreeIfNeeded()
        fitCompactControlsToContent()
        if compactMode {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        publishAPI()
    }

    private func fitCompactControlsToContent() {
        guard compactMode, !peekMode, !messageMode else { return }
        let previewHeight = min(CompactWindowSizing.messagePreviewHeight,
                                ceil(feedStack.fittingSize.height))
        let targetHeight = CompactWindowSizing.headerHeight(for: compactWidth) +
            previewHeight
        guard abs(panel.frame.height - targetHeight) > 0.5 else { return }
        transitionPanel(to: targetHeight, width: compactWidth,
                        minSize: NSSize(width: CompactWindowSizing.minimumWidth,
                                        height: targetHeight),
                        maxSize: NSSize(width: CompactWindowSizing.maximumWidth,
                                        height: targetHeight),
                        animated: false)
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
        let fallback = ISO8601DateFormatter()
        guard let date = iso.date(from: timestamp) ?? fallback.date(from: timestamp) else {
            return timestamp
        }
        let calendar = Calendar.current
        let fmt = DateFormatter()
        if calendar.isDateInToday(date) {
            fmt.dateFormat = "'Today,' HH:mm"
        } else if calendar.isDateInYesterday(date) {
            fmt.dateFormat = "'Yesterday,' HH:mm"
        } else {
            fmt.dateFormat = "d MMM, HH:mm"
        }
        return fmt.string(from: date)
    }

    private func nearBottom() -> Bool {
        let visible = scrollView.contentView.bounds
        return feedView.bounds.maxY - visible.maxY < 64
    }

    @objc private func requestLatest(_ sender: Any?) {
        api.perform(.latest, origin: .appKit)
    }

    private func scrollToLatest() {
        if compactMode, !eventCards.isEmpty {
            unacknowledgedViolationIndex = nil
            compactIndex = eventCards.count - 1
            selectedMessageChanged()
            return
        }
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
        card.selectedRequested = { [weak self, weak card] in
            guard let self, let card,
                  let index = self.eventCards.firstIndex(where: { $0 === card }) else { return }
            self.selectExpandedMessage(at: index)
        }
        card.openRequested = { [weak self, weak card] in
            guard let self, let card,
                  let index = self.eventCards.firstIndex(where: { $0 === card }) else { return }
            self.selectExpandedMessage(at: index)
            self.api.perform(.showMessage, origin: .appKit)
        }
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
            DispatchQueue.main.async { [weak self] in self?.scrollToLatest() }
        } else {
            unseenCount += 1
            latestButton.title = "\(unseenCount) new ↓"
        }
        return card
    }

    private var visibleEventIndexes: [Int] {
        eventPreviews.indices.filter { !violationsOnly || eventPreviews[$0].alarmActive }
    }

    private func selectExpandedMessage(at index: Int) {
        guard !compactMode, eventCards.indices.contains(index),
              !eventCards[index].isHidden else { return }
        compactIndex = index
        for (cardIndex, card) in eventCards.enumerated() {
            card.setSelected(cardIndex == index && !card.isHidden)
        }
        panel.makeFirstResponder(eventCards[index])
        eventCards[index].scrollToVisible(eventCards[index].bounds)
        publishAPI()
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

    private func restoreViolationCards() {
        for record in violationRecords {
            let event = UIEvent(timestamp: record.timestamp, kind: "analysis",
                                text: record.content, readableAnalysis: true)
            let card = addCard(source: record.source, event: event,
                               deferScrollAndLayout: true)
            guard let preview = eventPreviews.last else { continue }
            preview.evaluation = .alert(EvaluationDecision(
                alert: true, reason: record.reason, evidence: record.evidence))
            preview.violationID = record.id
            preview.violationReviewed = record.reviewedAt != nil
            card.setViolation(reason: record.reason, evidence: record.evidence,
                              provider: record.provider, latencyMs: record.latencyMs,
                              checkPrompt: record.checkPrompt)
            card.setViolationReviewed(record.reviewedAt != nil)
        }
        if !violationRecords.isEmpty {
            compactIndex = eventCards.count - 1
            updateCardVisibility()
        }
    }

    private func updateViolationMenu() {
        let count = violationRecords.count
        let newCount = violationRecords.filter { $0.reviewedAt == nil }.count
        violationsMenuItem?.title = violationHistoryMenuTitle(
            recorded: count, unreviewed: newCount,
            storageUnavailable: violationStore.lastError != nil)
        violationsMenuItem?.toolTip = "Keeps the latest \(ViolationStore.maximumRecords) violations locally."
        violationsMenuItem?.isEnabled = true
        historyFilterControl?.setLabel("Violations \(count)", forSegment: 1)
        let hasUnacknowledged = newCount > 0
        statusItem?.button?.image = NSImage(
            systemSymbolName: count > 0
                ? (hasUnacknowledged
                    ? "exclamationmark.shield.fill" : "exclamationmark.shield")
                : "text.bubble.fill",
            accessibilityDescription: hasUnacknowledged
                ? "Thinkpeek has a new violation" : "Thinkpeek")
        statusItem?.button?.title = newCount == 0 ? "" : " \(newCount > 9 ? "9+" : String(newCount))"
        statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        if let button = statusItem?.button {
            restoreNativeStatusItemForeground(button)
        }
        statusItem?.button?.setAccessibilityLabel(count == 0
            ? "Thinkpeek, no recorded violations"
            : "Thinkpeek, \(newCount) new and \(count) recorded violation\(count == 1 ? "" : "s")")
        statusItem?.button?.toolTip = count == 0
            ? "Thinkpeek · no recorded violations"
            : "Thinkpeek · \(newCount) new · \(count) recorded"
    }

    private func markViolationReviewed(at index: Int) {
        guard eventPreviews.indices.contains(index),
              let id = eventPreviews[index].violationID,
              !eventPreviews[index].violationReviewed else { return }
        violationRecords = violationStore.markReviewed(id: id)
        eventPreviews[index].violationReviewed = true
        eventCards[index].setViolationReviewed(true)
        if unacknowledgedViolationIndex == index { unacknowledgedViolationIndex = nil }
        updateViolationMenu()
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
        unacknowledgedViolationIndex = nil
        violationsOnly = false
        compactIndex = -1
        restoreViolationCards()
        updateCardVisibility()
    }

    /// Operation records are immediate live status. They never enter history or
    /// the checker, but they must replace a stale thought from another provider
    /// while the exact source session is actively working.
    private func operationStarted(source: String, identity: String? = nil) {
        operationState.operationStarted(source: source, identity: identity)
        updateWindowTitle()
        publishAPI()
    }

    private func operationUpdated(source: String, identity: String? = nil) {
        operationState.operationUpdated(source: source, identity: identity)
        updateWindowTitle()
        publishAPI()
    }

    private func operationFinished(source: String, identity: String? = nil) {
        operationState.operationFinished(source: source, identity: identity)
        updateWindowTitle()
        publishAPI()
    }

    private func operationWaitingForUser(source: String, identity: String? = nil) {
        operationState.operationWaitingForUser(source: source, identity: identity)
        updateWindowTitle()
        publishAPI()
    }

    private func readableContentArrived(source: String, identity: String? = nil) {
        operationState.readableContentArrived(source: source, identity: identity)
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        if let index = unacknowledgedViolationIndex,
           index >= 0, index < eventPreviews.count,
           eventPreviews[index].alarmActive {
            let preview = eventPreviews[index]
            panel.title = "⚠ Thinkpeek violation — \(violationRecords.count) recorded"
            updatePeekHeader(source: preview.displaySource)
            peekTicker.text = normalizedTickerText(preview.tickerText)
            applyTickerAppearance(alarmActive: true)
            return
        }
        panel.title = operationState.windowTitle
        if let source = operationState.activityDisplaySource {
            updatePeekHeader(source: source)
            peekTicker.text = operationState.activityDisplayText ?? "Working"
            applyTickerAppearance(alarmActive: false)
        } else if compactIndex >= 0 && compactIndex < eventPreviews.count {
            updatePeekHeader(source: eventPreviews[compactIndex].displaySource)
            peekTicker.text = normalizedTickerText(eventPreviews[compactIndex].tickerText)
            applyTickerAppearance(alarmActive: eventPreviews[compactIndex].alarmActive)
        } else {
            updatePeekHeader(source: "Thinkpeek")
            peekTicker.text = "Watching Claude and Codex…"
            applyTickerAppearance(alarmActive: false)
        }
    }

    // MARK: session picker

    @objc private func requestSessionSelection(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        let path = (i <= 0 || i - 1 >= sessions.count) ? nil : sessions[i - 1].path
        api.perform(.selectSession(path: path), origin: .appKit)
    }

    private func applySessionSelection(path: String?) {
        pinned = path
        clearFeed()
        if let pinned {
            let name = sourceName(for: pinned)
            addSystemCard(name, detail: "Pinned session · sub-agents included")
            panel.title = name
        } else {
            addSystemCard("Auto mode", detail: "Watching all active sessions and sub-agents")
        }
        monitorsReady = false
        transcriptMonitor.reset(pinned: pinned) { [weak self] in
            self?.monitorsReady = true
        }
        lastScan = .distantPast
    }

    private func refreshPicker(with discoveredSessions: [SessionInfo]) {
        sessions = discoveredSessions
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
        checkRulesButton.title = d.ready ? "Checks On" : "Checks Off"
        checkRulesButton.contentTintColor = d.ready ? .systemGreen : .secondaryLabelColor
        checkRulesButton.toolTip = d.ready
            ? "Checks are enabled. Click to edit the check prompt."
            : "Checks are off: \(d.detail). Click to configure them."
        checkRulesButton.setAccessibilityLabel(d.ready
            ? "Checks on. Edit check prompt" : "Checks off. Edit check prompt")
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

    private func requestTranscriptDiscovery(includeSessions: Bool) {
        transcriptDiscovery.request(includeSessions: includeSessions) { [weak self] snapshot in
            guard let self else { return }
            if let sessions = snapshot.sessions {
                self.refreshPicker(with: sessions)
            }
            self.transcriptMonitor.update(
                discoveredPaths: snapshot.activePaths,
                launchSizes: snapshot.sizes,
                pinned: self.pinned) { [weak self] in
                    self?.monitorsReady = true
                }
            self.publishAPI()
        }
    }

    private func refreshPreview(_ preview: MessagePreview) {
        guard compactIndex >= 0, compactIndex < eventPreviews.count,
              eventPreviews[compactIndex] === preview else { return }
        peekTicker.text = normalizedTickerText(preview.tickerText)
        updatePeekHeader(source: preview.displaySource)
        applyTickerAppearance(alarmActive: preview.alarmActive)
        // The reader displays an immutable snapshot. Async evaluator updates
        // remain on the underlying message and appear after the reader closes.
    }

    private func showAlert(_ decision: EvaluationDecision, provider: String,
                           _ ms: Double, timestamp: String, card: EventCard,
                           preview: MessagePreview) {
        let shouldRevealTicker = violationAlertsEnabled && peekMode && !hiddenByUser
        let priorSelection = compactIndex
        var restoreSelection = priorSelection
        preview.evaluation = .alert(decision)
        card.setViolation(reason: decision.reason, evidence: decision.evidence,
                          provider: provider, latencyMs: Int(ms),
                          checkPrompt: CheckRulesStore.instruction())
        let record = ViolationRecord(
            timestamp: timestamp, source: preview.source, content: preview.text,
            reason: decision.reason, evidence: decision.evidence, provider: provider,
            latencyMs: Int(ms), checkPrompt: CheckRulesStore.instruction())
        violationRecords = violationStore.append(record)
        preview.violationID = record.id
        preview.violationReviewed = false
        card.setViolationReviewed(false)
        if shouldRevealTicker {
            NSSound.beep()
            NSAccessibility.post(element: panel as Any,
                                 notification: .announcementRequested,
                                 userInfo: [
                                    .announcement: "New Thinkpeek violation from \(preview.source). \(decision.reason)",
                                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                                 ])
        }
        alertCount = violationRecords.count
        if let index = eventPreviews.firstIndex(where: { $0 === preview }) {
            if priorSelection == index, index > 0 { restoreSelection = index - 1 }
            if shouldRevealTicker {
                compactIndex = index
            } else if compactIndex == index, index > 0 {
                // With popups disabled, a just-arrived violation must not take
                // over the ticker merely because it was the newest record.
                compactIndex = index - 1
            }
            unacknowledgedViolationIndex = shouldRevealTicker ? index : nil
        }
        violationsOnly = false
        if shouldRevealTicker {
            if violationAlertDismissal == nil { violationAlertRestoreIndex = restoreSelection }
            applyPeekMode(true, animated: false)
            panel.orderFrontRegardless()
            scheduleViolationAlertDismissal()
        } else {
            compactIndex = restoreSelection
            updateCardVisibility()
        }
        panel.title = "⚠ Thinkpeek alert — \(alertCount)"
        apiEvents.append([
            "kind": "drift-alert", "text": decision.reason,
            "evidence": decision.evidence, "source": preview.source,
            "provider": provider, "latencyMs": Int(ms),
        ])
        updateViolationMenu()
        updateWindowTitle()
        publishAPI()
    }

    private func scheduleViolationAlertDismissal() {
        violationAlertDismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissTemporaryViolation() }
        violationAlertDismissal = work
        let duration = ISOLATED_E2E ? 0.25 : ViolationAlertsPreference.displayDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func cancelViolationAlertDismissal() {
        violationAlertDismissal?.cancel()
        violationAlertDismissal = nil
        violationAlertRestoreIndex = nil
    }

    private func dismissTemporaryViolation() {
        violationAlertDismissal?.cancel()
        violationAlertDismissal = nil
        unacknowledgedViolationIndex = nil
        if let restoreIndex = violationAlertRestoreIndex, !eventCards.isEmpty {
            compactIndex = min(max(0, restoreIndex), eventCards.count - 1)
            updateCardVisibility()
            updateWindowTitle()
        }
        violationAlertRestoreIndex = nil
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
        let requestToken = UUID()
        let destination = checkLabel()
        existingCard?.setFooter("Checking against your prompt with \(destination)…")
        apiEvents.append([
            "kind": "drift-request-started", "text": "sent for evaluation",
            "destination": destination, "source": source,
            "evidenceType": block.evaluationRecord.eventType,
        ])
        // Track the evaluation before scheduling the provider request. A fast UI
        // poll must never observe idle between accepting evidence and the
        // requestStarted callback reaching the main queue.
        checkerRequestTokens.insert(requestToken)
        checkerActivityDestination = destination
        checkerActivityIndicator.begin(destination: destination)
        publishAPI()
        checkDrift(block.evaluationRecord, source: source,
                   requestStarted: { [weak self] destination in
            self?.checkerActivityDestination = destination
            self?.checkerActivityIndicator.begin(destination: destination)
            self?.publishAPI()
        }) { [weak self] outcome, ms in
            guard let self else { return }
            self.checkerRequestTokens.remove(requestToken)
            if self.checkerRequestTokens.isEmpty {
                self.checkerActivityDestination = nil
                self.checkerActivityIndicator.finish()
            }
            var card = existingCard
            var preview = existingPreview
            switch outcome {
            case .scored(let decision, let provider) where decision.alert:
                if card == nil || preview == nil {
                    let event = uiEvent(for: block)
                    card = self.addCard(source: source, event: event)
                    preview = self.eventPreviews.last
                }
                guard let card, let preview else { return }
                self.showAlert(decision, provider: provider, ms,
                               timestamp: block.ts, card: card, preview: preview)
            case .scored(_, let provider):
                existingPreview?.evaluation = .clear
                existingCard?.setFooter("No violation · checked by \(provider) in \(Int(ms)) ms")
                self.apiEvents.append([
                    "kind": "drift-clean", "text": "no alert", "provider": provider,
                    "source": source, "latencyMs": Int(ms),
                    "evidenceType": block.evaluationRecord.eventType,
                ])
                if let existingPreview { self.refreshPreview(existingPreview) }
                self.publishAPI()
            case .failed(let message):
                if card == nil || preview == nil {
                    let event = uiEvent(for: block)
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
            refreshStatus()
        }
        if now.timeIntervalSince(lastScan) > RESCAN {
            lastScan = now
            requestTranscriptDiscovery(
                includeSessions: now.timeIntervalSince(lastPickerRefresh) < POLL)
        }

        transcriptMonitor.poll { [weak self] arrived in
            self?.processArrived(arrived)
        }
        claudeCloudActivityMonitor.poll { [weak self] events in
            guard let self else { return }
            for event in events {
                self.processActivity(source: event.source, phase: event.phase)
            }
        }
        claudeDesktopConversationMonitor.poll { [weak self] events in
            self?.processResolvedArrived(events.map {
                (source: $0.source, identity: $0.source, block: $0.block)
            })
        }
    }

    private func processActivity(source: String, identity: String? = nil,
                                 phase: Block.ActivityPhase) {
        switch phase {
        case .started: operationStarted(source: source, identity: identity)
        case .updated: operationUpdated(source: source, identity: identity)
        case .waiting: operationWaitingForUser(source: source, identity: identity)
        case .finished: operationFinished(source: source, identity: identity)
        }
    }

    private func processArrived(_ incoming: [(path: String, block: Block)]) {
        processResolvedArrived(incoming.map {
            let root = rootSessionPath(for: $0.path)
            let identity = platformName(for: root) + ":" + sessionID(for: root)
            return (source: sourceName(for: $0.path), identity: identity,
                    block: $0.block)
        })
    }

    private func processResolvedArrived(
        _ incoming: [(source: String, identity: String, block: Block)]) {
        var arrived = incoming
        arrived.sort { $0.block.ts < $1.block.ts }
        arrived.removeAll { event in
            let normalized = event.block.text
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let timestampPart = event.block.kind == .thinking ? "" : "\u{1f}" + event.block.ts
            let key = event.identity + "\u{1f}" + normalized + timestampPart
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
            let source = event.source
            let ui = uiEvent(for: block)
            if ui.kind == "activity" {
                processActivity(source: source,
                                identity: event.identity,
                                phase: block.activityPhase ?? .updated)
                continue
            }
            if block.kind == .response {
                var apiItem = ui.json
                apiItem["source"] = source
                apiItem["displayed"] = false
                apiEvents.append(apiItem)
                // Responses are factual checker evidence, not provider
                // reasoning. Evaluate them immediately without presenting them
                // as thought cards. An alert or checker failure creates a card.
                guard !block.backfilled else { continue }
                guard block.externallyEvaluable else { continue }
                let state = driftStatus()
                guard state.ready else {
                    apiEvents.append([
                        "kind": "drift-skipped", "text": state.detail,
                        "source": source,
                        "evidenceType": block.evaluationRecord.eventType,
                    ])
                    continue
                }
                evaluate(block, source: source, card: nil, preview: nil)
                continue
            }
            if ui.readableAnalysis, presentableTickerText(ui.text) == nil {
                discardedEmptySummaryCount += 1
                publishAPI()
                continue
            }
            readableContentArrived(source: source, identity: event.identity)
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
                continue
            }
            guard block.externallyEvaluable else {
                card.setFooter("Not evaluated · provider supplied no checkable summary")
                continue
            }

            let state = driftStatus()
            guard state.ready else {
                card.setFooter("Not evaluated · \(state.detail)")
                continue
            }
            evaluate(block, source: source, card: card, preview: preview)
        }
        if isInitialHistoryBatch {
            feedView.layoutSubtreeIfNeeded()
            scrollToLatest()
        }
        if monitorsReady { initialScanComplete = true }
        publishAPI()
    }
}
