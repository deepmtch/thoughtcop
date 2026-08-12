// Pure window-resize geometry shared by the HUD and headless regression tests.

import AppKit

private enum AxisResizeAnchor {
    case minimumEdge
    case center
    case maximumEdge
}

struct WindowPlacement {
    private let horizontal: AxisResizeAnchor
    private let vertical: AxisResizeAnchor
    private let horizontalReference: CGFloat
    private let verticalReference: CGFloat

    init(frame: NSRect, within visible: NSRect) {
        horizontal = resizeAnchor(minimum: frame.minX, maximum: frame.maxX,
                                  visibleMinimum: visible.minX,
                                  visibleMaximum: visible.maxX)
        vertical = resizeAnchor(minimum: frame.minY, maximum: frame.maxY,
                                visibleMinimum: visible.minY,
                                visibleMaximum: visible.maxY)
        switch horizontal {
        case .minimumEdge: horizontalReference = frame.minX
        case .center: horizontalReference = frame.midX
        case .maximumEdge: horizontalReference = frame.maxX
        }
        switch vertical {
        case .minimumEdge: verticalReference = frame.minY
        case .center: verticalReference = frame.midY
        case .maximumEdge: verticalReference = frame.maxY
        }
    }

    func frame(for size: NSSize, within visible: NSRect) -> NSRect {
        var result = NSRect(origin: .zero, size: size)
        switch horizontal {
        case .minimumEdge: result.origin.x = horizontalReference
        case .center: result.origin.x = horizontalReference - size.width / 2
        case .maximumEdge: result.origin.x = horizontalReference - size.width
        }
        switch vertical {
        case .minimumEdge: result.origin.y = verticalReference
        case .center: result.origin.y = verticalReference - size.height / 2
        case .maximumEdge: result.origin.y = verticalReference - size.height
        }
        result.origin.x = min(max(result.origin.x, visible.minX),
                              max(visible.minX, visible.maxX - result.width))
        result.origin.y = min(max(result.origin.y, visible.minY),
                              max(visible.minY, visible.maxY - result.height))
        return result
    }
}

private func resizeAnchor(minimum: CGFloat, maximum: CGFloat,
                          visibleMinimum: CGFloat, visibleMaximum: CGFloat,
                          edgeThreshold: CGFloat = 48) -> AxisResizeAnchor {
    if abs(minimum - visibleMinimum) <= edgeThreshold { return .minimumEdge }
    if abs(visibleMaximum - maximum) <= edgeThreshold { return .maximumEdge }
    return .center
}

/// Resize without losing the placement chosen by the user. A window docked near
/// an edge keeps that edge and its inset; a freely floating window keeps its center.
func resizedWindowFrame(_ frame: NSRect, toHeight height: CGFloat,
                        width: CGFloat? = nil, within visible: NSRect) -> NSRect {
    let size = NSSize(width: width ?? frame.width, height: height)
    return WindowPlacement(frame: frame, within: visible).frame(for: size, within: visible)
}
