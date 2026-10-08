// The Rules tab of Settings: Doublethink's locally persisted check rules.

import AppKit

final class CheckRulesEditor: NSViewController, NSTextViewDelegate {
    private let textView = NSTextView(frame: .zero)
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let saveHandler: (String, CheckInstructionMode) -> Void
    private let buttonRow = NSStackView()
    private let savedLabel = NSTextField(labelWithString: "")
    private var originalText: String
    private var originalMode: CheckInstructionMode

    // Each accessor loads the view first: its controls are built there.
    var currentText: String { _ = view; return textView.string }
    var currentMode: CheckInstructionMode {
        _ = view
        return CheckInstructionMode(
            rawValue: modeButton.selectedItem?.representedObject as? String ?? "") ?? .wholeText
    }
    var actionTitles: [String] {
        _ = view
        return buttonRow.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
    }
    var actionsAreHorizontal: Bool { _ = view; return buttonRow.orientation == .horizontal }

    init(contents: String, mode: CheckInstructionMode,
         save: @escaping (String, CheckInstructionMode) -> Void) {
        saveHandler = save
        originalText = contents
        originalMode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        buildContent(contents: originalText, mode: originalMode)
    }

    func focus() { view.window?.makeFirstResponder(textView) }

    /// Shows the stored rules again unless there are unsaved edits.
    func reload(contents: String, mode: CheckInstructionMode) {
        _ = view
        guard !isDirty else { return }
        originalText = contents
        originalMode = mode
        revertToSaved()
    }

    var isDirty: Bool { currentText != originalText || currentMode != originalMode }

    func textDidChange(_ notification: Notification) { savedLabel.stringValue = "" }

    private func buildContent(contents: String, mode: CheckInstructionMode) {
        let content = view

        let title = NSTextField(labelWithString: "What should Doublethink check?")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        // Wrapping: a single-line label demanded its full text width and made
        // the window about 740 points wide.
        let help = NSTextField(wrappingLabelWithString:
            "Each AI reply and readable thought is checked against your rules, exactly as written.")
        help.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        help.translatesAutoresizingMaskIntoConstraints = false
        help.maximumNumberOfLines = 2
        help.lineBreakMode = .byWordWrapping

        let modeLabel = NSTextField(labelWithString: "Check as:")
        modeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        modeLabel.textColor = .labelColor
        modeLabel.translatesAutoresizingMaskIntoConstraints = false

        CheckInstructionMode.allCases.forEach { value in
            modeButton.addItem(withTitle: value.title)
            modeButton.lastItem?.representedObject = value.rawValue
        }
        modeButton.selectItem(at: CheckInstructionMode.allCases.firstIndex(of: mode) ?? 0)
        modeButton.target = self
        modeButton.action = #selector(modeChanged(_:))
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.setAccessibilityLabel("Check mode")
        modeButton.setAccessibilityHelp("Choose whether all text is one rule or each non-empty line is its own rule.")

        let promptLabel = NSTextField(labelWithString: "Rules")
        promptLabel.font = .systemFont(ofSize: 12, weight: .medium)
        promptLabel.textColor = .labelColor
        promptLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        textView.string = contents
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.delegate = self
        textView.setAccessibilityLabel("Rules")
        textView.setAccessibilityHelp("Enter the exact rules Doublethink checks AI replies and thoughts against.")
        scrollView.documentView = textView

        let privacy = NSTextField(wrappingLabelWithString:
            "Stored on this Mac. Messages are sent for checking only while checks are on.")
        privacy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = .secondaryLabelColor
        privacy.translatesAutoresizingMaskIntoConstraints = false

        // Settings stays open after saving, so the second action reverts.
        let cancel = NSButton(title: "Revert", target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .rounded
        cancel.setAccessibilityLabel("Revert to the saved rules")
        let save = NSButton(title: "Save Rules", target: self,
                            action: #selector(save(_:)))
        save.bezelStyle = .rounded
        // Visibly the primary action; Return stays a newline in the editor.
        save.bezelColor = .controlAccentColor
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = [.command]
        save.setAccessibilityLabel("Save rules on this Mac")
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        savedLabel.font = .systemFont(ofSize: 11)
        savedLabel.textColor = .secondaryLabelColor
        buttonRow.addArrangedSubview(savedLabel)
        buttonRow.addArrangedSubview(cancel)
        buttonRow.addArrangedSubview(save)
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, help, modeLabel, modeButton, promptLabel,
                     scrollView, privacy, buttonRow] { content.addSubview(view) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            help.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            help.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            help.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            modeLabel.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 14),
            modeLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            modeLabel.centerYAnchor.constraint(equalTo: modeButton.centerYAnchor),
            modeButton.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 10),
            modeButton.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 8),
            modeButton.trailingAnchor.constraint(lessThanOrEqualTo: title.trailingAnchor),
            promptLabel.topAnchor.constraint(equalTo: modeButton.bottomAnchor, constant: 14),
            promptLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: privacy.topAnchor, constant: -10),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
            privacy.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            privacy.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            privacy.trailingAnchor.constraint(lessThanOrEqualTo: buttonRow.leadingAnchor,
                                               constant: -12),
            buttonRow.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    @objc private func save(_ sender: Any?) {
        saveHandler(textView.string, currentMode)
        originalText = textView.string
        originalMode = currentMode
        savedLabel.stringValue = "Saved."
    }

    @objc private func cancel(_ sender: Any?) { revertToSaved() }

    private func revertToSaved() {
        textView.string = originalText
        modeButton.selectItem(at: CheckInstructionMode.allCases.firstIndex(of: originalMode) ?? 0)
        savedLabel.stringValue = ""
    }

    @objc private func modeChanged(_ sender: Any?) { savedLabel.stringValue = "" }

    /// Asks before unsaved rules are lost; `proceed` is true after Save or
    /// Discard, false when the user keeps editing.
    func confirmDiscard(in window: NSWindow, proceed: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Save changes to your rules?"
        alert.informativeText = "Unsaved changes will be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.save(nil)
                proceed(true)
            case .alertThirdButtonReturn:
                self.revertToSaved()
                proceed(true)
            default:
                proceed(false)
            }
        }
    }
}
