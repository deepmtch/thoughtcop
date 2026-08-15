// Single-line, accessibility-aware ticker used by the collapsed HUD.

import AppKit
import QuartzCore

enum TickerTiming {
    static let startPause: TimeInterval = 1.2
    static let endPause: TimeInterval = 0.8
    static let returnDuration: TimeInterval = 0.15
}

enum TickerSpeed: String, CaseIterable {
    case slow, normal, fast

    var title: String { rawValue.capitalized }
    var pointsPerSecond: CGFloat {
        switch self {
        case .slow: return 22
        case .normal: return 34
        case .fast: return 52
        }
    }
}

func normalizedTickerText(_ text: String) -> String {
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let plain: String
    if let parsed = try? AttributedString(markdown: text, options: options) {
        plain = String(parsed.characters)
    } else {
        plain = text
    }
    // Transcript chunks can arrive while a Markdown span is incomplete, and
    // Foundation intentionally preserves unmatched delimiters. The ticker is
    // plain text, so remove the small inline subset that can otherwise leak.
    let inlinePatterns = [
        ("\\*\\*([^*]+)\\*\\*", "$1"),
        ("__([^_]+)__", "$1"),
        ("`([^`]+)`", "$1"),
        ("\\[([^]]+)\\]\\([^)]+\\)", "$1"),
        ("^\\s{0,3}#{1,6}\\s+", ""),
    ]
    let stripped = inlinePatterns.reduce(plain) { value, pattern in
        value.replacingOccurrences(of: pattern.0, with: pattern.1,
                                   options: .regularExpression)
    }
    return stripped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

func presentableTickerText(_ text: String) -> String? {
    let normalized = normalizedTickerText(text)
    return normalized.isEmpty ? nil : normalized
}

func visibleTickerTextWidth(textWidth: CGFloat, viewportWidth: CGFloat,
                            translation: CGFloat) -> CGFloat {
    max(0, min(viewportWidth, textWidth + translation) - max(0, translation))
}

final class TickerView: NSView {
    private var active = false
    private var optionsObserver: NSObjectProtocol?
    private var motionTimer: Timer?
    private var cycleStartedAt: CFTimeInterval = 0
    private var textStorage = ""
    private var attributedText = NSAttributedString(string: "")
    private var measuredTextWidth: CGFloat = 0
    private var measuredTextHeight: CGFloat = 0
    private var translation: CGFloat = 0
    var speed: TickerSpeed = .normal { didSet { restart() } }
    var foregroundColor: NSColor = .labelColor {
        didSet { rebuildAttributedText() }
    }
    var textFont: NSFont { .systemFont(ofSize: 14, weight: .regular) }

    var text: String {
        get { textStorage }
        set {
            guard let normalized = presentableTickerText(newValue) else { return }
            resetToBeginning()
            textStorage = normalized
            rebuildAttributedText()
            setAccessibilityValue(normalized)
            needsLayout = true
            layoutSubtreeIfNeeded()
            restart()
        }
    }

    private var textFrame: NSRect {
        NSRect(x: translation,
               y: floor((bounds.height - measuredTextHeight) / 2),
               width: max(measuredTextWidth, bounds.width),
               height: measuredTextHeight)
    }
    var isOverflowing: Bool { measuredTextWidth > bounds.width + 0.5 }
    var layoutMetrics: (viewport: NSRect, label: NSRect) {
        (bounds, textFrame)
    }
    var presentationMetrics: (translation: CGFloat, textWidth: CGFloat,
                              visibleWidth: CGFloat) {
        return (translation, measuredTextWidth,
                visibleTickerTextWidth(textWidth: measuredTextWidth,
                                       viewportWidth: bounds.width,
                                       translation: translation))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Scrolling message")

        optionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.restart() }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        motionTimer?.invalidate()
        if let optionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(optionsObserver)
        }
    }

    override func layout() {
        super.layout()
        measureAttributedText()
        restart()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        attributedText.draw(at: textFrame.origin)
        NSGraphicsContext.restoreGraphicsState()
    }

    func setActive(_ active: Bool) {
        guard self.active != active else {
            if active { restart() }
            return
        }
        self.active = active
        restart()
    }

    func restart() {
        resetToBeginning()
        guard active,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              isOverflowing else { return }
        cycleStartedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.advanceAnimation(now: CACurrentMediaTime())
        }
        motionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func resetToBeginning() {
        motionTimer?.invalidate()
        motionTimer = nil
        setTranslation(0)
    }

    private func rebuildAttributedText() {
        attributedText = NSAttributedString(
            string: textStorage,
            attributes: [.font: textFont, .foregroundColor: foregroundColor])
        measureAttributedText()
        needsDisplay = true
    }

    private func measureAttributedText() {
        let size = attributedText.size()
        measuredTextWidth = ceil(size.width)
        measuredTextHeight = min(bounds.height, ceil(size.height))
    }

    private func setTranslation(_ x: CGFloat) {
        guard abs(translation - x) > 0.01 else { return }
        translation = x
        // Draw the visible string at its current offset every frame. This avoids
        // moving a partially rasterized, clipped NSTextField backing store.
        needsDisplay = true
    }

    private func advanceAnimation(now: CFTimeInterval) {
        guard active,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              measuredTextWidth > bounds.width + 0.5 else {
            resetToBeginning()
            return
        }

        let distance = measuredTextWidth - bounds.width
        let travelDuration = TimeInterval(distance / speed.pointsPerSecond)
        let total = TickerTiming.startPause + travelDuration +
            TickerTiming.endPause + TickerTiming.returnDuration
        guard total > 0 else {
            resetToBeginning()
            return
        }

        let elapsed = (now - cycleStartedAt).truncatingRemainder(dividingBy: total)
        let translation: CGFloat
        if elapsed < TickerTiming.startPause {
            translation = 0
        } else if elapsed < TickerTiming.startPause + travelDuration {
            let travelElapsed = elapsed - TickerTiming.startPause
            translation = -min(distance, CGFloat(travelElapsed) * speed.pointsPerSecond)
        } else if elapsed < TickerTiming.startPause + travelDuration +
                    TickerTiming.endPause {
            translation = -distance
        } else {
            let returnElapsed = elapsed - TickerTiming.startPause - travelDuration -
                TickerTiming.endPause
            let progress = min(1, CGFloat(returnElapsed / TickerTiming.returnDuration))
            translation = -distance * (1 - progress)
        }
        setTranslation(translation)
    }
}
