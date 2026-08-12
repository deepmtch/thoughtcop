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

final class TickerView: NSView {
    private let viewport = NSView()
    private let label = NSTextField(labelWithString: "")
    private var active = false
    private var optionsObserver: NSObjectProtocol?
    var speed: TickerSpeed = .normal { didSet { restart() } }
    var foregroundColor: NSColor = .labelColor {
        didSet { label.textColor = foregroundColor }
    }

    var text: String {
        get { label.stringValue }
        set {
            guard let normalized = presentableTickerText(newValue) else { return }
            label.stringValue = normalized
            needsLayout = true
            layoutSubtreeIfNeeded()
            restart()
        }
    }

    var isOverflowing: Bool { label.frame.width > viewport.bounds.width + 0.5 }
    var layoutMetrics: (viewport: NSRect, label: NSRect) {
        (viewport.bounds, label.frame)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        viewport.wantsLayer = true
        viewport.layer?.masksToBounds = true
        addSubview(viewport)

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.cell?.wraps = false
        label.cell?.isScrollable = false
        label.wantsLayer = true
        viewport.addSubview(label)

        optionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.restart() }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let optionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(optionsObserver)
        }
    }

    override func layout() {
        super.layout()
        viewport.frame = bounds
        let fitting = label.fittingSize
        let labelHeight = min(bounds.height, ceil(fitting.height))
        label.frame = NSRect(x: 0, y: floor((bounds.height - labelHeight) / 2),
                             width: max(ceil(fitting.width), bounds.width),
                             height: labelHeight)
        restart()
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
        label.layer?.removeAnimation(forKey: "ticker")
        guard active,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              isOverflowing else { return }

        let distance = label.frame.width - viewport.bounds.width
        let travelDuration = TimeInterval(distance / speed.pointsPerSecond)
        let total = TickerTiming.startPause + travelDuration +
            TickerTiming.endPause + TickerTiming.returnDuration
        guard total > 0 else { return }

        let reachedEnd = (TickerTiming.startPause + travelDuration) / total
        let leaveEnd = (TickerTiming.startPause + travelDuration +
                        TickerTiming.endPause) / total
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -distance, -distance, 0]
        animation.keyTimes = [0,
                              NSNumber(value: TickerTiming.startPause / total),
                              NSNumber(value: reachedEnd),
                              NSNumber(value: leaveEnd),
                              1]
        animation.duration = total
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = false
        label.layer?.add(animation, forKey: "ticker")
    }
}
