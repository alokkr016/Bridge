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
            return
        }
        if keyPairStore.isPaired() {
            for _ in 1...6 {
                Thread.sleep(forTimeInterval: 0.25)
                if let stored = keyPairStore.loadPrivateKey() {
                    keyPair = stored
                    keyPairStore.ensurePersisted(stored)
                    return
                }
            }
            keyPairStore.clearPairing()
            keyPairStore.rotateDeviceId()
        }
        let newKey = Curve25519.KeyAgreement.PrivateKey()
        keyPair = newKey
        keyPairStore.savePrivateKey(newKey)
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
        let raw = sharedSecret.withUnsafeBytes { Data($0) }
        return SessionCrypto.deriveKey(
            rawSecret: raw,
            myPublicKey: myKey.publicKey.rawRepresentation,
            theirPublicKey: theirPublicKeyData
        )
    }

    func seal(plaintext: Data, key: Data, seq: UInt64) throws -> Data {
        try SessionCrypto.seal(body: plaintext, key: key, seq: seq, encrypt: encrypt)
    }

    func openFrame(ciphertext: Data, key: Data) throws -> (seq: UInt64, body: Data) {
        try SessionCrypto.open(ciphertext: ciphertext, key: key, decrypt: decrypt)
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

enum SessionCrypto {
    private static let salt = Data("otpbridge-hkdf-salt-v2".utf8)
    private static let infoLabel = Data("otpbridge-session-v2".utf8)

    static func deriveKey(rawSecret: Data, myPublicKey: Data, theirPublicKey: Data) -> Data {
        hkdfSHA256(ikm: rawSecret, salt: salt, info: info(myPublicKey, theirPublicKey), length: 32)
    }

    static func signedBeacon(ip: String, port: Int, deviceId: String, secret: Data) -> String {
        let message = "OTPBRIDGE \(ip) \(port) \(deviceId)"
        let mac = Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: secret)))
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        return "\(message) \(hex)"
    }

    static func seal(body: Data, key: Data, seq: UInt64, encrypt: (Data, Data) throws -> Data) throws -> Data {
        let wrapper: [String: Any] = [
            "v": 2,
            "seq": NSNumber(value: seq),
            "body": String(data: body, encoding: .utf8) ?? ""
        ]
        return try encrypt(JSONSerialization.data(withJSONObject: wrapper), key)
    }

    static func open(ciphertext: Data, key: Data, decrypt: (Data, Data) throws -> Data) throws -> (seq: UInt64, body: Data) {
        let plain = try decrypt(ciphertext, key)
        guard let json = try JSONSerialization.jsonObject(with: plain) as? [String: Any],
              (json["v"] as? NSNumber)?.intValue == 2,
              let seq = (json["seq"] as? NSNumber)?.uint64Value, seq > 0,
              let body = json["body"] as? String else {
            throw CryptoManager.CryptoError.decryptionFailed
        }
        return (seq, Data(body.utf8))
    }

    static func hkdfSHA256(ikm: Data, salt: Data, info: Data, length: Int) -> Data {
        let extractKey = salt.isEmpty ? Data(count: 32) : salt
        let prk = Data(HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: extractKey)))
        var okm = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while okm.count < length {
            var blockInput = previous
            blockInput.append(info)
            blockInput.append(counter)
            previous = Data(HMAC<SHA256>.authenticationCode(for: blockInput, using: SymmetricKey(data: prk)))
            okm.append(previous)
            counter += 1
        }
        return okm.prefix(length)
    }

    private static func info(_ first: Data, _ second: Data) -> Data {
        let left: Data
        let right: Data
        if first.lexicographicallyPrecedes(second) || first == second {
            left = first
            right = second
        } else {
            left = second
            right = first
        }
        var out = infoLabel
        out.append(0)
        out.append(left)
        out.append(right)
        return out
    }
}
