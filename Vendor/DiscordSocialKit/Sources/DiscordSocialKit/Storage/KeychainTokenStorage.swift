#if IRPC_XTOOL
import Foundation
import Security

/// Device-local credentials, available after first unlock for background sessions.
/// No access group or synchronizable attribute: no shared keychain or iCloud sync.
@MainActor
public final class KeychainTokenStorage: TokenStorage {
    private let service: String

    public init(service: String) { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "discord-oauth"]
    }

    public func load() throws -> DiscordToken? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw StorageError.invalidData }
        return try JSONDecoder().decode(DiscordToken.self, from: data)
    }

    public func save(_ token: DiscordToken) throws {
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(token),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
    }

    private enum StorageError: LocalizedError {
        case keychain(OSStatus), invalidData
        var errorDescription: String? {
            switch self {
            case .keychain(let status): return "Keychain operation failed (\(status))."
            case .invalidData: return "Stored Discord credentials are unreadable."
            }
        }
    }
}
#endif
