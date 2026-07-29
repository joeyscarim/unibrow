import Foundation
import Security

enum KeychainService {
    static func savePassword(_ password: String, account: String) {
        let data = Data(password.utf8)

        deletePassword(account: account, service: KeychainIdentifiers.legacyPasswordService)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainIdentifiers.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        deletePassword(account: account, service: KeychainIdentifiers.service)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadPassword(account: String) -> String {
        if let password = loadPassword(account: account, service: KeychainIdentifiers.service) {
            return password
        }

        if let legacyPassword = loadPassword(account: account, service: KeychainIdentifiers.legacyPasswordService) {
            savePassword(legacyPassword, account: account)
            return legacyPassword
        }

        return ""
    }

    static func deletePassword(account: String) {
        deletePassword(account: account, service: KeychainIdentifiers.service)
        deletePassword(account: account, service: KeychainIdentifiers.legacyPasswordService)
    }

    private static func loadPassword(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    private static func deletePassword(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
