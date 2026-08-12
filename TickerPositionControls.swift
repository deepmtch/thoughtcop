// Compact icon-only edge controls for the resting ticker toolbar.

import AppKit

enum TickerWindowEdge: Int, CaseIterable {
    case left, right, top, bottom

    var symbolName: String {
        switch self {
        case .left: return "rectangle.lefthalf.inset.filled"
        case .right: return "rectangle.righthalf.inset.filled"
        case .top: return "rectangle.tophalf.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        }
    }

    var accessibilityName: String {
        switch self {
        case .left: return "Move window to left edge"
        case .right: return "Move window to right edge"
        case .top: return "Move window to top edge"
        case .bottom: return "Move window to bottom edge"
        }
    }
}

final class TickerPositionControls: NSStackView {
    var directionRequested: ((TickerWindowEdge) -> Void)?
    private var buttons: [NSButton] = []

    var accessibilityNames: [String] {
        buttons.map { $0.accessibilityLabel() ?? "" }
    }

    var foregroundColor: NSColor? {
        didSet { buttons.forEach { $0.contentTintColor = foregroundColor } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        spacing = 0
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        widthAnchor.constraint(equalToConstant: 88).isActive = true

        for edge in TickerWindowEdge.allCases {
            let image = NSImage(systemSymbolName: edge.symbolName,
                                accessibilityDescription: edge.accessibilityName)
                ?? NSImage(systemSymbolName: fallbackSymbol(for: edge),
                           accessibilityDescription: edge.accessibilityName)
                ?? NSImage()
            let button = NSButton(image: image, target: self,
                                  action: #selector(edgePressed(_:)))
            button.tag = edge.rawValue
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.controlSize = .small
            button.toolTip = edge.accessibilityName
            button.setAccessibilityLabel(edge.accessibilityName)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            addArrangedSubview(button)
            buttons.append(button)
        }
    }

    required init?(coder: NSCoder) { nil }

    func request(_ edge: TickerWindowEdge) { directionRequested?(edge) }

    @objc private func edgePressed(_ sender: NSButton) {
        guard let edge = TickerWindowEdge(rawValue: sender.tag) else { return }
        request(edge)
    }

    private func fallbackSymbol(for edge: TickerWindowEdge) -> String {
        switch edge {
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .top: return "chevron.up"
        case .bottom: return "chevron.down"
        }
    }
}
