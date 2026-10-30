import Foundation
import Security

/// The GitHub token on this Mac, in the data protection keychain, never synchronized.
/// A build signed without an application identifier cannot reach that keychain, so
/// it falls back to the login keychain, where the item is still this app's alone.
enum MacKeychain {
    private static let account = "github.token"

    static func read() -> String? {
        for dataProtection in [true, false] {
            var query = baseQuery(dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
                return String(decoding: data, as: UTF8.self)
            }
        }
        return nil
    }

    static func save(_ token: String) -> OSStatus {
        delete()
        var status = errSecMissingEntitlement
        for dataProtection in [true, false] where status == errSecMissingEntitlement {
            var add = baseQuery(dataProtection: dataProtection)
            add[kSecValueData as String] = Data(token.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status
    }

    static func delete() {
        for dataProtection in [true, false] {
            SecItemDelete(baseQuery(dataProtection: dataProtection) as CFDictionary)
        }
    }

    private static func baseQuery(dataProtection: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.arkwerx.northlight",
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtection,
        ]
    }
}
