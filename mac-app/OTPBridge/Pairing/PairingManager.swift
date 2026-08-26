import Foundation
import CryptoKit
import Security

class PairingManager {

    static let shared = PairingManager()

    private let cryptoManager = CryptoManager.shared
    private let keyPairStore = KeyPairStore()

    /// True only while the user has the pairing window open.
    ///
    /// Security: an unauthenticated handshake must never be able to overwrite an
    /// existing pairing, or any device on the LAN could take over the session and
    /// receive OTPs. A first-time or replacement pairing is accepted only inside
    /// this window, which the user has to open deliberately.
    private(set) var isPairingModeActive = false
    private var pairingModeExpiry: Date?
    /// One-time token embedded in the QR. A reconnect without this token
    /// cannot complete a *new* pairing, even while the window is open.
    private(set) var pairingToken: String?

    /// How long the window stays open, in case the UI forgets to close it.
    private static let pairingWindowDuration: TimeInterval = 300

    private init() {}

    func beginPairingMode() {
        isPairingModeActive = true
        pairingModeExpiry = Date().addingTimeInterval(Self.pairingWindowDuration)
        pairingToken = Self.makeToken()
        NSLog("[OTPBridge] Pairing mode opened")
    }

    func endPairingMode() {
        guard isPairingModeActive else { return }
        isPairingModeActive = false
        pairingModeExpiry = nil
        pairingToken = nil
        NSLog("[OTPBridge] Pairing mode closed")
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Pairing mode, with its timeout applied.
    func pairingModeAvailable() -> Bool {
        guard isPairingModeActive else { return false }
        if let expiry = pairingModeExpiry, Date() > expiry {
            NSLog("[OTPBridge] Pairing mode expired")
            endPairingMode()
            return false
        }
        return true
    }

    /// Decides whether a handshake offering `publicKeyData` may proceed.
    ///
    /// Accepts when the key matches the stored pairing (the normal reconnect
    /// case), or when the user is actively pairing. Everything else is an
    /// unknown device on the network and is refused.
    func shouldAcceptHandshake(publicKeyData: Data, token: String? = nil) -> Bool {
        guard publicKeyData.count == 32 else {
            NSLog("[OTPBridge] Rejecting handshake: bad key length \(publicKeyData.count)")
            return false
        }
        if let known = keyPairStore.getPairedDevice(), known.publicKey == publicKeyData {
            return true
        }
        // New or replacement pairing requires the token from this QR. Opening
        // the window is not enough — the already-paired phone reconnects on
        // its own and used to look like a successful scan.
        guard pairingModeAvailable(), let expected = pairingToken, !expected.isEmpty else {
            NSLog("[OTPBridge] REJECTED handshake: unknown device (not a QR scan)")
            return false
        }
        guard let token, token == expected else {
            NSLog("[OTPBridge] REJECTED handshake: missing or wrong pairing token")
            return false
        }
        NSLog("[OTPBridge] Accepting new pairing from QR scan")
        return true
    }

    func consumePairingToken() {
        pairingToken = nil
    }

    func matchesPairingToken(_ token: String?) -> Bool {
        guard pairingModeAvailable(), let expected = pairingToken, !expected.isEmpty else { return false }
        return token == expected
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
        let name = pairingDisplayName()
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        if pairingToken == nil { beginPairingMode() }
        let token = pairingToken ?? ""
        return "otpbridge://\(deviceId)?pk=\(encodedKey)&ip=\(ip)&port=\(port)&kind=mac&name=\(encodedName)&token=\(token)"
    }

    private func pairingDisplayName() -> String {
        if let host = Host.current().localizedName, !host.isEmpty { return host }
        let hostname = ProcessInfo.processInfo.hostName
        if hostname.hasSuffix(".local") {
            return String(hostname.dropLast(6))
        }
        return hostname.isEmpty ? "Mac" : hostname
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
