// Four unambiguous corner controls for the resting ticker toolbar.

import AppKit

enum TickerWindowCorner: Int, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var symbolName: String {
        switch self {
        case .topLeft: return "arrow.up.left"
        case .topRight: return "arrow.up.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomRight: return "arrow.down.right"
        }
    }

    var routeName: String {
        switch self {
        case .topLeft: return "top-left"
        case .topRight: return "top-right"
        case .bottomLeft: return "bottom-left"
        case .bottomRight: return "bottom-right"
        }
    }

    var accessibilityName: String {
        "Move window to \(routeName.replacingOccurrences(of: "-", with: " ")) corner"
    }
}

final class TickerCornerControls: NSStackView {
    var cornerRequested: ((TickerWindowCorner) -> Void)?
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

        for corner in TickerWindowCorner.allCases {
            let image = NSImage(systemSymbolName: corner.symbolName,
                                accessibilityDescription: corner.accessibilityName)
                ?? NSImage()
            let button = NSButton(image: image, target: self,
                                  action: #selector(cornerPressed(_:)))
            button.tag = corner.rawValue
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.controlSize = .small
            button.toolTip = corner.accessibilityName
            button.setAccessibilityLabel(corner.accessibilityName)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            addArrangedSubview(button)
            buttons.append(button)
        }
    }

    required init?(coder: NSCoder) { nil }

    func request(_ corner: TickerWindowCorner) { cornerRequested?(corner) }

    @objc private func cornerPressed(_ sender: NSButton) {
        guard let corner = TickerWindowCorner(rawValue: sender.tag) else { return }
        request(corner)
    }
}
