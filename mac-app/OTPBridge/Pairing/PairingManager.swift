import Foundation
import CryptoKit
import Security

class PairingManager {

    static let shared = PairingManager()

    private let cryptoManager = CryptoManager.shared
    private let keyPairStore = KeyPairStore()

    private(set) var isPairingModeActive = false
    private var pairingModeExpiry: Date?
    private(set) var pairingToken: String?
    private static let pairingWindowDuration: TimeInterval = 300

    private init() {}

    func beginPairingMode() {
        isPairingModeActive = true
        pairingModeExpiry = Date().addingTimeInterval(Self.pairingWindowDuration)
        pairingToken = Self.makeToken()
    }

    func endPairingMode() {
        isPairingModeActive = false
        pairingModeExpiry = nil
        pairingToken = nil
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func pairingModeAvailable() -> Bool {
        guard isPairingModeActive else { return false }
        if let expiry = pairingModeExpiry, Date() > expiry {
            endPairingMode()
            return false
        }
        return true
    }

    func shouldAcceptHandshake(publicKeyData: Data, token: String? = nil) -> Bool {
        guard publicKeyData.count == 32 else { return false }
        if let known = keyPairStore.getPairedDevice(), known.publicKey == publicKeyData {
            return true
        }
        guard pairingModeAvailable(), let expected = pairingToken, !expected.isEmpty else { return false }
        guard let token, token == expected else { return false }
        return true
    }

    func consumePairingToken() {
        pairingToken = nil
    }

    func isPaired() -> Bool {
        return keyPairStore.isPaired()
    }

    func getPairingURL() -> String? {
        guard let publicKey = cryptoManager.getPublicKeyData() else { return nil }
        let deviceId = cryptoManager.getDeviceId()
        let ip = getLocalIPAddress() ?? "127.0.0.1"
        let port = 8420
        let encodedKey = publicKey.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        if pairingToken == nil { beginPairingMode() }
        let token = pairingToken ?? ""
        return "otpbridge://\(deviceId)?pk=\(encodedKey)&ip=\(ip)&port=\(port)&token=\(token)"
    }

    func completePairing(deviceId: String, publicKeyData: Data) throws -> Bool {
        let sharedSecret = try cryptoManager.deriveSharedSecret(theirPublicKeyData: publicKeyData)
        let secretData = sharedSecret.withUnsafeBytes { Data($0) }
        let ip = getLocalIPAddress() ?? "127.0.0.1"
        keyPairStore.savePairedDevice(deviceId: deviceId, publicKey: publicKeyData, ip: ip, port: 8420, sharedSecret: secretData)
        return true
    }

    func clearPairing() {
        keyPairStore.clearPairing()
    }

    func getPairedDevice() -> PairedDevice? {
        return keyPairStore.getPairedDevice()
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}
