// Native Keychain editor for external checker credentials.

import AppKit

final class ProviderCredentialsEditor: NSWindowController, NSWindowDelegate,
    NSTextFieldDelegate {
    private let groqField = NSSecureTextField()
    private let cerebrasField = NSSecureTextField()
    private let removeGroq = NSButton(checkboxWithTitle: "Remove saved Groq key",
                                      target: nil, action: nil)
    private let removeCerebras = NSButton(checkboxWithTitle: "Remove saved Cerebras key",
                                          target: nil, action: nil)
    private let saveHandler: ([CheckerProvider: CheckerCredentialEdit]) -> [String]
    private let closeHandler: () -> Void
    private var allowClose = false

    var usesSecureInputs: Bool {
        groqField.cell is NSSecureTextFieldCell &&
            cerebrasField.cell is NSSecureTextFieldCell
    }

    init(statuses: [CheckerProvider: String],
         save: @escaping ([CheckerProvider: CheckerCredentialEdit]) -> [String],
         closed: @escaping () -> Void) {
        saveHandler = save
        closeHandler = closed
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 350),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
        window.title = "Provider Credentials"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        buildContent(statuses: statuses)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(groqField)
    }

    func windowWillClose(_ notification: Notification) { closeHandler() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !allowClose, isDirty else { return true }
        presentUnsavedChangesAlert()
        return false
    }

    private var isDirty: Bool {
        !groqField.stringValue.isEmpty || !cerebrasField.stringValue.isEmpty ||
            removeGroq.state == .on || removeCerebras.state == .on
    }

    private func buildContent(statuses: [CheckerProvider: String]) {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Configure external checking")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let help = wrappingLabel(
            "Keys are stored in your macOS Keychain. Thinkpeek sends the check instruction and each eligible reasoning or assistant-response record directly to Groq, with Cerebras as fallback.")
        let precedence = wrappingLabel(
            "Process environment and a development checkout's .env override Keychain values. Leave a field blank to keep its saved key.")

        let groqStatus = statusLabel(statuses[.groq] ?? "Not configured")
        let cerebrasStatus = statusLabel(statuses[.cerebras] ?? "Not configured")
        configureSecureField(groqField, provider: "Groq")
        configureSecureField(cerebrasField, provider: "Cerebras")
        removeGroq.setAccessibilityLabel("Remove saved Groq key from Keychain")
        removeCerebras.setAccessibilityLabel("Remove saved Cerebras key from Keychain")

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Groq API key"), groqField],
            [NSTextField(labelWithString: ""), groqStatus],
            [NSTextField(labelWithString: ""), removeGroq],
            [NSTextField(labelWithString: "Cerebras API key"), cerebrasField],
            [NSTextField(labelWithString: ""), cerebrasStatus],
            [NSTextField(labelWithString: ""), removeCerebras],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save to Keychain", target: self,
                            action: #selector(save(_:)))
        save.bezelStyle = .rounded
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = [.command]
        save.setAccessibilityLabel("Save provider credentials to macOS Keychain")
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        for view in [title, help, precedence, grid, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            help.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7),
            help.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            help.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            precedence.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 7),
            precedence.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            precedence.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            grid.topAnchor.constraint(equalTo: precedence.bottomAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            buttons.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    private func configureSecureField(_ field: NSSecureTextField, provider: String) {
        field.placeholderString = "Leave blank to keep the saved key"
        field.delegate = self
        field.setAccessibilityLabel("\(provider) API key")
        field.setAccessibilityHelp("Stored only in the macOS login Keychain")
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 3
        return label
    }

    private func statusLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func edits() -> [CheckerProvider: CheckerCredentialEdit] {
        func edit(field: NSSecureTextField, remove: NSButton) -> CheckerCredentialEdit {
            if !field.stringValue.isEmpty { return .set(field.stringValue) }
            return remove.state == .on ? .remove : .unchanged
        }
        return [
            .groq: edit(field: groqField, remove: removeGroq),
            .cerebras: edit(field: cerebrasField, remove: removeCerebras),
        ]
    }

    @objc private func save(_ sender: Any?) {
        let failures = saveHandler(edits())
        groqField.stringValue = ""
        cerebrasField.stringValue = ""
        guard failures.isEmpty else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Some credentials could not be saved"
            alert.informativeText = failures.joined(separator: "\n")
            if let window { alert.beginSheetModal(for: window) }
            return
        }
        allowClose = true
        close()
    }

    @objc private func cancel(_ sender: Any?) {
        guard isDirty else { allowClose = true; close(); return }
        presentUnsavedChangesAlert()
    }

    private func presentUnsavedChangesAlert() {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard credential changes?"
        alert.informativeText = "Nothing has been written to Keychain yet."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Changes")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            self?.allowClose = true
            self?.close()
        }
    }
}
