import Foundation
import Security

/// Secrets live in the login keychain, never in UserDefaults, never in a file
/// inside the app bundle, and never in a log line.
public enum Keychain {
    public enum Failure: Error, LocalizedError {
        case status(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .status(let code):
                let message = SecCopyErrorMessageString(code, nil) as String? ?? "Keychain error \(code)"
                return message
            }
        }
    }

    private static let service = "com.mikeshobes.PuraMac"

    public static func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func set(_ value: String?, for account: String) throws {
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw Failure.status(status)
            }
            return
        }

        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw Failure.status(updateStatus) }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Failure.status(addStatus) }
    }

    public static func hasValue(for account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum Credentials {
    public static let openRouterAccount = "openrouter-api-key"

    public static var openRouterKey: String? {
        Keychain.string(for: openRouterAccount)
    }

    public static func setOpenRouterKey(_ key: String?) throws {
        try Keychain.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: openRouterAccount)
    }

    /// Earlier builds read the key from a plaintext .env path. If one is still
    /// there, move it into the keychain once so the upgrade is seamless, then
    /// stop reading from disk entirely.
    @discardableResult
    public static func migrateLegacyKeyIfNeeded(
        legacyPath: String = NSHomeDirectory() + "/Documents/Keys/.env"
    ) -> Bool {
        guard !Keychain.hasValue(for: openRouterAccount),
              let contents = try? String(contentsOfFile: legacyPath, encoding: .utf8) else {
            return false
        }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("OPENROUTER_API_KEY=") else { continue }
            let value = String(trimmed.dropFirst("OPENROUTER_API_KEY=".count))
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { continue }
            try? setOpenRouterKey(value)
            Log.ai.info("Migrated OpenRouter key from legacy file into the keychain")
            return true
        }
        return false
    }
}
