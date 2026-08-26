import Foundation
import CryptoKit

class CryptoManager {

    static let shared = CryptoManager()

    private var keyPair: Curve25519.KeyAgreement.PrivateKey?
    private let keyPairStore = KeyPairStore()

    private init() {
        loadOrCreateKeyPair()
    }

    private func loadOrCreateKeyPair() {
        if let stored = keyPairStore.loadPrivateKey() {
            keyPair = stored
            keyPairStore.ensurePersisted(stored)
            logIdentity(source: "stored")
            return
        }

        // Login-item start can miss Keychain for a moment. Never mint a new
        // identity while a pairing exists — that is what broke reconnect after reboot.
        if keyPairStore.isPaired() {
            for attempt in 1...6 {
                Thread.sleep(forTimeInterval: 0.25)
                if let stored = keyPairStore.loadPrivateKey() {
                    keyPair = stored
                    keyPairStore.ensurePersisted(stored)
                    logIdentity(source: "retry-\(attempt)")
                    return
                }
            }
            NSLog("[OTPBridge] Identity key missing while paired — rotating id so the phone will not treat us as an impostor")
            keyPairStore.clearPairing()
            keyPairStore.rotateDeviceId()
        }

        let newKey = Curve25519.KeyAgreement.PrivateKey()
        keyPair = newKey
        keyPairStore.savePrivateKey(newKey)
        logIdentity(source: "new")
    }

    private func logIdentity(source: String) {
        let prefix = getPublicKeyData()?.prefix(4).map { String(format: "%02x", $0) }.joined() ?? "?"
        NSLog("[OTPBridge] Identity %@ pk=%@… id=%@", source, prefix, getDeviceId())
    }

    func getDeviceId() -> String {
        return keyPairStore.getDeviceId()
    }

    func getPublicKey() -> Curve25519.KeyAgreement.PublicKey? {
        return keyPair?.publicKey
    }

    func getPublicKeyData() -> Data? {
        return keyPair?.publicKey.rawRepresentation
    }

    func deriveSharedSecret(theirPublicKeyData: Data) throws -> Data {
        guard let myKey = keyPair else {
            throw CryptoError.noKeyPair
        }

        let theirPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirPublicKeyData)
        let sharedSecret = try myKey.sharedSecretFromKeyAgreement(with: theirPublicKey)
        let derived = SHA256.hash(data: sharedSecret.withUnsafeBytes { Data($0) })
        return Data(derived)
    }

    func encrypt(plaintext: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else { throw CryptoError.encryptionFailed }
        return combined
    }

    func decrypt(ciphertext: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    func parsePublicKey(_ data: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }

    enum CryptoError: Error {
        case noKeyPair
        case encryptionFailed
        case decryptionFailed
    }
}
