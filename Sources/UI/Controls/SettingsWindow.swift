// One Settings window (menu bar › Settings…, ⌘,, and the ticker's ⚙) with
// General, Alerts, Rules and Keys tabs. General and Alerts apply at once;
// Rules and Keys keep their explicit Save, and unsaved edits are confirmed
// when the window closes (switching tabs keeps them).

import AppKit

enum SettingsTab: String, CaseIterable {
    case general, alerts, rules, keys

    var title: String {
        switch self {
        case .general: return "General"
        case .alerts: return "Alerts"
        case .rules: return "Rules"
        case .keys: return "Keys"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .alerts: return "bell.badge"
        case .rules: return "checklist"
        case .keys: return "key"
        }
    }
}

final class SettingsWindow: NSWindowController, NSWindowDelegate {
    let general = GeneralSettingsPane()
    let alerts = AlertSettingsPane()
    let rules: CheckRulesEditor
    let keys: ProviderCredentialsEditor
    private let tabs = SettingsTabsController()
    var closed: (() -> Void)?

    init(rules: CheckRulesEditor, keys: ProviderCredentialsEditor) {
        self.rules = rules
        self.keys = keys
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered,
                              defer: false)
        window.toolbarStyle = .preference
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        tabs.tabStyle = .toolbar
        let panes: [(SettingsTab, NSViewController, NSSize)] = [
            (.general, general, NSSize(width: 500, height: 210)),
            (.alerts, alerts, NSSize(width: 500, height: 270)),
            (.rules, rules, NSSize(width: 500, height: 400)),
            (.keys, keys, NSSize(width: 500, height: 360)),
        ]
        for (tab, pane, size) in panes {
            // Toolbar-style tabs resize the window to each pane's size.
            pane.preferredContentSize = size
            pane.title = tab.title
            let item = NSTabViewItem(viewController: pane)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            tabs.addTabViewItem(item)
        }
        window.contentViewController = tabs
        window.delegate = self
        // The window title names the selected tab, as in System Settings.
        tabs.selected = { [weak window] tab in window?.title = tab.title }
        window.title = SettingsTab.general.title
    }

    required init?(coder: NSCoder) { nil }

    var isVisible: Bool { window?.isVisible == true }

    var selectedTab: SettingsTab {
        let index = tabs.selectedTabViewItemIndex
        return SettingsTab.allCases.indices.contains(index) ? SettingsTab.allCases[index] : .general
    }

    func show(_ tab: SettingsTab) {
        tabs.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if tab == .rules { rules.focus() }
        if tab == .keys { keys.focus() }
    }

    /// Closes after confirming unsaved Rules or Keys edits.
    func requestClose() {
        guard let window else { return }
        if windowShouldClose(window) { window.close() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if rules.isDirty {
            show(.rules)
            rules.confirmDiscard(in: sender) { [weak self] proceed in
                if proceed { self?.requestClose() }
            }
            return false
        }
        if keys.isDirty {
            show(.keys)
            keys.confirmDiscard(in: sender) { [weak self] proceed in
                if proceed { self?.requestClose() }
            }
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) { closed?() }
}

/// Reports tab changes, including clicks on the toolbar tabs.
private final class SettingsTabsController: NSTabViewController {
    var selected: ((SettingsTab) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String, let tab = SettingsTab(rawValue: id) {
            selected?(tab)
        }
    }
}

/// A label + control row, the native Settings layout.
private func settingsGrid(_ rows: [(String, NSView)]) -> NSGridView {
    let grid = NSGridView(views: rows.map { title, control in
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        return [label, control]
    })
    grid.column(at: 0).xPlacement = .trailing
    grid.rowAlignment = .firstBaseline
    grid.rowSpacing = 12
    grid.columnSpacing = 10
    grid.translatesAutoresizingMaskIntoConstraints = false
    return grid
}

private func pin(_ content: NSView, in view: NSView, top: CGFloat = 24) {
    view.addSubview(content)
    NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: view.topAnchor, constant: top),
        content.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        content.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        content.centerXAnchor.constraint(equalTo: view.centerXAnchor),
    ])
}

final class GeneralSettingsPane: NSViewController {
    static let positions: [(String, String)] = [
        ("Top Left", "top-left"), ("Top Center", "top-center"), ("Top Right", "top-right"),
        ("Bottom Left", "bottom-left"), ("Bottom Center", "bottom-center"),
        ("Bottom Right", "bottom-right"),
    ]
    var speedChanged: ((TickerSpeed) -> Void)?
    var widthChanged: ((CGFloat) -> Void)?
    var positionPicked: ((String) -> Void)?
    var chooseColorRequested: (() -> Void)?
    var defaultColorRequested: (() -> Void)?

    let speedButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let widthButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let positionButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let colorState = NSTextField(labelWithString: "")
    private let defaultColorButton = NSButton(title: "Use Default", target: nil, action: nil)

    override func loadView() {
        view = NSView()
        TickerSpeed.allCases.forEach { speedButton.addItem(withTitle: $0.title) }
        speedButton.target = self
        speedButton.action = #selector(speedPicked(_:))
        widthButton.addItems(withTitles: ["Narrow", "Standard"])
        widthButton.target = self
        widthButton.action = #selector(widthPicked(_:))
        // A pull-down: the window can also be dragged, so no position is "current".
        positionButton.addItem(withTitle: "Move Window To…")
        Self.positions.forEach { positionButton.addItem(withTitle: $0.0) }
        positionButton.target = self
        positionButton.action = #selector(positionChosen(_:))
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseColor(_:)))
        defaultColorButton.target = self
        defaultColorButton.action = #selector(defaultColor(_:))
        colorState.textColor = .secondaryLabelColor
        let color = NSStackView(views: [colorState, choose, defaultColorButton])
        color.spacing = 8
        let grid = settingsGrid([
            ("Scroll speed:", speedButton), ("Ticker width:", widthButton),
            ("Position:", positionButton), ("Violation color:", color),
        ])
        pin(grid, in: view)
    }

    func update(speed: TickerSpeed, width: CGFloat, usesDefaultAlarmColor: Bool) {
        _ = view
        speedButton.selectItem(at: TickerSpeed.allCases.firstIndex(of: speed) ?? 1)
        widthButton.selectItem(at: abs(width - CompactWindowSizing.narrowWidth) < 1 ? 0 : 1)
        colorState.stringValue = usesDefaultAlarmColor ? "Default" : "Custom"
        defaultColorButton.isHidden = usesDefaultAlarmColor
    }

    @objc private func speedPicked(_ sender: NSPopUpButton) {
        guard TickerSpeed.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        speedChanged?(TickerSpeed.allCases[sender.indexOfSelectedItem])
    }

    @objc private func widthPicked(_ sender: NSPopUpButton) {
        widthChanged?(sender.indexOfSelectedItem == 0 ? CompactWindowSizing.narrowWidth
                                                      : CompactWindowSizing.standardWidth)
    }

    @objc private func positionChosen(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1  // item 0 is the pull-down title
        guard Self.positions.indices.contains(index) else { return }
        positionPicked?(Self.positions[index].1)
    }

    @objc private func chooseColor(_ sender: Any?) { chooseColorRequested?() }
    @objc private func defaultColor(_ sender: Any?) { defaultColorRequested?() }
}

final class AlertSettingsPane: NSViewController {
    var flashChanged: ((Bool) -> Void)?
    var bubbleChanged: ((Bool) -> Void)?
    var verificationChanged: ((Bool) -> Void)?
    var historyLimitChanged: ((Int) -> Void)?

    let flashSwitch = NSSwitch()
    let bubbleSwitch = NSSwitch()
    let verificationSwitch = NSSwitch()
    let historyButton = NSPopUpButton(frame: .zero, pullsDown: false)

    override func loadView() {
        view = NSView()
        flashSwitch.target = self
        flashSwitch.action = #selector(flashToggled(_:))
        flashSwitch.setAccessibilityLabel("Flash menu-bar icon red")
        bubbleSwitch.target = self
        bubbleSwitch.action = #selector(bubbleToggled(_:))
        bubbleSwitch.setAccessibilityLabel("Show bubble")
        verificationSwitch.target = self
        verificationSwitch.action = #selector(verificationToggled(_:))
        verificationSwitch.setAccessibilityLabel("Confirm with second check")
        ViolationHistoryPreference.choices.forEach {
            historyButton.addItem(withTitle: "\($0) newest")
        }
        historyButton.target = self
        historyButton.action = #selector(historyPicked(_:))
        historyButton.setAccessibilityLabel("Keep violation history")
        let rows = NSStackView(views: [
            row("Flash menu-bar icon red",
                "For 3 s when a violation arrives", flashSwitch),
            separator(),
            row("Show bubble",
                "Under the menu-bar icon for 5 s (after the flash); click to open",
                bubbleSwitch),
            separator(),
            row("Confirm with second check",
                "Show only violations the model confirms", verificationSwitch),
            separator(),
            row("Keep violation history",
                "Older than 1 hour moves to Archive", historyButton),
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            rows.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            rows.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        for arranged in rows.arrangedSubviews {
            arranged.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    private func row(_ title: String, _ detail: String, _ control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [text, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    func update(flashEnabled: Bool, bubbleEnabled: Bool, verificationEnabled: Bool,
                historyLimit: Int) {
        _ = view
        flashSwitch.state = flashEnabled ? .on : .off
        bubbleSwitch.state = bubbleEnabled ? .on : .off
        verificationSwitch.state = verificationEnabled ? .on : .off
        if let index = ViolationHistoryPreference.choices.firstIndex(of: historyLimit) {
            historyButton.selectItem(at: index)
        }
    }

    @objc private func flashToggled(_ sender: NSSwitch) { flashChanged?(sender.state == .on) }
    @objc private func bubbleToggled(_ sender: NSSwitch) { bubbleChanged?(sender.state == .on) }
    @objc private func verificationToggled(_ sender: NSSwitch) {
        verificationChanged?(sender.state == .on)
    }
    @objc private func historyPicked(_ sender: NSPopUpButton) {
        let choices = ViolationHistoryPreference.choices
        guard choices.indices.contains(sender.indexOfSelectedItem) else { return }
        historyLimitChanged?(choices[sender.indexOfSelectedItem])
    }
}
