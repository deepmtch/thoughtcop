// Persisted ticker background color and automatic readable foreground contrast.

import AppKit

enum TickerBackgroundPreference {
    static let defaultsKey = "tickerBackgroundRGBA"
    static let modeKey = "tickerBackgroundMode"
    // Kimi K3's review recommended a calm critical-red surface instead of the
    // old monochrome/yellow treatment. Keep the old symbol name as a source
    // compatibility alias for existing preference code.
    static let defaultViolationBackground = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.227, green: 0.118, blue: 0.118, alpha: 1) // #3A1E1E
            : NSColor(srgbRed: 0.992, green: 0.925, blue: 0.918, alpha: 1) // #FDECEA
    }
    static let stickyYellow = defaultViolationBackground

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
            return nil
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
        guard let foreground = color.usingColorSpace(.sRGB),
              let surface = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)
        else { return false }
        let alpha = foreground.alphaComponent
        let red = foreground.redComponent * alpha + surface.redComponent * (1 - alpha)
        let green = foreground.greenComponent * alpha + surface.greenComponent * (1 - alpha)
        let blue = foreground.blueComponent * alpha + surface.blueComponent * (1 - alpha)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) +
            0.0722 * linear(blue)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast
    }
}

enum TickerAppearance {
    static let normalBackground = NSColor.windowBackgroundColor

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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
