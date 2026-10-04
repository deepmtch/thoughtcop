// The Keys tab of Settings: native Keychain editor for checker credentials.

import AppKit

final class ProviderCredentialsEditor: NSViewController, NSTextFieldDelegate {
    private let groqField = NSSecureTextField()
    private let cerebrasField = NSSecureTextField()
    private let removeGroq = NSButton(checkboxWithTitle: "Remove saved Groq key",
                                      target: nil, action: nil)
    private let removeCerebras = NSButton(checkboxWithTitle: "Remove saved Cerebras key",
                                          target: nil, action: nil)
    private let saveHandler: ([CheckerProvider: CheckerCredentialEdit]) -> [String]
    private var statuses: [CheckerProvider: String]
    /// Re-reads the saved state after Save, so the status lines stay true.
    var statusesProvider: (() -> [CheckerProvider: String])?

    var usesSecureInputs: Bool {
        _ = view
        return groqField.cell is NSSecureTextFieldCell &&
            cerebrasField.cell is NSSecureTextFieldCell
    }

    init(statuses: [CheckerProvider: String],
         save: @escaping ([CheckerProvider: CheckerCredentialEdit]) -> [String]) {
        saveHandler = save
        self.statuses = statuses
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        buildContent(statuses: statuses)
    }

    func focus() { view.window?.makeFirstResponder(groqField) }

    /// Rebuilds the status lines from the current saved state (unless edits
    /// are pending).
    func refresh(statuses: [CheckerProvider: String]) {
        _ = view
        guard !isDirty else { return }
        self.statuses = statuses
        view.subviews.forEach { $0.removeFromSuperview() }
        buildContent(statuses: statuses)
    }

    var isDirty: Bool {
        _ = view
        return !groqField.stringValue.isEmpty || !cerebrasField.stringValue.isEmpty ||
            removeGroq.state == .on || removeCerebras.state == .on
    }

    private func buildContent(statuses: [CheckerProvider: String]) {
        let content = view

        let title = NSTextField(labelWithString: "Provider keys")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let help = wrappingLabel(
            "Stored in your macOS Keychain. Your rules and each message are sent to Groq for checking, with Cerebras as fallback.")
        let precedence = wrappingLabel("")
        precedence.isHidden = true

        func providerSection(_ name: String, field: NSSecureTextField,
                             remove: NSButton, status: String) -> NSStackView {
            let label = NSTextField(labelWithString: "\(name) API key")
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            let saved = status == "Active: macOS Keychain"
            let override = status.hasPrefix("Active: environment")
            // The hint matches the real state: keep a saved key, or paste one.
            field.placeholderString = saved ? "Saved — leave blank to keep" : "Paste API key"
            let shown = override ? "Using the key from your environment or .env"
                : saved ? "Saved in Keychain" : "Not set"
            let statusText = statusLabel(shown)
            // Removing is offered only when there is a saved key to remove.
            remove.isHidden = !saved
            let section = NSStackView(views: [label, field, statusText, remove])
            section.orientation = .vertical
            section.alignment = .leading
            section.spacing = 5
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
            return section
        }
        configureSecureField(groqField, provider: "Groq")
        configureSecureField(cerebrasField, provider: "Cerebras")
        removeGroq.setAccessibilityLabel("Remove saved Groq key from Keychain")
        removeCerebras.setAccessibilityLabel("Remove saved Cerebras key from Keychain")
        let grid = NSStackView(views: [
            providerSection("Groq", field: groqField, remove: removeGroq,
                            status: statuses[.groq] ?? "Not configured"),
            providerSection("Cerebras", field: cerebrasField, remove: removeCerebras,
                            status: statuses[.cerebras] ?? "Not configured"),
        ])
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 18
        for section in grid.arrangedSubviews {
            section.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        }

        let cancel = NSButton(title: "Revert", target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .rounded
        cancel.setAccessibilityLabel("Clear the typed keys")
        let save = NSButton(title: "Save", target: self,
                            action: #selector(save(_:)))
        save.bezelStyle = .rounded
        save.bezelColor = .controlAccentColor
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
            precedence.topAnchor.constraint(equalTo: help.bottomAnchor),
            precedence.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            precedence.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            grid.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            buttons.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    private func configureSecureField(_ field: NSSecureTextField, provider: String) {
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
        clearEdits()
        if let statusesProvider { refresh(statuses: statusesProvider()) }
        guard failures.isEmpty else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Some credentials could not be saved"
            alert.informativeText = failures.joined(separator: "\n")
            if let window = view.window { alert.beginSheetModal(for: window) }
            return
        }
    }

    @objc private func cancel(_ sender: Any?) { clearEdits() }

    private func clearEdits() {
        groqField.stringValue = ""
        cerebrasField.stringValue = ""
        removeGroq.state = .off
        removeCerebras.state = .off
    }

    /// Asks before typed keys are dropped; `proceed` is true after Discard.
    func confirmDiscard(in window: NSWindow, proceed: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard credential changes?"
        alert.informativeText = "Nothing has been written to Keychain yet."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Changes")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn else { proceed(false); return }
            self?.clearEdits()
            proceed(true)
        }
    }
}
