// Provider credentials stored in the macOS login Keychain for installed builds.

import Foundation
import Security

enum CheckerProvider: String, CaseIterable, Hashable {
    case groq
    case cerebras

    var displayName: String { self == .groq ? "Groq" : "Cerebras" }
    var environmentKey: String { self == .groq ? "GROQ_API_KEY" : "CEREBRAS_API_KEY" }
}

enum CheckerCredentialEdit {
    case unchanged
    case set(String)
    case remove
}

protocol CredentialAccess {
    func read(account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func remove(account: String) throws
}

enum CredentialAccessError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain returned status \(status)."
        case .invalidData:
            return "The saved Keychain value is not valid UTF-8."
        }
    }
}

final class KeychainCredentialStore: CredentialAccess {
    // The Keychain service keeps the pre-rename identifier so existing
    // installs keep their saved provider keys after the ThoughtCop rename.
    static let service = "com.thinkpeek.desktop.provider-credentials"

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialAccessError.keychain(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8)
        else { throw CredentialAccessError.invalidData }
        return value.isEmpty ? nil : value
    }

    func save(_ value: String, account: String) throws {
        let query = baseQuery(account: account)
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw CredentialAccessError.keychain(updated)
        }
        var addition = query
        addition[kSecValueData as String] = Data(value.utf8)
        let added = SecItemAdd(addition as CFDictionary, nil)
        guard added == errSecSuccess else { throw CredentialAccessError.keychain(added) }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialAccessError.keychain(status)
        }
    }
}

final class CheckerCredentials {
    static let shared = CheckerCredentials(store: KeychainCredentialStore())

    private let store: CredentialAccess
    private let overrideLookup: (String) -> String?
    private let lock = NSLock()
    private var keychainValues: [CheckerProvider: String] = [:]
    private var keychainErrors: [CheckerProvider: String] = [:]
    private var loaded = false

    init(store: CredentialAccess,
         overrideLookup: @escaping (String) -> String? = dotenv) {
        self.store = store
        self.overrideLookup = overrideLookup
    }

    func reload() {
        lock.lock()
        defer { lock.unlock() }
        reloadLocked()
    }

    private func reloadLocked() {
        keychainValues.removeAll()
        keychainErrors.removeAll()
        for provider in CheckerProvider.allCases {
            do {
                if let value = try store.read(account: provider.environmentKey), !value.isEmpty {
                    keychainValues[provider] = value
                }
            } catch {
                keychainErrors[provider] = error.localizedDescription
            }
        }
        loaded = true
    }

    private func ensureLoadedLocked() {
        if !loaded { reloadLocked() }
    }

    /// Development environment and repository `.env` remain explicit overrides.
    /// Installed builds fall back to the login Keychain.
    func resolve(_ provider: CheckerProvider) -> String? {
        if let override = overrideLookup(provider.environmentKey), !override.isEmpty {
            return override
        }
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return keychainValues[provider]
    }

    func status(_ provider: CheckerProvider) -> String {
        if overrideLookup(provider.environmentKey) != nil {
            return "Active: environment or development .env"
        }
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        if keychainValues[provider] != nil { return "Active: macOS Keychain" }
        if keychainErrors[provider] != nil { return "Keychain unavailable" }
        return "Not configured"
    }

    func isConfigured(_ provider: CheckerProvider) -> Bool {
        resolve(provider) != nil
    }

    /// Returns provider-scoped errors only; secret values are never included.
    func apply(_ edits: [CheckerProvider: CheckerCredentialEdit]) -> [String] {
        var failures: [String] = []
        for provider in CheckerProvider.allCases {
            do {
                switch edits[provider] ?? .unchanged {
                case .unchanged:
                    break
                case .set(let value):
                    guard !value.isEmpty else { break }
                    try store.save(value, account: provider.environmentKey)
                case .remove:
                    try store.remove(account: provider.environmentKey)
                }
            } catch {
                failures.append("\(provider.displayName): \(error.localizedDescription)")
            }
        }
        reload()
        return failures
    }
}
