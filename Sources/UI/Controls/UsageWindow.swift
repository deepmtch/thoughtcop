// Usage and cost: today and this month, from provider-reported tokens and
// provider-published prices (UsageStore).

import AppKit

final class UsageWindow: NSWindowController, NSWindowDelegate {
    private let todayCost = NSTextField(labelWithString: "")
    private let todayChecks = NSTextField(labelWithString: "")
    private let monthCost = NSTextField(labelWithString: "")
    private let monthChecks = NSTextField(labelWithString: "")
    private let secondChecks = NSTextField(labelWithString: "")
    private let tokens = NSTextField(labelWithString: "")
    private let model = NSTextField(labelWithString: "")
    private let price = NSTextField(labelWithString: "")
    var closed: (() -> Void)?

    init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                             styleMask: [.titled, .closable, .utilityWindow],
                             backing: .buffered, defer: false)
        window.title = "Usage"
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        super.init(window: window)
        window.delegate = self
        build(in: window)
    }

    required init?(coder: NSCoder) { nil }

    private func metric(_ title: String, value: NSTextField, detail: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        value.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, value, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 8
        stack.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        return stack
    }

    private func row(_ title: String, _ value: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        value.alignment = .right
        value.lineBreakMode = .byTruncatingMiddle
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [label, NSView(), value])
        stack.orientation = .horizontal
        return stack
    }

    private func build(in window: NSWindow) {
        guard let content = window.contentView else { return }
        // Same surface as the other editors (draws in captures and dark mode).
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let metrics = NSStackView(views: [
            metric("Today", value: todayCost, detail: todayChecks),
            metric("This month", value: monthCost, detail: monthChecks),
        ])
        metrics.distribution = .fillEqually
        metrics.spacing = 10
        let note = NSTextField(wrappingLabelWithString:
            "Counted from the tokens the provider reports for each check, times the provider's published price. Local-only mode costs nothing.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let done = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), done])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [
            metrics, row("Second checks", secondChecks), row("Tokens today", tokens),
            row("Model", model), row("Price", price), note, buttons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(14, after: metrics)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -14),
            metrics.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        for view in stack.arrangedSubviews where view is NSStackView && view !== metrics {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func refresh(backends: [DriftBackend]) {
        let summary = UsageStore.shared.summary()
        // Without a published price the amount is a dash, never an estimate;
        // the reason is stated in the line below it.
        func amount(_ cost: Double?) -> String { cost == nil ? "—" : formattedCost(cost) }
        func detail(_ period: UsageSummary) -> String {
            "\(period.totals.checks) checks" + (period.costUSD == nil ? " · price not published" : "")
        }
        todayCost.stringValue = amount(summary.today.costUSD)
        todayChecks.stringValue = detail(summary.today)
        monthCost.stringValue = amount(summary.month.costUSD)
        monthChecks.stringValue = detail(summary.month)
        secondChecks.stringValue = "\(summary.today.totals.secondChecks) today"
        tokens.stringValue = "\(compact(summary.today.totals.inputTokens)) in · " +
            "\(compact(summary.today.totals.outputTokens)) out"
        let primary = backends.first
        model.stringValue = primary?.label ?? "Checks off"
        if let primary, let published = UsageStore.shared.price(for: primary.label) {
            price.stringValue = String(format: "$%.2f / $%.2f per 1M tokens",
                                       published.input * 1_000_000,
                                       published.output * 1_000_000)
        } else {
            price.stringValue = primary == nil ? "—" : "not published"
        }
    }

    private func compact(_ value: Int) -> String {
        value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : "\(value)"
    }

    func show(backends: [DriftBackend]) {
        refresh(backends: backends)
        window?.center()
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
    }

    @objc private func done(_ sender: Any?) { window?.close() }

    func windowWillClose(_ notification: Notification) { closed?() }

    var isVisible: Bool { window?.isVisible == true }
}

/// The menu-bar line: actionable, opens the Usage window.
func usageMenuTitle(_ today: UsageSummary) -> String {
    "Usage Today: \(formattedCost(today.costUSD)) · \(today.totals.checks) checks…"
}
