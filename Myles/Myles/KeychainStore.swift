import Foundation
import Security

/// Small wrapper around macOS Keychain for storing OAuth tokens + client_id.
///
/// Why Keychain and not UserDefaults / a file:
///   • Encrypted at rest, tied to the user's login credentials
///   • Not readable by other apps on the same Mac
///   • Doesn't get synced to iCloud unless we explicitly opt in
///   • Survives app updates (unlike UserDefaults if we ever migrate)
///
/// Everything is stored as a Data blob under a string key. We only expose the
/// three keys we actually use so callers can't typo them.
enum KeychainStore {

    enum Key: String {
        /// The `client_id` returned by Swiggy's Dynamic Client Registration.
        /// Not secret per OAuth's public-client model, but keeping it in
        /// Keychain alongside the tokens keeps everything in one place.
        case swiggyClientId

        /// Short-lived (Swiggy: ~5 days) — used as Bearer on API calls.
        case swiggyAccessToken

        /// Long-lived — used to mint a new access token when it expires.
        case swiggyRefreshToken
    }

    // MARK: - Public API

    static func set(_ value: String, for key: Key) throws {
        try setData(Data(value.utf8), for: key)
    }

    static func get(_ key: Key) -> String? {
        guard let data = getData(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: Key) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        // errSecItemNotFound is fine — we asked to delete something that
        // already wasn't there, which is the desired end state.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    /// Wipe all Swiggy-related items. Used on logout or auth reset.
    static func clearAll() {
        Key.allCases.forEach { try? delete($0) }
    }

    // MARK: - Internals

    private static func setData(_ data: Data, for key: Key) throws {
        // Try update-in-place first (in case the item already exists),
        // then fall back to adding a new item.
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, update as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery(for: key)
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.osStatus(updateStatus)
        }
    }

    private static func getData(_ key: Key) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dharani.Myles",
            kSecAttrAccount as String: key.rawValue
        ]
    }
}

// MARK: - Support types

extension KeychainStore.Key: CaseIterable {}

enum KeychainError: Error, LocalizedError {
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .osStatus(let status):
            return "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        }
    }
}
