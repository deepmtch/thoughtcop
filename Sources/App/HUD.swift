// Main AppKit controller for the floating reasoning HUD.

import AppKit
import Foundation
import QuartzCore

/// The menu-bar glyph: a brain, plus a lightning bolt while a violation is
/// unreviewed. With `color` nil the result is a template image that macOS
/// draws in the menu bar's own foreground (BUG-079); with a color it is a
/// regular image drawn exactly in that color, which the flash needs because
/// a template image, its tint and the title color are all redrawn by macOS
/// in the menu bar's color, so the first flash showed black instead of red.
func statusGlyphImage(bolt: Bool, count: String = "", color: NSColor? = nil) -> NSImage {
    var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    if let color {
        config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    }
    let brain = NSImage(systemSymbolName: "brain", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) ?? NSImage()
    let boltConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .heavy)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color ?? .black]))
    let boltImage = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(boltConfig) ?? NSImage()
    let text = NSAttributedString(string: count, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
        .foregroundColor: color ?? NSColor.black])
    let textSize = count.isEmpty ? .zero : text.size()
    // The bolt sits beside the brain's top-right edge, like the app icon,
    // instead of over the folds where it is unreadable at 18 points.
    let boltOverlap: CGFloat = bolt ? boltImage.size.width * 0.4 : 0
    let glyphWidth = brain.size.width + boltOverlap
    let height = ceil(max(brain.size.height, textSize.height, 18))
    let width = ceil(glyphWidth + (count.isEmpty ? 0 : 3 + textSize.width))
    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
        brain.draw(in: NSRect(x: 0, y: (rect.height - brain.size.height) / 2,
                              width: brain.size.width, height: brain.size.height))
        if bolt {
            boltImage.draw(in: NSRect(x: glyphWidth - boltImage.size.width,
                                      y: rect.height - boltImage.size.height,
                                      width: boltImage.size.width,
                                      height: boltImage.size.height))
        }
        if !count.isEmpty {
            text.draw(at: NSPoint(x: glyphWidth + 3,
                                  y: (rect.height - textSize.height) / 2))
        }
        return true
    }
    image.isTemplate = color == nil
    return image
}

/// The flash image: brain, bolt and count all in `color`.
func statusFlashImage(count: String, color: NSColor) -> NSImage {
    statusGlyphImage(bolt: true, count: count, color: color)
}

/// True when some opaque pixel of `image` is within 0.2 of `color` in every
/// RGB channel (evidence that the color is actually drawn).
func imageDrawsColor(_ image: NSImage, _ color: NSColor) -> Bool {
    guard let target = color.usingColorSpace(.sRGB),
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(image.size.width * 2),
                                     pixelsHigh: Int(image.size.height * 2),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return false }
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    for x in 0..<rep.pixelsWide {
        for y in 0..<rep.pixelsHigh {
            guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                  pixel.alphaComponent > 0.8 else { continue }
            if abs(pixel.redComponent - target.redComponent) < 0.2,
               abs(pixel.greenComponent - target.greenComponent) < 0.2,
               abs(pixel.blueComponent - target.blueComponent) < 0.2 { return true }
        }
    }
    return false
}

func restoreNativeStatusItemForeground(_ button: NSStatusBarButton) {
    button.contentTintColor = nil
    // The flash sets a red attributed count; a plain title takes the native
    // foreground again.
    let title = button.title
    button.title = title
}

/// Two independent switches, as the user asked (2026-10-04): a new violation
/// turns the menu-bar icon red for `duration` (on by default)...
enum ViolationFlashPreference {
    static let defaultsKey = "violationFlashEnabled"
    static let duration: TimeInterval = 3

    static func load(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func save(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}

/// ...and shows a bubble under the icon for `duration` (off by default),
/// after the flash when both are on. The key is the earlier single alert
/// switch's, so an earlier opt-in keeps the bubble on.
enum ViolationBubblePreference {
    static let defaultsKey = "violationAlertsEnabled"
    static let duration: TimeInterval = 5

    static func load(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func save(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}

/// Hide survives restarts: a user who hid Doublethink is not shown the ticker
/// again on the next launch. Isolated tests neither read nor write it.
enum HiddenPreference {
    static let defaultsKey = "tickerHidden"

    static func load(defaults: UserDefaults = .standard) -> Bool {
        !ISOLATED_E2E && defaults.bool(forKey: defaultsKey)
    }

    static func save(_ hidden: Bool, defaults: UserDefaults = .standard) {
        guard !ISOLATED_E2E else { return }
        defaults.set(hidden, forKey: defaultsKey)
    }
}

/// The three history tabs. Violations lists those whose transcript record is
/// less than `violationArchiveAge` old; older ones are under Archive.
enum HistoryFilter: String {
    case all, violations, archive
}

/// One hour, as the user asked. Measured from the violation's transcript
/// record timestamp, the time shown on its row.
let violationArchiveAge: TimeInterval = 3600

/// nil when the record has no readable timestamp; such a violation is never
/// archived, because its age is unknown, and `/ui` counts it.
func violationIsArchived(timestamp: String, now: Date) -> Bool? {
    guard let date = parsedRecordTimestamp(timestamp) else { return nil }
    return now.timeIntervalSince(date) >= violationArchiveAge
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
    /// The violation's one-line summary (BUG-104), when it has arrived.
    var violationSummary: String?
    /// The reader shows Why and the full message only after "Why and full
    /// message ▸" when a summary is shown.
    var violationDetailsExpanded = false

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

    /// A violation or check failure is composed with headings, so the reader
    /// renders it as formatted text whatever kind the original record was.
    var readerKind: String {
        switch evaluation {
        // "violation" renders the summary bold; without one, the earlier style.
        case .alert: return violationSummary == nil ? "analysis" : "violation"
        case .failed: return "analysis"
        default: return kind
        }
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
            // Same order as the history row: the quote, why, then the full
            // message once (omitted when it is exactly the quote).
            let quote = decision.evidence.isEmpty ? "" : "“\(decision.evidence)”\n\n"
            let full = text == decision.evidence ? ""
                : "\n\n**Full message**\n\(text)"
            if let summary = violationSummary {
                // The summary first; Why and the full message one click away.
                let rest = violationDetailsExpanded
                    ? "Why: \(decision.reason)\(full)"
                    : "[Why and full message ▸](doublethink://violation-details)"
                return "**\(summary)**\n\n\(quote)\(rest)"
            }
            return "**Violation**\n\(quote)Why: \(decision.reason)\(full)"
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
    private var peekPrimaryActions: TickerPrimaryActions!
    private var peekToolbar: NSStackView!
    private let peekSeparator = NSTextField(labelWithString: "·")
    private var peekSourceKey = "Doublethink"
    /// Active only while the reader shows: hidden, its minimum height (about
    /// 39 pt) would hold the 28-pt ticker taller than its window.
    private var fullMessageBottom: NSLayoutConstraint!
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
    private var settingsWindow: SettingsWindow!
    private var isolatedInputMonitor: Any?
    /// What the bubble shows now: a new violation's alert, or the last
    /// violation while the mouse rests on the menu-bar icon.
    private enum BubbleMode: String { case none, alert, hover }
    private var bubbleMode: BubbleMode = .none
    private let statusHover = StatusItemHoverTracker()
    private var hoverWork: DispatchWorkItem?
    private var pointerOnIcon = false
    private var pointerOnBubble = false
    private static let hoverDelay: TimeInterval = 0.5
    private var isolatedActivity: NSObjectProtocol?
    /// Set when a violation was opened (bubble, Show Last Violation, Open
    /// Violation History) while the user had hidden Doublethink (BUG-100).
    private var returnToHiddenOnClose = false
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
    /// The one-line ticker follows the Window Width setting (Narrow 400 /
    /// Standard 560); 400 keeps the ticker bar's required 384 points.
    private var tickerWidth: CGFloat {
        max(CompactWindowSizing.narrowWidth, CompactWindowSizing.clamped(compactWidth))
    }
    /// One row, as the user asked (2026-10-04): icon, chat, text, actions.
    private let peekHeight: CGFloat = 28
    private var compactWidth = CompactWindowSizing.savedWidth()
    private var expandedHeight: CGFloat = 480
    /// History is a list of compact rows. 400 points (the Narrow width) fits
    /// its header controls and the hidden ticker bar's required 384 points.
    /// History is a list of compact two-line rows (option C of the approved
    /// mockup). Hidden views must stay detached for this width to hold.
    private let expandedWidth: CGFloat = 380
    /// Controls, reader and history share one width (approved unified UI).
    private var detailWidth: CGFloat { expandedWidth }
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
    private var historyFilter: HistoryFilter = .all
    /// The reader shows a fixed note, not a chat message: no chips, no status.
    private var readerShowsNote = false
    private var archiveBoundaryTimer: Timer?
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
    private var violationFlashEnabled = ViolationFlashPreference.load()
    private var violationBubbleEnabled = ViolationBubblePreference.load()
    private var violationVerificationEnabled = ViolationVerificationPreference.load()
    private var usageMenuItem: NSMenuItem?
    /// Reader session tab (nil = All), whether it follows that session's
    /// newest message, and per-session counts of messages that arrived while
    /// the reader showed something else.
    private var readerSession: String?
    private var readerLive = true
    private var readerUnseen: [String: Int] = [:]
    private var usageWindow: UsageWindow?
    /// Only records written after this moment are checked (see
    /// writtenSinceLaunch). Saved violations are kept regardless.
    private let launchedAt = Date()
    /// While set, the menu-bar icon and count are red.
    private var statusFlashActive = false
    private var statusFlashImageDrawsColor = false
    /// The flash uses the violation color chosen in Settings › General
    /// (default red).
    private var statusFlashColor: NSColor {
        (tickerAlarmColor ?? .systemRed).withAlphaComponent(1)
    }
    private let violationBubble = ViolationBubble()
    private var bubbleViolationID: String?
    /// Invalidates pending flash/bubble steps when a newer violation arrives.
    private var violationAlertGeneration = 0
    private var lastViolationMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PrivacyAudit.shared.start()
        installStatusMenu()
        panel = ConstrainedPanel(
            contentRect: NSRect(x: 60, y: 140, width: 560, height: 210),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Doublethink"
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
        panel.setFrameAutosaveName("doublethink.main-window")
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = true
        (panel as? ConstrainedPanel)?.escapeRequested = { [weak self] in
            guard let self, !self.peekMode else { return }
            self.api.perform(.close, origin: .appKit)
        }
        (panel as? ConstrainedPanel)?.newestFirst = { [weak self] in
            guard let self else { return false }
            return !self.compactMode && !self.peekMode && !self.messageMode
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

        peekSourceLabel = NSTextField(labelWithString: "Doublethink")
        peekSourceLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        peekSourceLabel.textColor = .secondaryLabelColor
        // Cut at the end so the chat name stays readable (middle truncation
        // showed only a sub-agent ID at narrow width).
        peekSourceLabel.lineBreakMode = .byTruncatingTail
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

        peekPrimaryActions = TickerPrimaryActions(frame: .zero)
        peekPrimaryActions.historyRequested = { [weak self] in
            self?.api.perform(.showHistory, origin: .appKit)
        }
        peekPrimaryActions.hideRequested = { [weak self] in self?.hideHUD() }
        configureSettingsButton(peekPrimaryActions.displaySettingsButton)
        peekToolbar = NSStackView(views: [peekPrimaryActions])
        peekToolbar.orientation = .horizontal
        peekToolbar.alignment = .centerY
        peekToolbar.spacing = 2
        peekToolbar.translatesAutoresizingMaskIntoConstraints = false
        peekToolbar.setContentHuggingPriority(.required, for: .horizontal)
        peekToolbar.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Sized by its buttons; a fixed width (once 214 pt for eight icons)
        // left the three actions floating away from the right edge.
        tickerAlarmColor = TickerBackgroundPreference.load()
        applyTickerAppearance(alarmActive: false)
        peekBar.addSubview(peekProviderIcon)
        peekBar.addSubview(peekSourceLabel)
        peekSeparator.textColor = .secondaryLabelColor
        peekSeparator.translatesAutoresizingMaskIntoConstraints = false
        peekSeparator.setContentHuggingPriority(.required, for: .horizontal)
        peekBar.addSubview(peekSeparator)
        peekBar.addSubview(checkerActivityIndicator)
        peekBar.addSubview(peekTicker)
        // Keep interactive controls above every text/image layer. AppKit's cached
        // rendering can otherwise omit them after a provider/source transition.
        peekBar.addSubview(peekToolbar)

        fullMessageView = FullMessageView(frame: .zero)
        fullMessageView.tabSelected = { [weak self] index in
            self?.api.perform(.readerTab(index), origin: .appKit)
        }
        fullMessageView.jumpToLatestRequested = { [weak self] in
            self?.api.perform(.readerLatest, origin: .appKit)
        }
        fullMessageView.closeRequested = { [weak self] in
            self?.api.perform(.close, origin: .appKit)
        }
        fullMessageView.linkRequested = { [weak self] url in
            if url.host == "violation-details" {
                self?.api.perform(.expandViolationDetails, origin: .appKit)
            }
        }
        fullMessageView.historyRequested = { [weak self] in
            self?.api.perform(.showHistory, origin: .appKit)
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

        latestButton = NSButton(title: "↑ New", target: self,
                                action: #selector(requestLatest(_:)))
        latestButton.bezelStyle = .rounded
        latestButton.controlSize = .small
        latestButton.translatesAutoresizingMaskIntoConstraints = false
        latestButton.setContentHuggingPriority(.required, for: .horizontal)
        latestButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        latestButton.toolTip = "Scroll to the newest history items"
        latestButton.setAccessibilityLabel("Scroll to newest history items")
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
            labels: ["All", "Violations 0", "Archive 0"], trackingMode: .selectOne,
            target: self, action: #selector(requestHistoryFilter(_:)))
        historyFilterControl.selectedSegment = 0
        historyFilterControl.controlSize = .small
        historyFilterControl.toolTip = "Filter message history"
        historyFilterControl.setAccessibilityLabel("History filter")
        historyFilterControl.translatesAutoresizingMaskIntoConstraints = false
        historyFilterControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 236).isActive = true
        historyFilterControl.isHidden = true

        positionButton = NSButton(frame: .zero)
        configureSettingsButton(positionButton)
        positionButton.controlSize = .small
        positionButton.translatesAutoresizingMaskIntoConstraints = false
        positionButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        positionButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        settingsWindow = makeSettingsWindow()
        fullMessageBottom = fullMessageView.bottomAnchor.constraint(
            equalTo: panel.contentView!.bottomAnchor)
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
            // One row: icon · chat name · text · checker light · actions.
            peekProviderIcon.leadingAnchor.constraint(equalTo: peekBar.leadingAnchor,
                                                       constant: 10),
            peekProviderIcon.centerYAnchor.constraint(equalTo: peekBar.centerYAnchor),
            peekProviderIcon.widthAnchor.constraint(equalToConstant: 16),
            peekProviderIcon.heightAnchor.constraint(equalToConstant: 16),
            peekSourceLabel.leadingAnchor.constraint(equalTo: peekProviderIcon.trailingAnchor,
                                                      constant: 6),
            peekSourceLabel.centerYAnchor.constraint(equalTo: peekBar.centerYAnchor),
            // The chat name never takes more than a third of the row.
            peekSourceLabel.widthAnchor.constraint(lessThanOrEqualTo: peekBar.widthAnchor,
                                                   multiplier: 0.34),
            peekSeparator.leadingAnchor.constraint(equalTo: peekSourceLabel.trailingAnchor,
                                                    constant: 5),
            peekSeparator.centerYAnchor.constraint(equalTo: peekBar.centerYAnchor),
            peekTicker.leadingAnchor.constraint(equalTo: peekSeparator.trailingAnchor,
                                                constant: 5),
            peekTicker.trailingAnchor.constraint(
                equalTo: checkerActivityIndicator.leadingAnchor, constant: -6),
            peekTicker.centerYAnchor.constraint(equalTo: peekBar.centerYAnchor),
            peekTicker.heightAnchor.constraint(equalToConstant: 22),
            checkerActivityIndicator.trailingAnchor.constraint(
                equalTo: peekToolbar.leadingAnchor, constant: -4),
            checkerActivityIndicator.centerYAnchor.constraint(equalTo: peekBar.centerYAnchor),
            checkerActivityIndicator.widthAnchor.constraint(equalToConstant: 16),
            checkerActivityIndicator.heightAnchor.constraint(equalToConstant: 16),
            peekToolbar.trailingAnchor.constraint(equalTo: peekBar.trailingAnchor,
                                                   constant: -6),
            peekToolbar.centerYAnchor.constraint(equalTo: peekBar.centerYAnchor),
            peekToolbar.heightAnchor.constraint(equalToConstant: 24),
            fullMessageView.topAnchor.constraint(equalTo: content.topAnchor),
            fullMessageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            fullMessageView.trailingAnchor.constraint(equalTo: content.trailingAnchor),

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

        if HiddenPreference.load() {
            hiddenByUser = true
        } else {
            panel.orderFrontRegardless()
        }
        applyPeekMode(true, animated: false)

        api.captureHandler = { [weak self] target in self?.captureWindowPNG(target: target) }
        api.actionHandler = { [weak self] command in self?.handleCommand(command) }
        api.start()
        if ISOLATED_E2E {
            // Isolated tests assert timer-driven behavior (the one-hour Archive
            // boundary); App Nap delayed those timers by about a minute while
            // other apps were in front on the host. Test runs only.
            isolatedActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated, reason: "Isolated end-to-end test run")
            // Isolated tests drive Doublethink only through the command API.
            // Real keys and clicks (a person or another tool using the same
            // desktop) must not change the app mid-assertion.
            isolatedInputMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown,
                .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel,
            ]) { _ in nil }
        }
        if !ISOLATED_E2E {
            outsideClickMonitor.start(shouldDismiss: { [weak self] location in
                guard let self else { return false }
                return shouldDismissDetails(isShowingDetails: !self.peekMode,
                                            isEditorVisible: self.settingsWindow.isVisible,
                                            windowFrame: self.panel.frame,
                                            clickLocation: location)
            }, dismiss: { [weak self] in
                self?.api.perform(.close, origin: .appKit)
            })
        }
        requestTranscriptDiscovery(includeSessions: true)
        refreshStatus()
        addSystemCard("Watching active Claude and Codex sessions",
                      detail: "New reasoning summaries appear here automatically.")
        violationRecords = violationStore.setLimit(violationStore.limit)
        alertCount = violationRecords.count
        restoreViolationCards()
        updateViolationMenu()
        Timer.scheduledTimer(withTimeInterval: POLL, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Let AppKit present the first frame before any transcript backfill.
        // The repeating timer performs the first scan after POLL seconds.
    }

    private func usageJSON(_ summary: UsageSummary) -> [String: Any] {
        ["checks": summary.totals.checks, "secondChecks": summary.totals.secondChecks,
         "inputTokens": summary.totals.inputTokens,
         "outputTokens": summary.totals.outputTokens,
         "costUSD": summary.costUSD.map { $0 as Any } ?? NSNull(),
         "models": summary.models]
    }

    private func publishAPI() {
        let usage = UsageStore.shared.summary()
        usageMenuItem?.title = usageMenuTitle(usage.today)
        if usageWindow?.isVisible == true { usageWindow?.refresh(backends: driftBackends()) }
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
        let tickerPresentation = peekTicker.presentationMetrics
        let tickerToolbarAttached = peekToolbar.arrangedSubviews.count == 1 &&
            peekToolbar.arrangedSubviews[0] === peekPrimaryActions
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
            "isolatedInputIgnored": isolatedInputMonitor != nil,
            "returnsToHiddenOnClose": returnToHiddenOnClose,
            "violationBubbleMode": bubbleMode.rawValue,
            "violationFlashEnabled": violationFlashEnabled,
            "violationBubbleEnabled": violationBubbleEnabled,
            "statusItemFlashActive": statusFlashActive,
            "violationBubbleVisible": violationBubble.isVisible,
            "violationBubbleTitle": violationBubble.isVisible ? violationBubble.title : "",
            "violationBubbleQuote": violationBubble.isVisible ? violationBubble.quote : "",
            "violationBubbleHint": violationBubble.isVisible ? violationBubble.hint : "",
            "violationBubblePlacement": violationBubble.isVisible ? violationBubble.placement : "",
            "violationBubbleOnScreen": violationBubble.isVisible && violationBubble.isOnScreen,
            "statusItemVisible": statusItem?.button?.window?.occlusionState
                .contains(.visible) == true,
            "violationBubbleFrame": violationBubble.isVisible ? [
                "x": Int(violationBubble.frame.minX), "y": Int(violationBubble.frame.minY),
                "width": Int(violationBubble.frame.width),
                "height": Int(violationBubble.frame.height)] : [:],
            "statusItemWindowFrame": statusItem?.button?.window.map { [
                "x": Int($0.frame.minX), "y": Int($0.frame.minY),
                "width": Int($0.frame.width), "height": Int($0.frame.height)] } ?? [:],
            "statusItemDrawsFlashColor": statusFlashActive && statusFlashImageDrawsColor,
            "statusItemImageIsTemplate": statusItem?.button?.image?.isTemplate ?? false,
            "lastViolationMenuTitle": lastViolationMenuItem?.title ?? "",
            "violationTabCounts": violationTabCountsJSON(),
            "menuBarViolationAlertActive": violationRecords.contains {
                $0.reviewedAt == nil
            },
            "menuBarAvailable": statusItem != nil,
            "statusItemUsesNativeForeground": statusItem?.button?.contentTintColor == nil,
            "statusItemBadgeText": statusItem?.button?.title
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "statusMenuItems": statusItem?.menu?.items
                .filter { !$0.isSeparatorItem }.map(\.title) ?? [],
            "violationCount": violationRecords.count,
            "violationStorageError": violationStore.lastError ?? NSNull(),
            "violationRetentionLimit": violationStore.limit,
            "violationRetentionChoices": ViolationHistoryPreference.choices,
            "violationVerificationEnabled": violationVerificationEnabled,
            "usageMenuTitle": usageMenuItem?.title ?? "",
            "usageWindowVisible": usageWindow?.isVisible == true,
            "usageToday": usageJSON(usage.today),
            "usageMonth": usageJSON(usage.month),
            "violationsVisible": historyFilter == .violations && !peekMode && !messageMode,
            "violationEmptyStateVisible": violationEmptyState?.isHidden == false,
            "currentViolationVisible": unacknowledgedViolationIndex != nil,
            "historyFilter": historyFilter.rawValue,
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
            "contentViewHeight": Int(panel.contentView?.bounds.height ?? 0),
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
            "cardCount": feedCardCount,
            "attachedCardCount": feedStack.arrangedSubviews.count,
            "selectedViolationExpanded": eventCards.indices.contains(compactIndex)
                ? eventCards[compactIndex].violationExpanded : false,
            "visibleCardCount": (peekMode || messageMode || compactMode)
                ? 0 : eventCards.filter { !$0.isHidden }.count,
            "compactMode": compactMode,
            "peekMode": peekMode,
            "messageMode": messageMode,
            "messageReaderFrozen": messageMode && messageReaderSnapshot != nil && !readerLive,
            "readerLive": messageMode && readerLive,
            "readerTabs": messageMode ? fullMessageView.tabTitles : [],
            "readerSelectedTab": messageMode && fullMessageView.tabTitles.indices
                .contains(fullMessageView.selectedTab)
                ? fullMessageView.tabTitles[fullMessageView.selectedTab] : NSNull(),
            "readerStatus": messageMode ? fullMessageView.statusText : "",
            "readerOverflowTabs": messageMode ? fullMessageView.overflowMenuTitles : [],
            "readerTabFrames": messageMode ? zip(fullMessageView.tabFrames,
                                                 fullMessageView.tabContentFrames).map {
                ["x": Int($0.minX), "y": Int($0.minY), "width": Int($0.width),
                 "contentX": Int($1.minX), "contentWidth": Int($1.width)] } : [],
            "readerTabAreaWidth": messageMode ? Int(fullMessageView.tabAreaWidth) : 0,
            "messageReaderIndex": messageMode ? compactIndex : NSNull(),
            "messageReaderSource": messageReaderSnapshot?.source ?? NSNull(),
            "messageReaderText": messageReaderSnapshot?.text ?? NSNull(),
            "messageReaderRenderedText": messageMode ? fullMessageView.text : NSNull(),
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
            "peekSource": peekSourceKey,
            "peekSourceShown": peekSourceLabel?.stringValue ?? "",
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
            "tickerBackgroundMode": "normal-semantic",
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
            "tickerToolbarActions": peekPrimaryActions.accessibilityNames,
            "tickerToolbarAttached": tickerToolbarAttached,
            "windowAtTop": windowAtTop,
            "windowRoundedTopCorners": panel.contentView?.layer?.maskedCorners
                .contains(.layerMinXMaxYCorner) ?? true,
            "tickerToolbarTrailingGap": Int(peekBar.bounds.maxX -
                peekPrimaryActions.convert(peekPrimaryActions.bounds, to: peekBar).maxX),
            "availableWindowPositions": ["top-left", "top-center", "top-right",
                                         "bottom-left", "bottom-center", "bottom-right"],
            "tickerPrimaryActions": peekPrimaryActions.accessibilityNames,
            "settingsVisible": settingsWindow?.isVisible == true,
            "settingsTab": settingsWindow?.isVisible == true
                ? settingsWindow.selectedTab.rawValue : "",
            "settingsTabs": SettingsTab.allCases.map(\.title),
            "settingsWindowTitle": settingsWindow?.window?.title ?? "",
            "settingsFlashSwitchOn": settingsWindow?.alerts.flashSwitch.state == .on,
            "settingsBubbleSwitchOn": settingsWindow?.alerts.bubbleSwitch.state == .on,
            "settingsVerificationSwitchOn":
                settingsWindow?.alerts.verificationSwitch.state == .on,
            "settingsHistoryChoice": settingsWindow?.alerts.historyButton.titleOfSelectedItem ?? "",
            "settingsSpeedChoice": settingsWindow?.general.speedButton.titleOfSelectedItem ?? "",
            "settingsWidthChoice": settingsWindow?.general.widthButton.titleOfSelectedItem ?? "",
            "checkRulesText": CheckRulesStore.loadRaw(),
            "checkRuleCount": loadEvaluationInstructions().count,
            "checkInstructionMode": CheckRulesStore.mode().rawValue,
            "checkRulesStorage": "local-app-preferences",
            "checkRulesCustomized": CheckRulesStore.isCustomized(),
            "checkRulesEditorVisible": settingsWindow?.isVisible == true &&
                settingsWindow.selectedTab == .rules,
            "providerCredentialsEditorVisible": settingsWindow?.isVisible == true &&
                settingsWindow.selectedTab == .keys,
            "groqCredentialConfigured": CheckerCredentials.shared.isConfigured(.groq),
            "cerebrasCredentialConfigured": CheckerCredentials.shared.isConfigured(.cerebras),
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
                        : (historyFilter == .all ? "expanded-card-feed"
                            : "\(historyFilter.rawValue)-list"))),
            "events": Array(apiEvents.suffix(250)),
        ])
    }

    func windowDidResize(_ notification: Notification) {
        guard panel != nil else { return }
        updateWindowCorners()
        if peekMode {
            compactWidth = max(CompactWindowSizing.narrowWidth,
                               CompactWindowSizing.clamped(panel.frame.width))
        } else if messageMode {
        } else if compactMode {
            detailHeaderLayout.apply(width: panel.frame.width)
        } else {
            expandedHeight = panel.frame.height
            detailHeaderLayout.apply(width: panel.frame.width)
        }
        publishAPI()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if peekMode {
            UserDefaults.standard.set(Double(compactWidth),
                                      forKey: CompactWindowSizing.defaultsKey)
            updateSettingsMenuChecks(peekTicker.speed)
        }
        publishAPI()
    }

    func windowDidMove(_ notification: Notification) {
        updateWindowCorners()
        publishAPI()
    }

    /// Flush against the menu bar, only the bottom corners are rounded, so the
    /// window reads as attached to it.
    private var windowAtTop: Bool {
        guard let panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else {
            return false
        }
        return abs(panel.frame.maxY - visible.maxY) < 1
    }

    private func updateWindowCorners() {
        guard let layer = panel?.contentView?.layer else { return }
        let bottom: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let all: CACornerMask = bottom.union([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        layer.maskedCorners = windowAtTop ? bottom : all
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
        switch command {
        case .first: showFirst()
        case .previous: showPrevious()
        case .next: showNext()
        case .latest: scrollToLatest()
        case .showHistory: showHistory()
        case .showViolations: showViolations()
        case .historyFilter(let value):
            guard let filter = HistoryFilter(rawValue: value) else { return }
            historyFilter = filter
            unacknowledgedViolationIndex = nil
            showExpandedFeed()
        case .restartTicker: restartTickerAtBeginning()
        case .showMessage: showCurrentMessage()
        case .showHUD: showHUDFromMenu(nil)
        case .hideHUD: hideHUD()
        case .close: dismissDetailsToTicker()
        case .quit: quitApplication()
        case .editCheckRules: showSettings(.rules)
        case .closeCheckRules, .closeProviderCredentials, .closeSettings:
            settingsWindow.requestClose()
        case .showSettings(let tab): showSettings(SettingsTab(rawValue: tab) ?? .general)
        case .saveCheckRules(let text, let rawMode):
            guard let mode = CheckInstructionMode(rawValue: rawMode) else { return }
            CheckRulesStore.saveRaw(text)
            CheckRulesStore.saveMode(mode)
            refreshStatus()
            publishAPI()
        case .editProviderCredentials: showSettings(.keys)
        case .applyProviderCredentialEdits(let edits, let completion):
            let failures = CheckerCredentials.shared.apply(edits)
            refreshStatus()
            publishAPI()
            completion(failures)
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
        case .violationFlash(let enabled): setViolationFlash(enabled)
        case .violationBubble(let enabled): setViolationBubble(enabled)
        case .violationVerification(let enabled): setViolationVerification(enabled)
        case .violationHistoryLimit(let limit): setViolationHistoryLimit(limit)
        case .readerTab(let index): if messageMode { selectReaderTab(index) }
        case .readerLatest: if messageMode { showReaderLatest() }
        case .showUsage: showUsage()
        case .closeUsage: usageWindow?.close()
        case .showLastViolation: showLastViolation()
        case .statusItemHover(let inside): statusItemHoverChanged(inside)
        case .expandViolationDetails: expandReaderViolationDetails()
        case .openViolationBubble: openBubbleViolation()
        case .toggleSelectedViolation:
            guard !compactMode, eventCards.indices.contains(compactIndex) else { break }
            let card = eventCards[compactIndex]
            card.setViolationExpanded(!card.violationExpanded)
            publishAPI()
        }
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let glyph = statusGlyphImage(bolt: false)
        glyph.accessibilityDescription = "Doublethink"
        item.button?.image = glyph
        item.button?.toolTip = "Doublethink"
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Doublethink", action: #selector(showHUDFromMenu(_:)),
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
        let lastViolation = NSMenuItem(title: "Show Last Violation",
                                       action: #selector(showLastViolationFromMenu(_:)),
                                       keyEquivalent: "")
        lastViolation.target = self
        lastViolation.toolTip = "Open the newest violation in the reader"
        menu.addItem(lastViolation)
        lastViolationMenuItem = lastViolation
        menu.addItem(.separator())
        let usage = NSMenuItem(title: usageMenuTitle(UsageStore.shared.summary().today),
                               action: #selector(showUsageFromMenu(_:)), keyEquivalent: "")
        usage.target = self
        usage.toolTip = "Checks and cost today and this month"
        menu.addItem(usage)
        usageMenuItem = usage
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(showSettingsFromMenu(_:)),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Doublethink", action: #selector(quitFromMenu(_:)),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        menu.delegate = self
        if let button = item.button {
            statusHover.changed = { [weak self] inside in
                // Isolated tests ignore real input (BUG-094 follow-up).
                guard !ISOLATED_E2E else { return }
                self?.api.perform(.statusItemHover(inside), origin: .appKit)
            }
            statusHover.install(on: button)
        }
        violationBubble.hoverChanged = { [weak self] inside in
            guard !ISOLATED_E2E else { return }
            self?.pointerOnBubble = inside
            self?.updateHoverBubble()
        }
        statusItem = item
    }

    private func hideHUD() {
        returnToHiddenOnClose = false
        hiddenByUser = true
        HiddenPreference.save(true)
        panel.orderOut(nil)
        publishAPI()
    }

    @objc private func showHUDFromMenu(_ sender: Any?) {
        // Show Doublethink undoes Hide for good.
        returnToHiddenOnClose = false
        hiddenByUser = false
        HiddenPreference.save(false)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        publishAPI()
    }

    @objc private func showViolationsFromMenu(_ sender: Any?) {
        api.perform(.showViolations, origin: .appKit)
    }

    @objc private func showLastViolationFromMenu(_ sender: Any?) {
        api.perform(.showLastViolation, origin: .appKit)
    }

    @objc private func showSettingsFromMenu(_ sender: Any?) {
        api.perform(.showSettings(SettingsTab.general.rawValue), origin: .appKit)
    }

    @objc private func showGeneralSettings(_ sender: Any?) {
        api.perform(.showSettings(SettingsTab.general.rawValue), origin: .appKit)
    }

    /// Both ⚙ buttons open Settings › General.
    private func configureSettingsButton(_ button: NSButton) {
        button.title = ""
        button.image = NSImage(systemSymbolName: "gearshape",
                               accessibilityDescription: "Settings")
        button.imagePosition = .imageOnly
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.target = self
        button.action = #selector(showGeneralSettings(_:))
        button.toolTip = "Settings"
        button.setAccessibilityLabel("Settings")
    }

    @objc private func quitFromMenu(_ sender: Any?) { quitApplication() }

    @objc private func showUsageFromMenu(_ sender: Any?) {
        api.perform(.showUsage, origin: .appKit)
    }

    private func showUsage() {
        if usageWindow == nil {
            usageWindow = UsageWindow()
            usageWindow?.closed = { [weak self] in self?.publishAPI() }
        }
        usageWindow?.show(backends: driftBackends())
        publishAPI()
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

    private func makeSettingsWindow() -> SettingsWindow {
        let rules = CheckRulesEditor(contents: CheckRulesStore.loadRaw(),
                                     mode: CheckRulesStore.mode(),
                                     save: { [weak self] text, mode in
            self?.api.perform(.saveCheckRules(text: text, mode: mode.rawValue),
                              origin: .appKit)
        })
        let keys = ProviderCredentialsEditor(statuses: Self.credentialStatuses(),
            save: { [weak self] edits in
                var failures = ["Doublethink could not save credentials."]
                self?.api.perform(.applyProviderCredentialEdits(edits,
                    completion: { failures = $0 }), origin: .appKit)
                return failures
            })
        keys.statusesProvider = { Self.credentialStatuses() }
        let window = SettingsWindow(rules: rules, keys: keys)
        window.closed = { [weak self] in self?.publishAPI() }
        let general = window.general
        general.speedChanged = { [weak self] speed in
            self?.api.perform(.speed(speed.rawValue), origin: .appKit)
        }
        general.widthChanged = { [weak self] width in
            self?.api.perform(.width(width), origin: .appKit)
        }
        general.positionPicked = { [weak self] preset in
            self?.api.perform(.position(preset), origin: .appKit)
        }
        general.chooseColorRequested = { [weak self] in
            self?.api.perform(.chooseBackground, origin: .appKit)
        }
        general.defaultColorRequested = { [weak self] in
            self?.api.perform(.backgroundRGBA(nil), origin: .appKit)
        }
        let alerts = window.alerts
        alerts.flashChanged = { [weak self] enabled in
            self?.api.perform(.violationFlash(enabled), origin: .appKit)
        }
        alerts.bubbleChanged = { [weak self] enabled in
            self?.api.perform(.violationBubble(enabled), origin: .appKit)
        }
        alerts.verificationChanged = { [weak self] enabled in
            self?.api.perform(.violationVerification(enabled), origin: .appKit)
        }
        alerts.historyLimitChanged = { [weak self] limit in
            self?.api.perform(.violationHistoryLimit(limit), origin: .appKit)
        }
        return window
    }

    private static func credentialStatuses() -> [CheckerProvider: String] {
        CheckerCredentials.shared.reload()
        return Dictionary(uniqueKeysWithValues: CheckerProvider.allCases.map {
            ($0, CheckerCredentials.shared.status($0))
        })
    }

    private func showSettings(_ tab: SettingsTab) {
        settingsWindow.rules.reload(contents: CheckRulesStore.loadRaw(),
                                    mode: CheckRulesStore.mode())
        settingsWindow.keys.refresh(statuses: Self.credentialStatuses())
        updateSettingsMenuChecks(peekTicker.speed)
        settingsWindow.show(tab)
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
    }

    /// The single refresh point for every settings control.
    private func updateSettingsMenuChecks(_ speed: TickerSpeed) {
        guard let settingsWindow else { return }
        settingsWindow.general.update(speed: speed, width: compactWidth,
                                      usesDefaultAlarmColor: tickerAlarmColor == nil)
        settingsWindow.alerts.update(flashEnabled: violationFlashEnabled,
                                     bubbleEnabled: violationBubbleEnabled,
                                     verificationEnabled: violationVerificationEnabled,
                                     historyLimit: violationStore.limit)
    }

    private func setViolationVerification(_ enabled: Bool) {
        violationVerificationEnabled = enabled
        ViolationVerificationPreference.save(enabled)
        updateSettingsMenuChecks(peekTicker.speed)
        refreshStatus()
        publishAPI()
    }

    private func setViolationHistoryLimit(_ limit: Int) {
        ViolationHistoryPreference.save(limit)
        violationRecords = violationStore.setLimit(limit)
        alertCount = violationRecords.count
        removeCardsForDeletedViolations()
        updateViolationMenu()
        updateSettingsMenuChecks(peekTicker.speed)
        publishAPI()
    }

    /// Removes the cards whose violation record the history limit deleted, so
    /// the history never shows a violation that is no longer stored.
    private func removeCardsForDeletedViolations() {
        let kept = Set(violationRecords.map(\.id))
        let removed = eventPreviews.indices.filter { index in
            guard let id = eventPreviews[index].violationID else { return false }
            return !kept.contains(id)
        }
        guard !removed.isEmpty else { return }
        func shifted(_ value: Int?, removing index: Int) -> Int? {
            guard let value else { return nil }
            if value == index { return nil }
            return value > index ? value - 1 : value
        }
        for index in removed.reversed() {
            let card = eventCards[index]
            if card.superview === feedStack {
                feedStack.removeArrangedSubview(card)
                card.removeFromSuperview()
            }
            feedOrder.removeAll { $0 === card }
            eventCards.remove(at: index)
            eventPreviews.remove(at: index)
            if compactIndex > index { compactIndex -= 1 }
            unacknowledgedViolationIndex = shifted(unacknowledgedViolationIndex,
                                                   removing: index)
        }
        compactIndex = min(compactIndex, eventCards.count - 1)
        updateCardVisibility()
    }

    private func setViolationFlash(_ enabled: Bool) {
        violationFlashEnabled = enabled
        ViolationFlashPreference.save(enabled)
        if !enabled, statusFlashActive { endViolationAlert() }
        updateSettingsMenuChecks(peekTicker.speed)
        publishAPI()
    }

    private func setViolationBubble(_ enabled: Bool) {
        violationBubbleEnabled = enabled
        ViolationBubblePreference.save(enabled)
        if !enabled, violationBubble.isVisible { endViolationAlert() }
        updateSettingsMenuChecks(peekTicker.speed)
        publishAPI()
    }

    private func setCompactWidth(_ requestedWidth: CGFloat) {
        compactWidth = CompactWindowSizing.clamped(requestedWidth)
        UserDefaults.standard.set(Double(compactWidth),
                                  forKey: CompactWindowSizing.defaultsKey)
        updateSettingsMenuChecks(peekTicker.speed)
        // The setting sizes the ticker; detail views keep their one width.
        guard peekMode else { publishAPI(); return }
        transitionPanel(to: peekHeight, width: tickerWidth,
                        minSize: NSSize(width: CompactWindowSizing.narrowWidth, height: peekHeight),
                        maxSize: NSSize(width: CompactWindowSizing.maximumWidth,
                                        height: peekHeight))
        publishAPI()
    }

    private func movePanel(to preset: String) {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let inset: CGFloat = 12
        var frame = panel.frame
        if preset.hasSuffix("left") { frame.origin.x = visible.minX + inset }
        else if preset.hasSuffix("right") { frame.origin.x = visible.maxX - frame.width - inset }
        else { frame.origin.x = visible.midX - frame.width / 2 }
        // Top positions touch the menu bar.
        if preset.hasPrefix("top") { frame.origin.y = visible.maxY - frame.height }
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
        // A hidden reader must not constrain the window: its tab and status
        // rows made the 70-point ticker lay out 82 points tall (header cut).
        fullMessageView.setSessions([], selected: 0, status: "", live: false,
                                    showJump: false, width: detailWidth)
        messageReaderSnapshot = nil
        panel.becomesKeyOnlyIfNeeded = peek
        (panel.contentView as? CompactInteractionView)?.dragOnly = peek
        peekBar.isHidden = !peek
        fullMessageView.isHidden = true
        fullMessageBottom.isActive = false
        detailHeader.isHidden = peek
        scrollView.isHidden = !shouldShowHistoryFeed(peekMode: peek,
                                                     messageMode: messageMode,
                                                     compactMode: compactMode)
        peekTicker.setActive(peek)
        if peek {
            detailHeaderLayout.setActive(false, width: detailWidth)
            transitionPanel(to: peekHeight, width: tickerWidth,
                            minSize: NSSize(width: CompactWindowSizing.narrowWidth, height: peekHeight),
                            maxSize: NSSize(width: CompactWindowSizing.maximumWidth,
                                            height: peekHeight),
                            animated: animated)
            releaseDetailFocus()
        } else {
            detailHeaderLayout.setActive(true, width: detailWidth)
            let controlsHeight = CompactWindowSizing.controlsHeight(for: detailWidth)
            let minSize = compactMode
                ? NSSize(width: detailWidth, height: controlsHeight)
                : NSSize(width: expandedWidth, height: 300)
            let maxSize: NSSize
            if compactMode {
                maxSize = NSSize(width: detailWidth, height: controlsHeight)
            } else if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                maxSize = NSSize(width: min(expandedWidth, visible.width),
                                 height: visible.height)
            } else {
                maxSize = NSSize(width: expandedWidth, height: expandedHeight)
            }
            transitionPanel(to: compactMode ? controlsHeight
                                            : max(360, expandedHeight),
                            width: detailWidth,
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
        historyFilter = .all
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
        if returnToHiddenOnClose {
            returnToHiddenOnClose = false
            hideHUD()
        }
    }

    private func quitApplication() {
        NSApp.terminate(nil)
    }

    /// Recent sessions for the reader tabs: working ones first, then by the
    /// newest message; at most four, then All.
    /// The chat a source belongs to: sub-agent sources ("<chat> · agent <id>",
    /// built by sourceName(for:)) belong to their parent chat's tab.
    private func readerSessionKey(_ source: String) -> String {
        source.components(separatedBy: " · agent ").first ?? source
    }

    private static let readerTabLimit = 3

    /// Chats for the reader tabs: the open one and working ones first, then by
    /// newest message; at most three (they must stay readable at 380 points),
    /// in a stable order so a tab never moves under the pointer.
    private func readerSessions() -> [String] {
        var ordered: [String] = []
        func add(_ key: String) { if !ordered.contains(key) { ordered.append(key) } }
        if let readerSession { add(readerSession) }
        operationState.activeSources.map(readerSessionKey).forEach(add)
        eventPreviews.reversed().map { readerSessionKey($0.source) }.forEach(add)
        let chosen = Array(ordered.prefix(Self.readerTabLimit))
        func firstSeen(_ key: String) -> Int {
            eventPreviews.firstIndex { readerSessionKey($0.source) == key } ?? Int.max
        }
        return chosen.sorted { firstSeen($0) < firstSeen($1) }
    }

    private func readerSessionWorking(_ key: String) -> Bool {
        operationState.activeSources.contains { readerSessionKey($0) == key }
    }

    private func readerIndexes(_ session: String?) -> [Int] {
        eventPreviews.indices.filter {
            session == nil || readerSessionKey(eventPreviews[$0].source) == session
        }
    }

    private func refreshReaderChrome() {
        guard messageMode else { return }
        let sessions = readerSessions()
        // With no chat yet, a lone "All" chip and a Live line would describe
        // nothing, and a fixed note belongs to no chat; the reader shows its
        // single source line instead.
        guard !sessions.isEmpty, !readerShowsNote else {
            fullMessageView.setSessions([], selected: 0, status: "", live: false,
                                        showJump: false, width: detailWidth)
            return
        }
        func title(_ source: String) -> String {
            let name = source.components(separatedBy: " · ").dropFirst().joined(separator: " · ")
            let unseen = readerUnseen[source, default: 0]
            return (name.isEmpty ? source : name) + (unseen > 0 ? " (\(unseen) new)" : "")
        }
        let layout = readerTabLayout(sessions)
        let titles = ["All"] + layout.shown.map(title) +
            (layout.overflow.isEmpty ? [] : ["+\(layout.overflow.count) ▾"])
        let selected = readerSession.flatMap { layout.shown.firstIndex(of: $0) }
            .map { $0 + 1 } ?? 0
        let indexes = readerIndexes(readerSession)
        let status: String
        if readerLive {
            let working = readerSession.map(readerSessionWorking) ?? false
            status = "● Live" + (working ? " · working now" : "")
        } else if let position = indexes.firstIndex(of: compactIndex) {
            status = "❚❚ Paused · message \(position + 1) of \(indexes.count)"
        } else {
            status = "❚❚ Paused"
        }
        fullMessageView.setSessions(titles, selected: selected, status: status,
                                    live: readerLive, showJump: !readerLive,
                                    width: detailWidth,
                                    toolTips: ["All sessions"] + layout.shown +
                                        (layout.overflow.isEmpty ? [] : ["More chats"]),
                                    working: [false] + layout.shown.map(readerSessionWorking) +
                                        (layout.overflow.isEmpty ? [] : [false]),
                                    overflowTitles: layout.overflow.map(title),
                                    overflowWorking: layout.overflow.map(readerSessionWorking))
    }

    /// At most two chats fit one row beside All and "+N ▾"; the rest are in
    /// the "+N" menu. The open chat is always shown, and order stays stable.
    private static let readerShownTabLimit = 2

    private func readerTabLayout(_ sessions: [String]) -> (shown: [String], overflow: [String]) {
        var shown = Array(sessions.prefix(Self.readerShownTabLimit))
        if let open = readerSession, sessions.contains(open), !shown.contains(open),
           !shown.isEmpty {
            shown[shown.count - 1] = open
            shown.sort { sessions.firstIndex(of: $0)! < sessions.firstIndex(of: $1)! }
        }
        return (shown, sessions.filter { !shown.contains($0) })
    }

    /// Shows the newest message of the reader's session (or its activity when
    /// it has none yet) and follows it live.
    private func showReaderLatest() {
        readerShowsNote = false
        readerLive = true
        if let session = readerSession { readerUnseen[session] = 0 } else { readerUnseen = [:] }
        if let latest = readerIndexes(readerSession).last {
            compactIndex = latest
            selectedMessageChanged()
        } else if let session = readerSession {
            let snapshot = readerActivitySnapshot(session)
            messageReaderSnapshot = snapshot
            fullMessageView.show(source: snapshot.source, text: snapshot.text,
                                 kind: snapshot.kind, tone: snapshot.tone)
            refreshReaderChrome()
            publishAPI()
        }
    }

    private func readerActivitySnapshot(_ source: String) -> MessageReaderSnapshot {
        let working = readerSessionWorking(readerSessionKey(source))
        let text = working
            ? "Working…\n\nThe provider hides its thinking for this turn. Replies are still checked."
            : "No readable message from this session yet."
        return MessageReaderSnapshot(source: source, text: text, kind: "activity", tone: .normal)
    }

    /// Tab 0 is All, then the shown chats, then the "+N" menu's chats.
    private func selectReaderTab(_ index: Int) {
        let layout = readerTabLayout(readerSessions())
        let order = layout.shown + layout.overflow
        readerSession = index >= 1 && order.indices.contains(index - 1) ? order[index - 1] : nil
        showReaderLatest()
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
                                             kind: preview.readerKind,
                                             tone: preview.readerTone)
        } else if !compactMode, compactIndex >= 0,
                  compactIndex < eventPreviews.count {
            let preview = eventPreviews[compactIndex]
            openedIndex = compactIndex
            snapshot = MessageReaderSnapshot(source: preview.displaySource,
                                             text: preview.detailText,
                                             kind: preview.readerKind,
                                             tone: preview.readerTone)
        } else if let source = operationState.activityDisplaySource {
            snapshot = operationState.activeSources.contains(source)
                ? readerActivitySnapshot(source)
                : MessageReaderSnapshot(
                    source: source,
                    text: "Working: " + operationState.activeSources.joined(separator: " • ") +
                        "\n\nThe providers hide their thinking for these turns. Replies are still checked.",
                    kind: "activity", tone: .normal)
        } else {
            guard compactIndex >= 0, compactIndex < eventPreviews.count else { return }
            let preview = eventPreviews[compactIndex]
            openedIndex = compactIndex
            snapshot = MessageReaderSnapshot(source: preview.displaySource,
                                             text: preview.detailText,
                                             kind: preview.readerKind,
                                             tone: preview.readerTone)
        }
        presentReader(snapshot, openedIndex: openedIndex)
    }

    /// Opens the reader on `snapshot`; `openedIndex` is its history item, if any.
    /// `followLive: false` keeps a fixed note (such as "No violations yet.")
    /// on screen instead of following the newest message.
    private func presentReader(_ snapshot: MessageReaderSnapshot, openedIndex: Int?,
                               followLive: Bool = true) {
        if let openedIndex { markViolationReviewed(at: openedIndex) }
        // The reader opens on this message's session; it follows that session
        // live only when this is its newest message.
        // An aggregate status ("Claude · 2 active") is not a session: with no
        // single readable message the reader opens on All.
        readerSession = openedIndex.map { readerSessionKey(eventPreviews[$0].source) }
            ?? (operationState.activeSources.contains(snapshot.source)
                ? readerSessionKey(snapshot.source) : nil)
        readerShowsNote = !followLive
        readerLive = followLive &&
            (openedIndex == nil || openedIndex == readerIndexes(readerSession).last)
        readerUnseen = [:]
        messageReaderSnapshot = snapshot
        fullMessageView.show(source: snapshot.source, text: snapshot.text,
                             kind: snapshot.kind, tone: snapshot.tone)
        peekMode = false
        messageMode = true
        refreshReaderChrome()
        (panel.contentView as? CompactInteractionView)?.dragOnly = false
        peekBar.isHidden = true
        fullMessageBottom.isActive = true
        fullMessageView.isHidden = false
        detailHeader.isHidden = true
        scrollView.isHidden = true
        detailHeaderLayout.setActive(false, width: detailWidth)
        peekTicker.setActive(false)
        panel.becomesKeyOnlyIfNeeded = false
        fitReaderToText()
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
        let filters: [HistoryFilter] = [.all, .violations, .archive]
        guard filters.indices.contains(sender.selectedSegment) else { return }
        api.perform(.historyFilter(filters[sender.selectedSegment].rawValue), origin: .appKit)
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
        if messageMode {
            let indexes = readerIndexes(readerSession)
            guard let position = indexes.firstIndex(of: compactIndex), position > 0 else { return }
            compactIndex = indexes[position - 1]
            selectedMessageChanged()
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
        if messageMode {
            let indexes = readerIndexes(readerSession)
            guard let position = indexes.firstIndex(of: compactIndex),
                  position + 1 < indexes.count else { return }
            compactIndex = indexes[position + 1]
            selectedMessageChanged()
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
        readerShowsNote = false
        if messageMode, compactIndex >= 0, compactIndex < eventPreviews.count {
            let preview = eventPreviews[compactIndex]
            let snapshot = MessageReaderSnapshot(source: preview.displaySource,
                                                 text: preview.detailText,
                                                 kind: preview.readerKind,
                                                 tone: preview.readerTone)
            messageReaderSnapshot = snapshot
            fullMessageView.show(source: snapshot.source, text: snapshot.text,
                                 kind: snapshot.kind, tone: snapshot.tone)
            readerLive = compactIndex == readerIndexes(readerSession).last
            if readerLive, let session = readerSession { readerUnseen[session] = 0 }
            refreshReaderChrome()
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
        historyFilter = .all
        unacknowledgedViolationIndex = nil
        showExpandedFeed()
    }

    private func showViolations() {
        if hiddenByUser { returnToHiddenOnClose = true }
        hiddenByUser = false
        historyFilter = .violations
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
        transitionPanel(to: max(360, expandedHeight), width: expandedWidth,
                        minSize: NSSize(width: expandedWidth, height: 300),
                        maxSize: maxSize)
        updateCardVisibility()
        unseenCount = 0
        updateLatestButton()
        if let latest = visibleEventIndexes.last { selectExpandedMessage(at: latest) }
    }

    /// Every card, event and system, in insertion order.
    private var feedOrder: [EventCard] = []

    /// Cards in the feed in the same sense as before BUG-086: every created
    /// card plus the violation empty state while it is in the stack.
    private var feedCardCount: Int {
        feedOrder.count + (violationEmptyState.superview === feedStack ? 1 : 0)
    }

    /// Only displayed cards stay in the feed stack. A hidden arranged subview
    /// is detached from stack layout but keeps its subtree and constraints in
    /// the window's layout engine, so 500 retained violation cards made every
    /// layout pass take seconds (BUG-086). Detached cards keep their content
    /// and state; attaching restores insertion order and the width constraint
    /// that removal from the stack deactivated.
    private func syncCardAttachment() {
        for (position, card) in feedOrder.enumerated() {
            let attached = card.superview === feedStack
            if card.isHidden, attached {
                feedStack.removeArrangedSubview(card)
                card.removeFromSuperview()
            } else if !card.isHidden, !attached {
                // Newest first: every newer attached card sits above this one,
                // below the empty state when that is shown.
                let attachedAfter = feedOrder[(position + 1)...]
                    .filter { $0.superview === feedStack }.count
                let base = violationEmptyState.superview === feedStack ? 1 : 0
                feedStack.insertArrangedSubview(card, at: base + attachedAfter)
                // Violation rows form one list with hairline separators.
                if card.isListRow { feedStack.setCustomSpacing(2, after: card) }
                card.widthAnchor.constraint(
                    equalTo: feedStack.widthAnchor,
                    constant: -feedStack.edgeInsets.left - feedStack.edgeInsets.right)
                    .isActive = true
            }
        }
    }

    /// Like cards, the empty state leaves the stack when hidden: its hidden
    /// width chain (text cap + margins) otherwise held the history at 510 pt.
    private func setViolationEmptyStateAttached(_ attached: Bool) {
        let isAttached = violationEmptyState.superview === feedStack
        if attached, !isAttached {
            feedStack.insertArrangedSubview(violationEmptyState, at: 0)
            violationEmptyState.widthAnchor.constraint(
                equalTo: feedStack.widthAnchor,
                constant: -feedStack.edgeInsets.left - feedStack.edgeInsets.right)
                .isActive = true
        } else if !attached, isAttached {
            feedStack.removeArrangedSubview(violationEmptyState)
            violationEmptyState.removeFromSuperview()
        }
    }

    private func updateCardVisibility() {
        if compactMode {
            if !eventCards.isEmpty {
                compactIndex = min(max(0, compactIndex), eventCards.count - 1)
            }
            // The compact controls show navigation and settings only; the
            // message itself is in the ticker and the reader (UI checklist).
            for card in eventCards { card.isHidden = true }
            for card in systemCards { card.isHidden = true }
            syncCardAttachment()
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
            let tabs = violationTabs()
            for (index, card) in eventCards.enumerated() {
                card.isHidden = !historyIncludes(eventPreviews[index], tabs: tabs)
            }
            for card in systemCards {
                card.isHidden = historyFilter != .all || !eventCards.isEmpty
            }
            syncCardAttachment()
            switch historyFilter {
            case .all: positionLabel.stringValue = "All \(eventCards.count)"
            case .violations: positionLabel.stringValue = "Violations \(tabs.recent.count)"
            case .archive: positionLabel.stringValue = "Archive \(tabs.archived.count)"
            }
            previousButton.isEnabled = false
            nextButton.isEnabled = false
            expandButton.isHidden = true
            restartTickerButton.isEnabled = false
            latestButton.isHidden = unseenCount == 0
            let indexes = visibleEventIndexes
            if !indexes.contains(compactIndex), let latest = indexes.last {
                compactIndex = latest
            }
        }
        let tabs = violationTabs()
        violationEmptyState.show(
            empty: historyFilter == .archive
                ? "No archived violations." : "No violations in the last hour.",
            storageError: violationStore.lastError)
        let tabIsEmpty = historyFilter == .archive
            ? tabs.archived.isEmpty : tabs.recent.isEmpty
        let showViolationEmptyState = !compactMode && historyFilter != .all &&
            (tabIsEmpty || violationStore.lastError != nil)
        violationEmptyState.isHidden = !showViolationEmptyState
        setViolationEmptyStateAttached(showViolationEmptyState)
        navigationGroup.isHidden = !compactMode
        historyFilterControl.isHidden = compactMode
        // History is a reading/filtering surface. Prompt configuration and
        // display settings belong to the dedicated controls/ticker surfaces;
        // placing them beside history filters makes their actions ambiguous.
        checkRulesButton.isHidden = !compactMode
        positionButton.isHidden = !compactMode
        historyFilterControl.selectedSegment = [HistoryFilter.all, .violations, .archive]
            .firstIndex(of: historyFilter) ?? 0
        historyFilterControl.setLabel("All \(eventCards.count)", forSegment: 0)
        setViolationTabLabels(tabs)
        scheduleArchiveBoundary(tabs)
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
        // Compact controls show no message card, so nothing below the header.
        let previewHeight: CGFloat = feedStack.arrangedSubviews.contains { !$0.isHidden }
            ? min(CompactWindowSizing.messagePreviewHeight, ceil(feedStack.fittingSize.height))
            : 0
        let targetHeight = CompactWindowSizing.headerHeight(for: detailWidth) +
            previewHeight
        guard abs(panel.frame.height - targetHeight) > 0.5 else { return }
        transitionPanel(to: targetHeight, width: detailWidth,
                        minSize: NSSize(width: detailWidth, height: targetHeight),
                        maxSize: NSSize(width: detailWidth, height: targetHeight),
                        animated: false)
    }

    private func updatePeekHeader(source: String) {
        peekProviderIcon.update(source: source)
        // A sub-agent shows as its chat; the full source stays in the tooltip.
        // The icon names the provider, so the one-line ticker shows only the
        // chat name (the app's own "Provider · Chat" label), as in the mockup.
        peekSourceKey = readerSessionKey(source)
        let chat = peekSourceKey.components(separatedBy: " · ").dropFirst()
            .joined(separator: " · ")
        peekSourceLabel.stringValue = chat.isEmpty ? peekSourceKey : chat
        peekSourceLabel.toolTip = source
        peekBar.layoutSubtreeIfNeeded()
        peekToolbar.needsDisplay = true
        peekBar.needsDisplay = true
        peekBar.displayIfNeeded()
        CATransaction.flush()
    }

    private func captureWindowPNG(target: String) -> Data? {
        if target == "bubble" {
            guard violationBubble.isVisible else { return nil }
            return pngData(of: violationBubble.contentView, scale: 2)
        }
        let captureWindow: NSWindow?
        if usageWindow?.isVisible == true {
            captureWindow = usageWindow?.window
        } else if settingsWindow.isVisible {
            captureWindow = settingsWindow.window
        } else {
            captureWindow = panel
        }
        guard let window = captureWindow, let content = window.contentView else { return nil }
        // Settings: include the window frame, so the tab toolbar is captured.
        let view = window === settingsWindow.window ? (content.superview ?? content) : content
        return pngData(of: view, scale: window.backingScaleFactor)
    }

    private func pngData(of view: NSView, scale: CGFloat) -> Data? {
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
            fmt.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            fmt.dateFormat = "'Yesterday,' HH:mm"
        } else {
            fmt.dateFormat = "d MMM, HH:mm"
        }
        return fmt.string(from: date)
    }

    /// The history is newest first, so following new items means staying at
    /// the top of the (flipped) feed.
    private func nearTop() -> Bool {
        scrollView.contentView.bounds.minY < 64
    }

    /// "↑ N new" appears only when newer items arrived above the visible part.
    private func updateLatestButton() {
        latestButton.title = "↑ \(unseenCount) new"
        latestButton.isHidden = compactMode || unseenCount == 0
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
        // Newest first: the latest item is at the top in every mode.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        unseenCount = 0
        updateLatestButton()
        publishAPI()
    }

    @discardableResult
    private func addCard(source: String, event: UIEvent,
                         deferScrollAndLayout: Bool = false,
                         navigable: Bool = true) -> EventCard {
        // Scroll-following is for the expanded history only. In compact mode
        // MessageReaderSelection decides whether a new message is selected;
        // with no card shown there, "near bottom" was always true and a new
        // message replaced the open reader (frozen-reader regression).
        let follow = !compactMode && !deferScrollAndLayout &&
            (nearTop() || feedCardCount == 0)
        let card = EventCard(source: source, time: displayTime(event.timestamp), event: event)
        card.selectedRequested = { [weak self, weak card] in
            guard let self, let card,
                  let index = self.eventCards.firstIndex(where: { $0 === card }) else { return }
            self.selectExpandedMessage(at: index)
        }
        card.violationToggleRequested = { [weak self] in
            self?.api.perform(.toggleSelectedViolation, origin: .appKit)
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
        // A new card starts hidden and outside the feed stack;
        // updateCardVisibility attaches it when it is displayed. A bulk add
        // (launch restore, initial history) applies visibility once at the end
        // instead of once per card (BUG-086).
        card.isHidden = true
        feedOrder.append(card)
        if navigable {
            // History is one list of rows; violations restyle their row later.
            card.setThoughtRow()
            let wasFollowingLatest = eventCards.isEmpty || compactIndex == eventCards.count - 1
            eventCards.append(card)
            eventPreviews.append(MessagePreview(source: source, text: event.text,
                                                kind: event.kind))
            if MessageReaderSelection.shouldAdvanceForNewMessage(
                isReaderOpen: messageMode, wasFollowingLatest: wasFollowingLatest) {
                compactIndex = eventCards.count - 1
            } else if messageMode {
                // A live reader follows only its own session; anything else is
                // counted on its tab and never replaces what is being read.
                if readerLive, readerSession == nil || readerSession == readerSessionKey(source) {
                    compactIndex = eventCards.count - 1
                    DispatchQueue.main.async { [weak self] in self?.selectedMessageChanged() }
                } else {
                    // Updated before the next publish, so the count is never stale.
                    readerUnseen[readerSessionKey(source), default: 0] += 1
                    refreshReaderChrome()
                }
            }
        } else {
            systemCards.append(card)
        }
        if deferScrollAndLayout { return card }
        updateCardVisibility()
        feedView.layoutSubtreeIfNeeded()
        if follow {
            DispatchQueue.main.async { [weak self] in self?.scrollToLatest() }
        } else {
            unseenCount += 1
            updateLatestButton()
        }
        return card
    }

    private var visibleEventIndexes: [Int] {
        let tabs = violationTabs()
        return eventPreviews.indices.filter { historyIncludes(eventPreviews[$0], tabs: tabs) }
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
        // A detached card is not rendered; its content is laid out and
        // published when updateCardVisibility attaches it. Per-card publishes
        // during launch restore cost seconds (BUG-086).
        guard card.superview === feedStack else { return }
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
        _ = addCard(source: "Doublethink", event: event, navigable: false)
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
            if let summary = record.summary {
                preview.violationSummary = summary
                card.setViolationSummary(summary)
            }
        }
        if !violationRecords.isEmpty {
            compactIndex = eventCards.count - 1
        }
        updateCardVisibility()
    }

    private func updateViolationMenu() {
        let count = violationRecords.count
        let newCount = violationRecords.filter { $0.reviewedAt == nil }.count
        violationsMenuItem?.title = violationHistoryMenuTitle(
            recorded: count, unreviewed: newCount,
            storageUnavailable: violationStore.lastError != nil)
        violationsMenuItem?.toolTip = "Keeps the newest \(violationStore.limit) violations locally."
        violationsMenuItem?.isEnabled = true
        setViolationTabLabels(violationTabs())
        let hasUnacknowledged = newCount > 0
        // Brain when quiet; the bolt joins it while a violation is unreviewed.
        let glyph = statusGlyphImage(bolt: hasUnacknowledged)
        glyph.accessibilityDescription = hasUnacknowledged
            ? "Doublethink has a new violation" : "Doublethink"
        statusItem?.button?.image = glyph
        statusItem?.button?.title = violationStatusBadgeTitle(unreviewed: newCount)
        statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        if let button = statusItem?.button {
            if statusFlashActive {
                // The flash colors the shield and the count; it ends after
                // `flashDuration`, then the native foreground returns.
                button.contentTintColor = nil
                let image = statusFlashImage(
                    count: violationStatusBadgeTitle(unreviewed: newCount)
                        .trimmingCharacters(in: .whitespaces),
                    color: statusFlashColor)
                button.image = image
                // Checked once per drawn image (scanning pixels on every
                // publish slowed launch with 500 stored violations).
                statusFlashImageDrawsColor = !image.isTemplate &&
                    imageDrawsColor(image, statusFlashColor)
                button.title = ""
            } else {
                restoreNativeStatusItemForeground(button)
            }
        }
        statusItem?.button?.setAccessibilityLabel(count == 0
            ? "Doublethink, no recorded violations"
            : "Doublethink, \(newCount) new and \(count) recorded violation\(count == 1 ? "" : "s")")
        statusItem?.button?.toolTip = count == 0
            ? "Doublethink · no recorded violations"
            : "Doublethink · \(newCount) new · \(count) recorded"
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
        updateLatestButton()
        apiEvents.removeAll()
        feedOrder.removeAll()
        eventCards.removeAll()
        eventPreviews.removeAll()
        systemCards.removeAll()
        presentationKeys.removeAll()
        operationState.resetPending()
        unacknowledgedViolationIndex = nil
        historyFilter = .all
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
            panel.title = "⚠ Doublethink violation — \(violationRecords.count) recorded"
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
            updatePeekHeader(source: "Doublethink")
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
                           preview: MessagePreview, evidence: EvaluationRecord) {
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
        // The badge and menu derive from violationRecords. Update them before
        // updateCardVisibility publishes, so no published state pairs the new
        // count with the previous badge.
        updateViolationMenu()
        removeCardsForDeletedViolations()
        alertCount = violationRecords.count
        if let index = eventPreviews.firstIndex(where: { $0 === preview }) {
            if priorSelection == index, index > 0 { restoreSelection = index - 1 }
            // A just-arrived violation never takes over the ticker merely
            // because it is the newest record.
            if compactIndex == index, index > 0 { compactIndex = index - 1 }
        }
        compactIndex = restoreSelection
        updateCardVisibility()
        requestViolationSummary(decision, record: record, evidence: evidence,
                                card: card, preview: preview)
        if violationFlashEnabled || violationBubbleEnabled {
            NSAccessibility.post(element: panel as Any,
                                 notification: .announcementRequested,
                                 userInfo: [
                                    .announcement: "New Doublethink violation from \(preview.source). \(decision.reason)",
                                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                                 ])
            startViolationAlert(record)
        }
        panel.title = "⚠ Doublethink alert — \(alertCount)"
        apiEvents.append([
            "kind": "drift-alert", "text": decision.reason,
            "evidence": decision.evidence, "source": preview.source,
            "provider": provider, "latencyMs": Int(ms),
        ])
        updateViolationMenu()
        updateWindowTitle()
        publishAPI()
    }

    private var alertDurations: (flash: TimeInterval, bubble: TimeInterval) {
        guard ISOLATED_E2E else {
            return (ViolationFlashPreference.duration, ViolationBubblePreference.duration)
        }
        // Isolated tests shorten the steps; the visual check passes the real
        // "3,5" so the guest screen can be captured during each step.
        let parts = (ProcessInfo.processInfo.environment["DOUBLETHINK_E2E_ALERT_SECONDS"] ?? "")
            .split(separator: ",").compactMap { TimeInterval(String($0)) }
        return parts.count == 2 ? (parts[0], parts[1]) : (1.0, 1.5)
    }

    /// The flash step (red menu-bar icon) and then the bubble step, each only
    /// when its switch is on. A newer violation restarts them with its own
    /// content.
    private func startViolationAlert(_ record: ViolationRecord) {
        violationAlertGeneration += 1
        let generation = violationAlertGeneration
        violationBubble.hide()
        bubbleViolationID = record.id
        let durations = alertDurations
        let showBubble = violationBubbleEnabled
        guard violationFlashEnabled else {
            if showBubble { showViolationBubble(record, generation: generation,
                                                duration: durations.bubble) }
            publishAPI()
            return
        }
        statusFlashActive = true
        updateViolationMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + durations.flash) { [weak self] in
            guard let self, generation == self.violationAlertGeneration else { return }
            self.statusFlashActive = false
            self.updateViolationMenu()
            if showBubble {
                self.showViolationBubble(record, generation: generation,
                                         duration: durations.bubble)
            } else {
                self.endViolationAlert()
            }
        }
        publishAPI()
    }

    private func showViolationBubble(_ record: ViolationRecord, generation: Int,
                                     duration: TimeInterval) {
        hoverWork?.cancel()
        bubbleMode = .alert
        violationBubble.clicked = { [weak self] in
            self?.api.perform(.openViolationBubble, origin: .appKit)
        }
        // The session name, as on the reader chips (the source is the app's
        // own "Provider · Session" label).
        let session = record.source.components(separatedBy: " · ").dropFirst()
            .joined(separator: " · ")
        let title = "Violation · " + (session.isEmpty ? record.source : session)
        let quote = violationRecords.first { $0.id == record.id }?.summary ??
            (record.evidence.isEmpty ? "Why: \(record.reason)" : "“\(record.evidence)”")
        // A status item macOS hid (full menu bar) is not a usable anchor.
        violationBubble.show(title: title, quote: quote, below: statusIconAnchor())
        publishAPI()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, generation == self.violationAlertGeneration else { return }
            self.endViolationAlert()
        }
    }

    private func endViolationAlert() {
        violationAlertGeneration += 1
        violationBubble.hide()
        bubbleMode = .none
        bubbleViolationID = nil
        if statusFlashActive {
            statusFlashActive = false
            updateViolationMenu()
        }
        publishAPI()
    }

    /// The one-line summary arrives after the violation is shown (about
    /// 0.4 s); the quote stands in until then and when the request fails.
    private func requestViolationSummary(_ decision: EvaluationDecision,
                                         record: ViolationRecord,
                                         evidence: EvaluationRecord,
                                         card: EventCard, preview: MessagePreview) {
        summarizeViolation(decision, evidence: evidence, source: preview.source) {
            [weak self] summary in
            guard let self, let summary else { return }
            self.violationRecords = self.violationStore.setSummary(id: record.id,
                                                                   summary: summary)
            preview.violationSummary = summary
            card.setViolationSummary(summary)
            if self.messageMode, self.eventPreviews.indices.contains(self.compactIndex),
               self.eventPreviews[self.compactIndex] === preview {
                self.selectedMessageChanged()
                self.fitReaderToText()
            }
            if self.violationBubble.isVisible,
               (self.bubbleMode == .alert && self.bubbleViolationID == record.id) ||
               (self.bubbleMode == .hover && self.violationRecords.last?.id == record.id) {
                self.violationBubble.show(title: self.violationBubble.title, quote: summary,
                                          below: self.statusIconAnchor(),
                                          hint: self.violationBubble.hint)
            }
            self.apiEvents.append(["kind": "violation-summary", "source": preview.source,
                                   "text": summary])
            self.publishAPI()
        }
    }

    /// "Why and full message ▸" in the reader: the reader grows to show them.
    private func expandReaderViolationDetails() {
        guard messageMode, eventPreviews.indices.contains(compactIndex),
              eventPreviews[compactIndex].alarmActive else { return }
        eventPreviews[compactIndex].violationDetailsExpanded = true
        selectedMessageChanged()
        fitReaderToText()
    }

    /// The reader's height follows its text, between 118 and 420 points.
    private func fitReaderToText() {
        guard messageMode else { return }
        let readerHeight = fullMessageView.preferredHeight(forWidth: detailWidth)
        transitionPanel(to: readerHeight, width: detailWidth,
                        minSize: NSSize(width: detailWidth, height: 118),
                        maxSize: NSSize(width: detailWidth, height: 420))
    }

    /// A status item macOS hid (full menu bar) is not a usable anchor.
    private func statusIconAnchor() -> NSRect? {
        statusItem?.button?.window.flatMap { window in
            window.occlusionState.contains(.visible) ? window.frame : nil }
    }

    private func statusItemHoverChanged(_ inside: Bool) {
        pointerOnIcon = inside
        updateHoverBubble()
    }

    /// Resting on the icon for `hoverDelay` shows the last violation; it
    /// stays while the mouse is on the icon or the bubble and hides
    /// `hoverDelay` after it leaves both. A new violation's alert wins.
    private func updateHoverBubble() {
        hoverWork?.cancel()
        hoverWork = nil
        guard bubbleMode != .alert else { return }
        let showing = bubbleMode == .hover && violationBubble.isVisible
        let work: DispatchWorkItem
        if pointerOnIcon || (showing && pointerOnBubble) {
            guard !showing else { return }
            work = DispatchWorkItem { [weak self] in self?.showHoverBubble() }
        } else if showing {
            work = DispatchWorkItem { [weak self] in self?.hideHoverBubble() }
        } else {
            return
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
    }

    private func showHoverBubble() {
        guard pointerOnIcon, bubbleMode != .alert else { return }
        bubbleMode = .hover
        violationBubble.clicked = { [weak self] in
            self?.hideHoverBubble()
            self?.api.perform(.showLastViolation, origin: .appKit)
        }
        if let record = violationRecords.last {
            let session = record.source.components(separatedBy: " · ").dropFirst()
                .joined(separator: " · ")
            let title = "Last violation · " + (session.isEmpty ? record.source : session)
            let quote = record.summary ??
                (record.evidence.isEmpty ? "Why: \(record.reason)" : "“\(record.evidence)”")
            // The time stays readable on the last line, however long the chat name.
            violationBubble.show(title: title, quote: quote, below: statusIconAnchor(),
                                 hint: displayTime(record.timestamp) + " · Click to open")
        } else {
            violationBubble.show(title: "Doublethink", quote: "No violations yet.",
                                 below: statusIconAnchor())
        }
        publishAPI()
    }

    private func hideHoverBubble() {
        hoverWork?.cancel()
        hoverWork = nil
        guard bubbleMode == .hover else { return }
        violationBubble.hide()
        bubbleMode = .none
        publishAPI()
    }

    /// Clicking the bubble opens its violation in the reader.
    private func openBubbleViolation() {
        let id = bubbleViolationID
        endViolationAlert()
        if let id, let index = eventPreviews.firstIndex(where: { $0.violationID == id }) {
            openViolationReader(at: index)
        } else {
            showViolations()
        }
    }

    /// The newest stored violation, in the reader. The store keeps records
    /// in the order they were recorded, so the last one is the newest.
    private func showLastViolation() {
        if let id = violationRecords.last?.id,
           let index = eventPreviews.firstIndex(where: { $0.violationID == id }) {
            openViolationReader(at: index)
        } else {
            presentReader(MessageReaderSnapshot(source: "Doublethink", text: "No violations yet.",
                                                kind: "activity", tone: .normal),
                          openedIndex: nil, followLive: false)
            revealForExplicitRequest()
        }
    }

    private func openViolationReader(at index: Int) {
        unacknowledgedViolationIndex = index
        showCurrentMessage()
        unacknowledgedViolationIndex = nil
        revealForExplicitRequest()
    }

    /// An explicit Show/Open action is the only thing that undoes Hide.
    private func revealForExplicitRequest() {
        // Opened from the bubble or the menu bar while hidden: closing it
        // returns to hidden (the user's Hide is remembered).
        if hiddenByUser { returnToHiddenOnClose = true }
        hiddenByUser = false
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        publishAPI()
    }

    /// Violation ids per tab, from the store (the same source as the badge
    /// and menu counts).
    private func violationTabs(now: Date = Date())
        -> (recent: Set<String>, archived: Set<String>, undated: Int) {
        var recent = Set<String>(), archived = Set<String>(), undated = 0
        for record in violationRecords {
            switch violationArchived(record, now: now) {
            case .some(true): archived.insert(record.id)
            case .some(false): recent.insert(record.id)
            case .none:
                recent.insert(record.id)
                undated += 1
            }
        }
        return (recent, archived, undated)
    }

    /// Record times parsed once per record (a record's timestamp never changes).
    private var violationDates: [String: Date?] = [:]

    private func violationArchived(_ record: ViolationRecord, now: Date) -> Bool? {
        let date: Date?
        if let cached = violationDates[record.id] {
            date = cached
        } else {
            date = parsedRecordTimestamp(record.timestamp)
            violationDates[record.id] = date
        }
        guard let date else { return nil }
        return now.timeIntervalSince(date) >= violationArchiveAge
    }

    private func historyIncludes(
        _ preview: MessagePreview,
        tabs: (recent: Set<String>, archived: Set<String>, undated: Int)) -> Bool {
        switch historyFilter {
        case .all: return true
        case .violations:
            return preview.alarmActive && preview.violationID.map(tabs.recent.contains) == true
        case .archive:
            return preview.alarmActive && preview.violationID.map(tabs.archived.contains) == true
        }
    }

    private func setViolationTabLabels(
        _ tabs: (recent: Set<String>, archived: Set<String>, undated: Int)) {
        historyFilterControl?.setLabel("Violations \(tabs.recent.count)", forSegment: 1)
        historyFilterControl?.setLabel("Archive \(tabs.archived.count)", forSegment: 2)
    }

    private func violationTabCountsJSON() -> [String: Int] {
        let tabs = violationTabs()
        return ["recent": tabs.recent.count, "archived": tabs.archived.count,
                "withoutReadableTimestamp": tabs.undated]
    }

    /// Re-sorts the tabs exactly when the oldest recent violation turns one
    /// hour old, so it moves to Archive even while history is open.
    private func scheduleArchiveBoundary(
        _ tabs: (recent: Set<String>, archived: Set<String>, undated: Int)) {
        archiveBoundaryTimer?.invalidate()
        archiveBoundaryTimer = nil
        let next = violationRecords
            .filter { tabs.recent.contains($0.id) }
            .compactMap { violationDates[$0.id] ?? nil }
            .map { $0.addingTimeInterval(violationArchiveAge) }
            .min()
        guard let next else { return }
        let timer = Timer(fire: max(next, Date().addingTimeInterval(0.05)), interval: 0,
                          repeats: false) { [weak self] _ in
            self?.updateCardVisibility()
            self?.updateViolationMenu()
        }
        RunLoop.main.add(timer, forMode: .common)
        archiveBoundaryTimer = timer
    }

    private func showCheckFailure(_ message: String, _ ms: Double,
                                  card: EventCard, preview: MessagePreview) {
        preview.evaluation = .failed(message)
        card.setError("Doublethink check error · \(message) · \(Int(ms)) ms")
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
                               timestamp: block.ts, card: card, preview: preview,
                               evidence: block.evaluationRecord)
            case .scored(let decision, let provider):
                existingPreview?.evaluation = .clear
                existingCard?.setFooter("No violation",
                                        detail: "Checked by \(provider) in \(Int(ms)) ms")
                self.apiEvents.append([
                    "kind": "drift-clean", "text": "no alert", "provider": provider,
                    "rejectedClaims": decision.rejectedClaims,
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
        refreshReaderChrome()
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
        let isInitialHistoryBatch = arrived.count > 20 && feedCardCount <= 1
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
                guard writtenSinceLaunch(block.ts, launchedAt: launchedAt) else {
                    apiEvents.append([
                        "kind": "drift-skipped-old", "source": source,
                        "reason": parsedRecordTimestamp(block.ts) == nil
                            ? "no readable timestamp" : "written before launch",
                        "evidenceType": block.evaluationRecord.eventType,
                    ])
                    continue
                }
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
            guard writtenSinceLaunch(block.ts, launchedAt: launchedAt) else {
                let unreadable = parsedRecordTimestamp(block.ts) == nil
                card.setFooter(unreadable
                    ? "Not checked · the record has no readable timestamp"
                    : "Not checked · written before Doublethink started")
                apiEvents.append([
                    "kind": "drift-skipped-old", "source": source,
                    "reason": unreadable ? "no readable timestamp" : "written before launch",
                    "evidenceType": block.evaluationRecord.eventType,
                ])
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
            updateCardVisibility()
            feedView.layoutSubtreeIfNeeded()
            scrollToLatest()
        }
        if monitorsReady { initialScanComplete = true }
        publishAPI()
    }
}

extension HUD: NSMenuDelegate {
    /// Clicking the icon opens its menu; the hover bubble gives way.
    func menuWillOpen(_ menu: NSMenu) {
        pointerOnIcon = false
        hideHoverBubble()
    }
}
