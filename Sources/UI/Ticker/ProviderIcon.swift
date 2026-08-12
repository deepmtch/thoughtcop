import AppKit

enum MessageProvider: String {
    case claude
    case chatGPT
    case unknown

    static func detect(from source: String) -> MessageProvider {
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.hasPrefix("claude") { return .claude }
        if normalized.hasPrefix("codex") || normalized.hasPrefix("chatgpt") {
            return .chatGPT
        }
        return .unknown
    }

    var accessibilityName: String {
        switch self {
        case .claude: return "Claude"
        case .chatGPT: return "ChatGPT"
        case .unknown: return "AI provider"
        }
    }

    var installedApplicationPath: String? {
        switch self {
        case .claude: return "/Applications/Claude.app"
        case .chatGPT: return "/Applications/ChatGPT.app"
        case .unknown: return nil
        }
    }

    func icon(fileManager: FileManager = .default) -> NSImage {
        if let applicationPath = installedApplicationPath,
           fileManager.fileExists(atPath: applicationPath) {
            let workspaceIcon = NSWorkspace.shared.icon(forFile: applicationPath)
            var sourceRect = NSRect(origin: .zero, size: workspaceIcon.size)
            if let representation = workspaceIcon.cgImage(forProposedRect: &sourceRect,
                                                           context: nil,
                                                           hints: nil) {
                return NSImage(cgImage: representation,
                               size: NSSize(width: 18, height: 18))
            }
        }

        let symbolName: String
        switch self {
        case .claude: symbolName = "sparkles"
        case .chatGPT: symbolName = "bubble.left.and.bubble.right.fill"
        case .unknown: symbolName = "brain.head.profile"
        }
        return NSImage(systemSymbolName: symbolName,
                       accessibilityDescription: accessibilityName) ?? NSImage()
    }
}

final class ProviderIconView: NSImageView {
    private(set) var provider: MessageProvider = .unknown

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyDown
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        update(source: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        imageScaling = .scaleProportionallyDown
        update(source: "")
    }

    func update(source: String) {
        provider = MessageProvider.detect(from: source)
        image = provider.icon()
        toolTip = "Provider: \(provider.accessibilityName)"
        setAccessibilityLabel("Provider: \(provider.accessibilityName)")
    }
}
