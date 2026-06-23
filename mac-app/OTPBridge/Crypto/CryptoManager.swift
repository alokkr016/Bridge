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

    func deriveSharedSecret(theirPublicKeyData: Data) throws -> SymmetricKey {
        guard let myKey = keyPair else {
            throw CryptoError.noKeyPair
        }

        let theirPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirPublicKeyData)
        let sharedSecret = try myKey.sharedSecretFromKeyAgreement(with: theirPublicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "OTPBridge-v1".data(using: .utf8)!,
            outputByteCount: 32
        )
    }

    func encrypt(plaintext: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(plaintext, using: key)
        return sealedBox.combined
    }

    func decrypt(ciphertext: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: ciphertext)
        return try ChaChaPoly.open(sealedBox, using: key)
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
