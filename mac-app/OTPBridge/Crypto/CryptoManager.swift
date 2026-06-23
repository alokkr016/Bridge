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
            self.keyPair = stored
        } else {
            let newKey = Curve25519.KeyAgreement.PrivateKey()
            self.keyPair = newKey
            keyPairStore.savePrivateKey(newKey)
        }
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
