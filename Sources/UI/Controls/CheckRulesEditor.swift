// Compact nonmodal editor for Thinkpeek's locally persisted check rules.

import AppKit

final class CheckRulesEditor: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let textView = NSTextView(frame: .zero)
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let saveHandler: (String, CheckInstructionMode) -> Void
    private let closeHandler: () -> Void
    private let buttonRow = NSStackView()
    private var originalText: String
    private var originalMode: CheckInstructionMode
    private var allowClose = false

    var currentText: String { textView.string }
    var currentMode: CheckInstructionMode {
        CheckInstructionMode(rawValue: modeButton.selectedItem?.representedObject as? String ?? "")
            ?? .wholeText
    }
    var actionTitles: [String] {
        buttonRow.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
    }
    var actionsAreHorizontal: Bool { buttonRow.orientation == .horizontal }

    init(contents: String, mode: CheckInstructionMode,
         save: @escaping (String, CheckInstructionMode) -> Void,
         closed: @escaping () -> Void) {
        saveHandler = save
        closeHandler = closed
        originalText = contents
        originalMode = mode
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
        window.title = "Rules"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 300)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        buildContent(contents: contents, mode: mode)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
    }

    func windowWillClose(_ notification: Notification) { closeHandler() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !allowClose, isDirty else { return true }
        presentUnsavedChangesAlert()
        return false
    }

    private var isDirty: Bool {
        textView.string != originalText || currentMode != originalMode
    }

    private func buildContent(contents: String, mode: CheckInstructionMode) {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "What should Thinkpeek check?")
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
        textView.setAccessibilityHelp("Enter the exact rules Thinkpeek checks AI replies and thoughts against.")
        scrollView.documentView = textView

        let privacy = NSTextField(wrappingLabelWithString:
            "Stored on this Mac. Messages are sent for checking only while checks are on.")
        privacy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = .secondaryLabelColor
        privacy.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
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
        allowClose = true
        close()
    }

    @objc private func cancel(_ sender: Any?) {
        guard isDirty else { allowClose = true; close(); return }
        presentUnsavedChangesAlert()
    }

    @objc private func modeChanged(_ sender: Any?) {}

    private func presentUnsavedChangesAlert() {
        guard let window else { return }
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
            case .alertThirdButtonReturn:
                self.allowClose = true
                self.close()
            default:
                break
            }
        }
    }
}
