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
        // Docked at the top, the window touches the menu bar (no inset), as
        // the user asked for the one-line ticker.
        case .maximumEdge: verticalReference = visible.maxY
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
/// the bottom, left or right edge keeps that edge and its inset; one docked at
/// the top touches the menu bar; a freely floating window keeps its center.
func resizedWindowFrame(_ frame: NSRect, toHeight height: CGFloat,
                        width: CGFloat? = nil, within visible: NSRect) -> NSRect {
    let size = NSSize(width: width ?? frame.width, height: height)
    return WindowPlacement(frame: frame, within: visible).frame(for: size, within: visible)
}

/// Move the window to one of the visible screen's four corners.
func movedWindowFrame(_ frame: NSRect, to corner: TickerWindowCorner,
                      within visible: NSRect, inset: CGFloat = 12) -> NSRect {
    var result = frame
    let minimumX = visible.minX + inset
    let maximumX = max(minimumX, visible.maxX - frame.width - inset)
    let minimumY = visible.minY + inset
    // Top corners touch the menu bar; the other edges keep the inset.
    let maximumY = max(minimumY, visible.maxY - frame.height)
    switch corner {
    case .topLeft:
        result.origin = NSPoint(x: minimumX, y: maximumY)
    case .topRight:
        result.origin = NSPoint(x: maximumX, y: maximumY)
    case .bottomLeft:
        result.origin = NSPoint(x: minimumX, y: minimumY)
    case .bottomRight:
        result.origin = NSPoint(x: maximumX, y: minimumY)
    }
    result.origin.x = min(max(result.origin.x, minimumX), maximumX)
    result.origin.y = min(max(result.origin.y, minimumY), maximumY)
    return result
}
