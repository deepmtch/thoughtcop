// Native multiline editor for changing drift-check instructions at runtime.

import AppKit

enum CheckPromptEditor {
    static func present(current: String, completion: (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Check Prompt"
        alert.informativeText = "Tell the checker what to look for. Changes apply to the next reasoning block."
        alert.alertStyle = .informational

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = current
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Restore Default")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        NSApp.activate(ignoringOtherApps: true)
        alert.window.title = "Thinkpeek Check Prompt"
        alert.window.initialFirstResponder = textView
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            completion(textView.string)
        case .alertThirdButtonReturn:
            completion(CheckPromptPreference.defaultValue)
        default:
            break
        }
    }
}
