import Foundation
import CryptoKit
import Security

class KeyPairStore {

    private let deviceIdKey = "com.otpbridge.deviceId"
    private let privateKeyTag = "com.otpbridge.privateKey"

    func getDeviceId() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }

    func savePrivateKey(_ key: Curve25519.KeyAgreement.PrivateKey) {
        let data = key.rawRepresentation
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: privateKeyTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func loadPrivateKey() -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: privateKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
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
