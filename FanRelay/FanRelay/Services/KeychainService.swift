import Foundation
import Security   // the Keychain APIs live here (built in, no dependency)

/// Stores the user's Nostr secret key in the iOS Keychain.
///
/// We keep the *raw 32 bytes* of the secret key — not the `nsec` text form.
/// That keeps this type tiny and independent: it knows nothing about Nostr,
/// bech32, or NIP-19. It just safely saves, loads, and deletes a small blob
/// of bytes under one fixed name.
///
/// The Keychain is the right home for this because it's encrypted at rest and
/// survives app relaunches and updates — unlike the ephemeral key the slice
/// generated fresh every launch.
enum KeychainService {

    /// Anything that can go wrong, surfaced so the ViewModel can show a message.
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)   // the Keychain returned an error code
        case wrongSize                    // a loaded key wasn't 32 bytes
    }

    /// Identifiers the Keychain files this item under. `service` namespaces it
    /// to our app; `account` names this particular secret. Together they're the
    /// unique key for save/load/delete.
    private static let service = "com.fanrelay.nostr"
    private static let account = "nostr-secret-key"

    /// Nostr secret keys are exactly 32 bytes.
    private static let keyLength = 32

    // MARK: - Save

    /// Store the secret key bytes, replacing any existing one.
    /// We delete first so a second save doesn't error with "already exists".
    static func saveSecretKey(_ keyBytes: [UInt8]) throws {
        guard keyBytes.count == keyLength else { throw KeychainError.wrongSize }

        // Remove any previous value so SecItemAdd can't collide with it.
        try? deleteSecretKey()

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String:   Data(keyBytes),
            // Readable only after first unlock, and only on this device
            // (never synced to iCloud or restored to a different device).
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Load

    /// Read the secret key back. Returns `nil` if nothing is stored yet
    /// (i.e. a brand-new install that hasn't onboarded).
    static func loadSecretKey() throws -> [UInt8]? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil   // nothing stored — not an error, just "no key yet"
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, data.count == keyLength else {
            throw KeychainError.wrongSize
        }
        return [UInt8](data)
    }

    // MARK: - Delete

    /// Remove the stored key (used by "reset identity" later, in Settings).
    static func deleteSecretKey() throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        // "not found" is fine — it just means there was nothing to delete.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Convenience for onboarding flow: is there already a key stored?
    static func hasSecretKey() -> Bool {
        (try? loadSecretKey()) != nil
    }
}
