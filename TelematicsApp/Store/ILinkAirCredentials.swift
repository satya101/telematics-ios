import Foundation
import Security

/// iLinkAir username and password, kept only in the iOS Keychain (this device, unlocked).
enum ILinkAirCredentials {
    private static let service = "com.satya101.whgtelematics.ilinkair"

    struct Credentials: Equatable {
        var username: String
        var password: String
    }

    static func load() -> Credentials? {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let dict = item as? [String: Any],
              let user = dict[kSecAttrAccount as String] as? String,
              let data = dict[kSecValueData as String] as? Data else { return nil }
        return Credentials(username: user, password: String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    static func save(_ creds: Credentials) -> Bool {
        delete()
        var item = baseQuery
        item[kSecAttrAccount as String] = creds.username
        item[kSecValueData as String] = Data(creds.password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }
}
