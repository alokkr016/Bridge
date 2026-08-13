import Foundation
import CryptoKit

class PairingManager {

    static let shared = PairingManager()

    private let cryptoManager = CryptoManager.shared
    private let keyPairStore = KeyPairStore()

    /// True only while the user has the pairing screen open.
    ///
    /// Security: an unauthenticated handshake must never be able to overwrite an
    /// existing pairing, or any device on the LAN could take over the session and
    /// receive OTPs. A first-time or replacement pairing is accepted only inside
    /// this window, which the user has to open deliberately.
    private(set) var isPairingModeActive = false
    private var pairingModeExpiry: Date?

    private static let pairingWindowDuration: TimeInterval = 300

    private init() {}

    func beginPairingMode() {
        isPairingModeActive = true
        pairingModeExpiry = Date().addingTimeInterval(Self.pairingWindowDuration)
        NSLog("[BridgePad] Pairing mode opened")
    }

    func endPairingMode() {
        guard isPairingModeActive else { return }
        isPairingModeActive = false
        pairingModeExpiry = nil
        NSLog("[BridgePad] Pairing mode closed")
    }

    func pairingModeAvailable() -> Bool {
        guard isPairingModeActive else { return false }
        if let expiry = pairingModeExpiry, Date() > expiry {
            NSLog("[BridgePad] Pairing mode expired")
            endPairingMode()
            return false
        }
        return true
    }

    /// Accepts a handshake only from the paired phone, or from any device while
    /// the user is actively pairing. Anything else is refused.
    func shouldAcceptHandshake(publicKeyData: Data) -> Bool {
        guard publicKeyData.count == 32 else {
            NSLog("[BridgePad] Rejecting handshake: bad key length \(publicKeyData.count)")
            return false
        }
        if let known = keyPairStore.getPairedDevice() {
            if known.publicKey == publicKeyData { return true }
            if pairingModeAvailable() {
                NSLog("[BridgePad] Replacing pairing — user is in pairing mode")
                return true
            }
            NSLog("[BridgePad] REJECTED handshake from unknown device (not in pairing mode)")
            return false
        }
        if pairingModeAvailable() { return true }
        NSLog("[BridgePad] REJECTED handshake: not paired and not in pairing mode")
        return false
    }

    func isPaired() -> Bool {
        return keyPairStore.isPaired()
    }

    func getPairingURL() -> String? {
        guard let publicKey = cryptoManager.getPublicKeyData() else { return nil }
        let deviceId = cryptoManager.getDeviceId()
        let ip = LocalAddress.ipv4() ?? "127.0.0.1"
        let port = 8420
        let encodedKey = publicKey.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "otpbridge://\(deviceId)?pk=\(encodedKey)&ip=\(ip)&port=\(port)"
    }

    func completePairing(deviceId: String, publicKeyData: Data) throws -> Bool {
        let sharedSecret = try cryptoManager.deriveSharedSecret(theirPublicKeyData: publicKeyData)
        let secretData = sharedSecret.withUnsafeBytes { Data($0) }
        let ip = LocalAddress.ipv4() ?? "127.0.0.1"
        keyPairStore.savePairedDevice(deviceId: deviceId, publicKey: publicKeyData, ip: ip, port: 8420, sharedSecret: secretData)
        return true
    }

    func clearPairing() {
        keyPairStore.clearPairing()
    }

    func getPairedDevice() -> PairedDevice? {
        return keyPairStore.getPairedDevice()
    }
}
