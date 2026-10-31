import Foundation
import CryptoKit
import Security

class KeyPairStore {

    private let deviceIdKey = "com.otpbridge.deviceId"
    private let privateKeyTag = "com.otpbridge.privateKey"
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
        savePrivateKeyToKeychain(key.rawRepresentation)
        UserDefaults.standard.removeObject(forKey: privateKeyDefaultsKey)
    }

    func ensurePersisted(_ key: Curve25519.KeyAgreement.PrivateKey) {
        if loadPrivateKeyFromKeychain() == nil {
            savePrivateKeyToKeychain(key.rawRepresentation)
        }
        UserDefaults.standard.removeObject(forKey: privateKeyDefaultsKey)
    }

    func loadPrivateKey() -> Curve25519.KeyAgreement.PrivateKey? {
        if let key = loadPrivateKeyFromKeychain() {
            UserDefaults.standard.removeObject(forKey: privateKeyDefaultsKey)
            return key
        }
        if let data = UserDefaults.standard.data(forKey: privateKeyDefaultsKey),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            savePrivateKeyToKeychain(data)
            UserDefaults.standard.removeObject(forKey: privateKeyDefaultsKey)
            NSLog("[BridgePad] Moved identity key into Keychain")
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
        guard status == errSecSuccess, let data = result as? Data else { return nil }
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
        let previousKey = UserDefaults.standard.data(forKey: "paired_public_key")
        UserDefaults.standard.set(deviceId, forKey: "paired_device_id")
        UserDefaults.standard.set(publicKey, forKey: "paired_public_key")
        UserDefaults.standard.set(ip, forKey: "paired_ip")
        UserDefaults.standard.set(port, forKey: "paired_port")
        UserDefaults.standard.removeObject(forKey: "paired_shared_secret")
        UserDefaults.standard.set(true, forKey: "is_paired")
        saveSecretToKeychain(sharedSecret)
        if previousKey != publicKey {
            UserDefaults.standard.set("0", forKey: sendSeqKey)
            UserDefaults.standard.set("0", forKey: recvSeqKey)
        }
    }

    func getPairedDevice() -> PairedDevice? {
        guard UserDefaults.standard.bool(forKey: "is_paired") else { return nil }
        guard let deviceId = UserDefaults.standard.string(forKey: "paired_device_id"),
              let publicKey = UserDefaults.standard.data(forKey: "paired_public_key"),
              let ip = UserDefaults.standard.string(forKey: "paired_ip"),
              let sharedSecret = loadSharedSecret() else {
            return nil
        }
        let port = UserDefaults.standard.integer(forKey: "paired_port")
        return PairedDevice(deviceId: deviceId, publicKey: publicKey, ip: ip, port: port, sharedSecret: sharedSecret)
    }

    func allocateSendSeq() -> UInt64 {
        seqLock.lock()
        defer { seqLock.unlock() }
        let current = UInt64(UserDefaults.standard.string(forKey: sendSeqKey) ?? "0") ?? 0
        let next = current &+ 1
        UserDefaults.standard.set(String(next), forKey: sendSeqKey)
        return next
    }

    func acceptRecvSeq(_ seq: UInt64) -> Bool {
        seqLock.lock()
        defer { seqLock.unlock() }
        guard seq > 0 else { return false }
        let current = UInt64(UserDefaults.standard.string(forKey: recvSeqKey) ?? "0") ?? 0
        guard seq > current else { return false }
        UserDefaults.standard.set(String(seq), forKey: recvSeqKey)
        return true
    }

    func clearPairing() {
        UserDefaults.standard.removeObject(forKey: "paired_device_id")
        UserDefaults.standard.removeObject(forKey: "paired_public_key")
        UserDefaults.standard.removeObject(forKey: "paired_ip")
        UserDefaults.standard.removeObject(forKey: "paired_port")
        UserDefaults.standard.removeObject(forKey: "paired_shared_secret")
        UserDefaults.standard.removeObject(forKey: sendSeqKey)
        UserDefaults.standard.removeObject(forKey: recvSeqKey)
        UserDefaults.standard.set(false, forKey: "is_paired")
        deleteKeychainItem(account: secretAccount)
    }

    private let secretAccount = "paired-secret"
    private let sendSeqKey = "paired_send_seq"
    private let recvSeqKey = "paired_recv_seq"
    private let seqLock = NSLock()

    private func loadSharedSecret() -> Data? {
        if let data = loadGenericPassword(account: secretAccount) {
            UserDefaults.standard.removeObject(forKey: "paired_shared_secret")
            return data
        }
        if let legacy = UserDefaults.standard.data(forKey: "paired_shared_secret") {
            saveSecretToKeychain(legacy)
            UserDefaults.standard.removeObject(forKey: "paired_shared_secret")
            return legacy
        }
        return nil
    }

    private func saveSecretToKeychain(_ data: Data) {
        saveGenericPassword(data, account: secretAccount)
    }

    private func saveGenericPassword(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyTag,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attrs) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func loadGenericPassword(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyTag,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyTag,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
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
