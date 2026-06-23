import XCTest
@testable import OTPBridge

final class CryptoManagerTests: XCTestCase {

    func testKeyGeneration() {
        let key1 = CryptoManager.shared
        let key2 = CryptoManager.shared
        XCTAssertNotNil(key1.getDeviceId())
        XCTAssertEqual(key1.getDeviceId(), key2.getDeviceId())
    }

    func testEncryptDecryptRoundtrip() throws {
        let crypto = CryptoManager.shared
        let testData = "Hello, OTP Bridge!".data(using: .utf8)!

        let symmetricKey = SymmetricKey(size: .bits256)
        let encrypted = try crypto.encrypt(plaintext: testData, key: symmetricKey)
        let decrypted = try crypto.decrypt(ciphertext: encrypted, key: symmetricKey)

        XCTAssertEqual(decrypted, testData)
    }

    func testSharedSecretDerivation() throws {
        let private1 = P256.KeyAgreement.PrivateKey()
        let private2 = P256.KeyAgreement.PrivateKey()

        let secret1 = try private1.sharedSecretFromKeyAgreement(with: private2.publicKey)
        let secret2 = try private2.sharedSecretFromKeyAgreement(with: private1.publicKey)

        let key1 = secret1.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "OTPBridge-v1".data(using: .utf8)!,
            outputByteCount: 32
        )
        let key2 = secret2.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "OTPBridge-v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        XCTAssertEqual(key1, key2)
    }
}
