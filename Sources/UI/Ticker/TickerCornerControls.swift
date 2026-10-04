// Window corners for the /corner command API (the ticker no longer shows
// corner buttons; Settings › General › Position moves the window).

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
