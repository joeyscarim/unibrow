import CryptoKit
import Foundation
import Security

enum ThumbnailCacheEncryption {
    /// One AES key at a time. Created on first encrypt after install or after cache clear.
    /// Clearing the thumbnail cache deletes files and this key; the next thumbnail creates a new key.

    static func deleteEncryptionKey() {
        deleteKeyData(
            service: KeychainIdentifiers.service,
            account: KeychainIdentifiers.thumbnailEncryptionAccount
        )
        deleteKeyData(
            service: KeychainIdentifiers.legacyThumbnailService,
            account: KeychainIdentifiers.legacyThumbnailAccount
        )
    }

    static func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: try symmetricKey())
        guard let combined = sealed.combined else {
            throw CacheEncryptionError.sealFailed
        }
        return combined
    }

    static func decrypt(_ ciphertext: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: try symmetricKey())
    }

    private static func symmetricKey() throws -> SymmetricKey {
        if let keyData = loadKeyData() {
            return SymmetricKey(data: keyData)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try saveKeyData(keyData)
        return key
    }

    private static func loadKeyData() -> Data? {
        if let data = readKeyData(
            service: KeychainIdentifiers.service,
            account: KeychainIdentifiers.thumbnailEncryptionAccount
        ) {
            return data
        }

        if let legacyData = readKeyData(
            service: KeychainIdentifiers.legacyThumbnailService,
            account: KeychainIdentifiers.legacyThumbnailAccount
        ) {
            try? saveKeyData(legacyData)
            deleteKeyData(
                service: KeychainIdentifiers.legacyThumbnailService,
                account: KeychainIdentifiers.legacyThumbnailAccount
            )
            return legacyData
        }

        return nil
    }

    private static func saveKeyData(_ data: Data) throws {
        deleteKeyData(
            service: KeychainIdentifiers.service,
            account: KeychainIdentifiers.thumbnailEncryptionAccount
        )

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainIdentifiers.service,
            kSecAttrAccount as String: KeychainIdentifiers.thumbnailEncryptionAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CacheEncryptionError.keyStorageFailed
        }
    }

    private static func readKeyData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return data
    }

    private static func deleteKeyData(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}

enum CacheEncryptionError: Error {
    case sealFailed
    case keyStorageFailed
}
