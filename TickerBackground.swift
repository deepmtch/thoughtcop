// Persisted ticker background color and automatic readable foreground contrast.

import AppKit

enum TickerBackgroundPreference {
    static let defaultsKey = "tickerBackgroundRGBA"

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
        guard let values = defaults.array(forKey: defaultsKey) as? [NSNumber] else {
            return nil
        }
        return color(from: values.map { CGFloat(truncating: $0) })
    }

    static func save(_ color: NSColor?, defaults: UserDefaults = .standard) {
        guard let color, let values = components(of: color) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(values.map(Double.init), forKey: defaultsKey)
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

final class TickerBackgroundView: NSView {
    var color: NSColor? { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color?.cgColor ?? NSColor.clear.cgColor
    }
}
