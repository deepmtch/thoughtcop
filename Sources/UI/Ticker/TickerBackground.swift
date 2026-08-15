// Persisted ticker background color and automatic readable foreground contrast.

import AppKit

enum TickerBackgroundPreference {
    static let defaultsKey = "tickerBackgroundRGBA"
    static let modeKey = "tickerBackgroundMode"
    static let stickyYellow = NSColor(srgbRed: 0.97, green: 0.96,
                                      blue: 0.56, alpha: 1)

    static func components(of color: NSColor) -> [CGFloat]? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return [rgb.redComponent, rgb.greenComponent,
                rgb.blueComponent, rgb.alphaComponent]
    }

    static func color(from components: [CGFloat]) -> NSColor? {
        guard components.count == 4 else { return nil }
        return NSColor(srgbRed: components[0], green: components[1],
                       blue: components[2], alpha: components[3])
    }

    static func load(defaults: UserDefaults = .standard) -> NSColor? {
        if defaults.string(forKey: modeKey) == "system" { return nil }
        guard let values = defaults.array(forKey: defaultsKey) as? [NSNumber] else {
            return stickyYellow
        }
        return color(from: values.map { CGFloat(truncating: $0) })
    }

    static func save(_ color: NSColor?, defaults: UserDefaults = .standard) {
        guard let color, let values = components(of: color) else {
            defaults.removeObject(forKey: defaultsKey)
            defaults.set("system", forKey: modeKey)
            return
        }
        defaults.set(values.map(Double.init), forKey: defaultsKey)
        defaults.set("custom", forKey: modeKey)
    }

    static func usesDarkForeground(on color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) +
            0.7152 * linear(rgb.greenComponent) +
            0.0722 * linear(rgb.blueComponent)
        return luminance > 0.42
    }
}

enum TickerAppearance {
    static let normalBackground = NSColor.white

    static func background(alarmActive: Bool,
                           configuredAlarmColor: NSColor?) -> NSColor {
        guard alarmActive else { return normalBackground }
        return configuredAlarmColor ?? TickerBackgroundPreference.stickyYellow
    }
}

final class TickerBackgroundView: NSView {
    var color: NSColor? { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color?.cgColor ?? NSColor.clear.cgColor
    }
}
