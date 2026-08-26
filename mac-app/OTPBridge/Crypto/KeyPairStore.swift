import Foundation
import CryptoKit
import Security

class KeyPairStore {

    private let deviceIdKey = "com.otpbridge.deviceId"
    private let privateKeyTag = "com.otpbridge.privateKey"
    /// Durable copy. Keychain is often unavailable when a login item starts,
    /// and the old path minted a new key (same device id) which broke pairing
    /// after every Mac reboot.
    private let privateKeyDefaultsKey = "com.otpbridge.privateKeyData"

    func getDeviceId() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }

    func rotateDeviceId() {
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        NSLog("[OTPBridge] Rotated device id to %@", newId)
    }

    func savePrivateKey(_ key: Curve25519.KeyAgreement.PrivateKey) {
        let data = key.rawRepresentation
        UserDefaults.standard.set(data, forKey: privateKeyDefaultsKey)
        savePrivateKeyToKeychain(data)
    }

    /// Write both stores if one is missing (migration after update).
    func ensurePersisted(_ key: Curve25519.KeyAgreement.PrivateKey) {
        let data = key.rawRepresentation
        if UserDefaults.standard.data(forKey: privateKeyDefaultsKey) != data {
            UserDefaults.standard.set(data, forKey: privateKeyDefaultsKey)
        }
        if loadPrivateKeyFromKeychain() == nil {
            savePrivateKeyToKeychain(data)
        }
    }

    func loadPrivateKey() -> Curve25519.KeyAgreement.PrivateKey? {
        if let data = UserDefaults.standard.data(forKey: privateKeyDefaultsKey),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return key
        }
        if let key = loadPrivateKeyFromKeychain() {
            UserDefaults.standard.set(key.rawRepresentation, forKey: privateKeyDefaultsKey)
            NSLog("[OTPBridge] Migrated identity key from Keychain to defaults")
            return key
        }
        return nil
    }

    private func savePrivateKeyToKeychain(_ data: Data) {
        let tag = Data(privateKeyTag.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyTag,
            kSecAttrAccount as String: "identity",
            kSecAttrApplicationTag as String: tag
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attrs) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                NSLog("[OTPBridge] Keychain add failed: %d", addStatus)
            }
        } else if status != errSecSuccess {
            NSLog("[OTPBridge] Keychain update failed: %d", status)
        }
        // Drop the old kSecClassKey item so we don't keep two identities.
        let legacy: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: privateKeyTag
        ]
        SecItemDelete(legacy as CFDictionary)
    }

    private func loadPrivateKeyFromKeychain() -> Curve25519.KeyAgreement.PrivateKey? {
        if let key = loadGenericPasswordKey() { return key }
        return loadLegacyClassKey()
    }

    private func loadGenericPasswordKey() -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyTag,
            kSecAttrAccount as String: "identity",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                NSLog("[OTPBridge] Keychain generic read failed: %d", status)
            }
            return nil
        }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    private func loadLegacyClassKey() -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: privateKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    func savePairedDevice(deviceId: String, publicKey: Data, ip: String, port: Int, sharedSecret: Data) {
        UserDefaults.standard.set(deviceId, forKey: "paired_device_id")
        UserDefaults.standard.set(publicKey, forKey: "paired_public_key")
        UserDefaults.standard.set(ip, forKey: "paired_ip")
        UserDefaults.standard.set(port, forKey: "paired_port")
        UserDefaults.standard.set(sharedSecret, forKey: "paired_shared_secret")
        UserDefaults.standard.set(true, forKey: "is_paired")
    }

    func getPairedDevice() -> PairedDevice? {
        guard UserDefaults.standard.bool(forKey: "is_paired") else { return nil }
        guard let deviceId = UserDefaults.standard.string(forKey: "paired_device_id"),
              let publicKey = UserDefaults.standard.data(forKey: "paired_public_key"),
              let ip = UserDefaults.standard.string(forKey: "paired_ip"),
              let sharedSecret = UserDefaults.standard.data(forKey: "paired_shared_secret") else {
            return nil
        }
        let port = UserDefaults.standard.integer(forKey: "paired_port")
        return PairedDevice(deviceId: deviceId, publicKey: publicKey, ip: ip, port: port, sharedSecret: sharedSecret)
    }

    func clearPairing() {
        UserDefaults.standard.removeObject(forKey: "paired_device_id")
        UserDefaults.standard.removeObject(forKey: "paired_public_key")
        UserDefaults.standard.removeObject(forKey: "paired_ip")
        UserDefaults.standard.removeObject(forKey: "paired_port")
        UserDefaults.standard.removeObject(forKey: "paired_shared_secret")
        UserDefaults.standard.set(false, forKey: "is_paired")
    }

    func isPaired() -> Bool {
        return UserDefaults.standard.bool(forKey: "is_paired")
    }
}

struct PairedDevice {
    let deviceId: String
    let publicKey: Data
    let ip: String
    let port: Int
    let sharedSecret: Data
}
