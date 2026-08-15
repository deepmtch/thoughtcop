// Width policy and responsive constraints for the compact controls/message UI.

import AppKit

enum CompactHeaderStyle: String {
    case inline
    case stacked
}

enum CompactWindowSizing {
    static let minimumWidth: CGFloat = 380
    static let narrowWidth: CGFloat = 400
    static let standardWidth: CGFloat = 560
    static let maximumWidth: CGFloat = 560
    static let stackThreshold: CGFloat = 520
    static let defaultsKey = "compactWindowWidth"

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(maximumWidth, max(minimumWidth, width))
    }

    static func savedWidth(defaults: UserDefaults = .standard) -> CGFloat {
        let saved = CGFloat(defaults.double(forKey: defaultsKey))
        return saved > 0 ? clamped(saved) : standardWidth
    }

    static func headerStyle(for width: CGFloat) -> CompactHeaderStyle {
        width < stackThreshold ? .stacked : .inline
    }

    static func headerHeight(for width: CGFloat) -> CGFloat {
        headerStyle(for: width) == .stacked ? 88 : 52
    }

    static func controlsHeight(for width: CGFloat) -> CGFloat {
        headerHeight(for: width)
    }
}

func shouldShowHistoryFeed(peekMode: Bool, messageMode: Bool,
                           compactMode: Bool) -> Bool {
    !peekMode && !messageMode && !compactMode
}

final class DetailHeaderLayout {
    private let heightConstraint: NSLayoutConstraint
    private let commonConstraints: [NSLayoutConstraint]
    private let inlineConstraints: [NSLayoutConstraint]
    private let stackedConstraints: [NSLayoutConstraint]
    private(set) var style: CompactHeaderStyle?
    private var isActive = false

    init(header: NSView, picker: NSView, controls: NSView, actions: NSView) {
        heightConstraint = header.heightAnchor.constraint(equalToConstant: 52)

        commonConstraints = [
            heightConstraint,
            picker.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            picker.heightAnchor.constraint(equalToConstant: 30),
            actions.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
        ]
        inlineConstraints = [
            picker.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            picker.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor,
                                              constant: -8),
            controls.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            controls.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -8),
            actions.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ]
        stackedConstraints = [
            picker.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            picker.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -8),
            actions.centerYAnchor.constraint(equalTo: picker.centerYAnchor),
            controls.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 6),
            controls.leadingAnchor.constraint(greaterThanOrEqualTo: header.leadingAnchor,
                                                constant: 14),
            controls.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
        ]
    }

    func apply(width: CGFloat) {
        guard isActive else { return }
        let next = CompactWindowSizing.headerStyle(for: width)
        guard next != style else { return }
        if let style {
            NSLayoutConstraint.deactivate(style == .inline
                ? inlineConstraints : stackedConstraints)
        }
        heightConstraint.constant = CompactWindowSizing.headerHeight(for: width)
        NSLayoutConstraint.activate(next == .inline ? inlineConstraints : stackedConstraints)
        style = next
    }

    func setActive(_ active: Bool, width: CGFloat) {
        guard active != isActive else {
            if active { apply(width: width) }
            return
        }
        if active {
            isActive = true
            NSLayoutConstraint.activate(commonConstraints)
            apply(width: width)
        } else {
            if let style {
                NSLayoutConstraint.deactivate(style == .inline
                    ? inlineConstraints : stackedConstraints)
            }
            NSLayoutConstraint.deactivate(commonConstraints)
            style = nil
            isActive = false
        }
    }
}
