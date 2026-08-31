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
    // The standard 560-point panel remains two-tiered. A single row becomes
    // useful only in the wider history view, where the controls have room to
    // remain visibly grouped instead of collapsing into an icon strip.
    // The 700-point history window also uses two tiers. A single row squeezed
    // the session picker, navigation, filter, utilities, and Hide into an
    // unreadable toolbar.
    static let stackThreshold: CGFloat = 760
    static let messagePreviewHeight: CGFloat = 210
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
        headerStyle(for: width) == .stacked ? 82 : 52
    }

    static func controlsHeight(for width: CGFloat) -> CGFloat {
        headerHeight(for: width) + messagePreviewHeight
    }
}

func shouldShowHistoryFeed(peekMode: Bool, messageMode: Bool,
                           compactMode: Bool) -> Bool {
    !peekMode && !messageMode
}

/// A quiet visual group for related toolbar controls. The grouping is
/// structural: callers decide which commands belong together; this view only
/// provides the standard compact capsule treatment.
final class DetailToolbarGroup: NSStackView {
    init(views: [NSView]) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 0
        edgeInsets = NSEdgeInsets(top: 1, left: 3, bottom: 1, right: 3)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.72).cgColor
        views.forEach(addArrangedSubview)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }
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
            controls.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor,
                                                 constant: -14),
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
