// Compact hierarchical settings menu for the detail toolbar.

import AppKit

final class TickerSettingsMenu: NSObject {
    var speedRequested: ((TickerSpeed) -> Void)?
    var widthRequested: ((CGFloat) -> Void)?
    var positionRequested: ((String) -> Void)?
    var backgroundRequested: (() -> Void)?
    var defaultAlarmColorRequested: (() -> Void)?

    private(set) var menu = NSMenu()
    private weak var launcherButton: NSButton?
    private var speedItems: [TickerSpeed: NSMenuItem] = [:]
    private var widthItems: [String: NSMenuItem] = [:]
    private var defaultAlarmColorItem: NSMenuItem!

    var structure: [String: [String]] {
        Dictionary(uniqueKeysWithValues: menu.items.compactMap { item in
            guard let submenu = item.submenu else { return nil }
            return (item.title, submenu.items.map(\.title))
        })
    }

    var topLevelTitles: [String] { menu.items.map(\.title) }
    var usesSingleButtonLauncher: Bool { launcherButton != nil }

    func install(on button: NSButton) {
        menu = NSMenu()
        menu.addItem(submenuItem(title: "Scroll Speed", symbol: "speedometer",
                                 submenu: speedMenu()))
        menu.addItem(submenuItem(title: "Window Width", symbol: "arrow.left.and.right",
                                 submenu: widthMenu()))
        menu.addItem(submenuItem(title: "Window Position", symbol: "rectangle.on.rectangle",
                                 submenu: positionMenu()))
        menu.addItem(submenuItem(title: "Appearance", symbol: "paintpalette",
                                 submenu: appearanceMenu()))
        launcherButton = button
        button.title = ""
        button.image = NSImage(systemSymbolName: "gearshape",
                               accessibilityDescription: "Display settings")
        button.imagePosition = .imageOnly
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.target = self
        button.action = #selector(showMenu(_:))
        button.toolTip = "Display settings"
        button.setAccessibilityLabel("Display settings")
    }

    @objc private func showMenu(_ sender: NSButton) {
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                   in: sender)
    }

    func update(speed: TickerSpeed, width: CGFloat, usesDefaultAlarmColor: Bool) {
        for (candidate, item) in speedItems { item.state = candidate == speed ? .on : .off }
        widthItems["narrow"]?.state = abs(width - CompactWindowSizing.narrowWidth) < 1
            ? .on : .off
        widthItems["standard"]?.state = abs(width - CompactWindowSizing.standardWidth) < 1
            ? .on : .off
        defaultAlarmColorItem.state = usesDefaultAlarmColor ? .on : .off
    }

    private func submenuItem(title: String, symbol: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.submenu = submenu
        return item
    }

    private func speedMenu() -> NSMenu {
        let submenu = NSMenu(title: "Scroll Speed")
        for (index, speed) in TickerSpeed.allCases.enumerated() {
            let item = NSMenuItem(title: speed.title, action: #selector(speedPicked(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            item.toolTip = "Use \(speed.title.lowercased()) ticker speed"
            submenu.addItem(item)
            speedItems[speed] = item
        }
        return submenu
    }

    private func widthMenu() -> NSMenu {
        let submenu = NSMenu(title: "Window Width")
        let choices: [(String, String)] = [("Narrow", "narrow"), ("Standard", "standard")]
        for (index, choice) in choices.enumerated() {
            let item = NSMenuItem(title: choice.0, action: #selector(widthPicked(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
            widthItems[choice.1] = item
        }
        return submenu
    }

    private func positionMenu() -> NSMenu {
        let submenu = NSMenu(title: "Window Position")
        let choices = [
            ("Top Left", "top-left", "arrow.up.left"),
            ("Top Center", "top-center", "arrow.up"),
            ("Top Right", "top-right", "arrow.up.right"),
            ("Bottom Left", "bottom-left", "arrow.down.left"),
            ("Bottom Center", "bottom-center", "arrow.down"),
            ("Bottom Right", "bottom-right", "arrow.down.right"),
        ]
        for (index, choice) in choices.enumerated() {
            let item = NSMenuItem(title: choice.0, action: #selector(positionPicked(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = NSImage(systemSymbolName: choice.2,
                                 accessibilityDescription: choice.0)
            submenu.addItem(item)
        }
        return submenu
    }

    private func appearanceMenu() -> NSMenu {
        let submenu = NSMenu(title: "Appearance")
        let choose = NSMenuItem(title: "Violation Highlight Color…",
                                action: #selector(backgroundPicked(_:)), keyEquivalent: "")
        choose.target = self
        choose.image = NSImage(systemSymbolName: "paintpalette",
                               accessibilityDescription: choose.title)
        submenu.addItem(choose)
        defaultAlarmColorItem = NSMenuItem(title: "Use Default Violation Color",
                                          action: #selector(systemBackgroundPicked(_:)),
                                          keyEquivalent: "")
        defaultAlarmColorItem.target = self
        defaultAlarmColorItem.image = NSImage(systemSymbolName: "arrow.counterclockwise",
                                              accessibilityDescription:
                                                defaultAlarmColorItem.title)
        submenu.addItem(defaultAlarmColorItem)
        return submenu
    }

    @objc private func speedPicked(_ sender: NSMenuItem) {
        guard TickerSpeed.allCases.indices.contains(sender.tag) else { return }
        speedRequested?(TickerSpeed.allCases[sender.tag])
    }

    @objc private func widthPicked(_ sender: NSMenuItem) {
        widthRequested?(sender.tag == 0 ? CompactWindowSizing.narrowWidth
                                       : CompactWindowSizing.standardWidth)
    }

    @objc private func positionPicked(_ sender: NSMenuItem) {
        let presets = ["top-left", "top-center", "top-right", "bottom-left",
                       "bottom-center", "bottom-right"]
        guard presets.indices.contains(sender.tag) else { return }
        positionRequested?(presets[sender.tag])
    }

    @objc private func backgroundPicked(_ sender: NSMenuItem) { backgroundRequested?() }
    @objc private func systemBackgroundPicked(_ sender: NSMenuItem) {
        defaultAlarmColorRequested?()
    }
}
