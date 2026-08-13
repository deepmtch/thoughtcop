// Compact nonmodal editor for Thinkpeek's locally persisted check rules.

import AppKit

final class CheckRulesEditor: NSWindowController, NSWindowDelegate {
    private let textView = NSTextView(frame: .zero)
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let saveHandler: (String, CheckInstructionMode) -> Void
    private let closeHandler: () -> Void
    private let buttonRow = NSStackView()

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
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
        window.title = "What to Check"
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

    private func buildContent(contents: String, mode: CheckInstructionMode) {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "What should Thinkpeek flag?")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let help = NSTextField(labelWithString:
            "Your text is sent verbatim. Choose explicitly how multiple lines are evaluated.")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        help.translatesAutoresizingMaskIntoConstraints = false

        CheckInstructionMode.allCases.forEach { value in
            modeButton.addItem(withTitle: value.title)
            modeButton.lastItem?.representedObject = value.rawValue
        }
        modeButton.selectItem(at: CheckInstructionMode.allCases.firstIndex(of: mode) ?? 0)
        modeButton.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        textView.string = contents
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        scrollView.documentView = textView

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.setAccessibilityLabel("Save check rules locally in Thinkpeek")
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(cancel)
        buttonRow.addArrangedSubview(save)
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, help, modeButton, scrollView, buttonRow] { content.addSubview(view) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            help.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            help.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            help.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            modeButton.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 10),
            modeButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            modeButton.trailingAnchor.constraint(lessThanOrEqualTo: title.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: modeButton.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -14),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
            buttonRow.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    @objc private func save(_ sender: Any?) {
        saveHandler(textView.string, currentMode)
        close()
    }

    @objc private func cancel(_ sender: Any?) { close() }
}
