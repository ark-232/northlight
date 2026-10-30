import Foundation
import Security

/// Secrets on this Apple TV only: never synchronized, never in CloudKit.
enum Keychain {
    enum Item: String {
        case calendarURL = "calendar.ics"
        case githubToken = "github.token"
        /// The Apple ID, its app-specific password and the calendars chosen, as JSON.
        case icloud = "icloud.calendars"
    }

    struct Failure: Error {
        let status: OSStatus
    }

    static func read(_ item: Item) -> String? {
        var query = baseQuery(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Updates the item in place, adding it only when it does not exist yet.
    static func save(_ value: String, as item: Item) throws(Failure) {
        let data = Data(value.utf8)
        let updated = SecItemUpdate(baseQuery(item) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw Failure(status: updated) }

        var add = baseQuery(item)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure(status: added) }
    }

    static func delete(_ item: Item) {
        SecItemDelete(baseQuery(item) as CFDictionary)
    }

    private static func baseQuery(_ item: Item) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.arkwerx.northlight",
            kSecAttrAccount as String: item.rawValue,
        ]
    }
}
