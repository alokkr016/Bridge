import Foundation
import Network
import CryptoKit

class WebSocketServer {

    static let shared = WebSocketServer()

    private var listener: NWListener?
    private var connection: NWConnection?
    private var sharedSecret: Data?
    private let cryptoManager = CryptoManager.shared
    private let pairingManager = PairingManager.shared
    private let keyPairStore = KeyPairStore()
    /// Orders sequence allocation with the bytes on the wire. A later frame
    /// must not overtake an earlier one or the phone treats it as a replay.
    private let sendQueue = DispatchQueue(label: "io.github.alokkr016.otpbridge.send")

    var onOTPReceived: ((String, String, String?, TimeInterval) -> Void)?
    var onCallReceived: ((String, String, String?) -> Void)?

    var isConnected = false {
        didSet {
            DispatchQueue.main.async {
                self.onConnectionChanged?(self.isConnected)
            }
        }
    }

    var onConnectionChanged: ((Bool) -> Void)?
    var onHandshakeReceived: ((String, Data) -> Void)?
    /// Fires only when pairing mode accepted a *new* device, not a reconnect.
    var onNewPairingCompleted: ((String, Data) -> Void)?

    private init() {}

    func start() {
        // If already listening, don't restart — avoids cancelling a healthy listener
        // when PairingWindow calls start() redundantly.
        if let existing = listener, existing.state == .ready {
            NSLog("[OTPBridge] Server already listening, skipping restart")
            return
        }

        stop()

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: 8420)!)

            listener?.newConnectionHandler = { [weak self] newConnection in
                NSLog("[OTPBridge] New TCP connection")
                self?.handleNewConnection(newConnection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    NSLog("[OTPBridge] Server listening on port 8420")
                case .failed(let error):
                    NSLog("[OTPBridge] Server failed: \(error), will restart")
                    self?.listener = nil
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        self?.start()
                    }
                default:
                    break
                }
            }

            listener?.start(queue: .global())
        } catch {
            NSLog("[OTPBridge] Failed to start server: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        connection?.cancel()
        listener = nil
        connection = nil
        isConnected = false
        DispatchQueue.main.async {
            ClipboardManager.shared.stopSyncing()
        }
    }

    private func handleNewConnection(_ newConnection: NWConnection) {
        guard isPrivateLan(newConnection) else {
            NSLog("[OTPBridge] Rejected connection from a non-local address")
            newConnection.cancel()
            return
        }
        if let existing = connection {
            existing.cancel()
        }
        connection = newConnection
        // Clear per-connection state so a fresh handshake is required
        sharedSecret = nil
        isConnected = false
        newConnection.start(queue: .global())
        readLoop(connection: newConnection)
    }

    private func isPrivateLan(_ connection: NWConnection) -> Bool {
        guard case let .hostPort(host, _) = connection.endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return Self.isPrivateIPv4(String(describing: address))
        case .ipv6(let address):
            let text = String(describing: address).lowercased()
            return text == "::1" || text.hasPrefix("fe80") || text.hasPrefix("fc") || text.hasPrefix("fd")
        default:
            return false
        }
    }

    private static func isPrivateIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 10 || parts[0] == 127 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        return false
    }

    /// Only the *current* connection may flip UI / server state. A cancelled
    /// predecessor's read loop finishing after a reconnect used to set
    /// `isConnected = false` and nil out the new socket, leaving the menu bar
    /// stuck on Offline even though TCP + handshake had succeeded.
    private func markDisconnected(ifCurrent candidate: NWConnection) {
        guard connection === candidate else {
            NSLog("[OTPBridge] Ignoring close from stale connection")
            return
        }
        isConnected = false
        connection = nil
        sharedSecret = nil
        DispatchQueue.main.async {
            ClipboardManager.shared.stopSyncing()
        }
    }

    private func readLoop(connection: NWConnection) {
        readFourBytes(connection: connection) { [weak self] lengthData in
            guard let self = self, let ld = lengthData else {
                NSLog("[OTPBridge] Connection closed or error reading length")
                self?.markDisconnected(ifCurrent: connection)
                return
            }
            let length = Int(ld[0]) << 24 | Int(ld[1]) << 16 | Int(ld[2]) << 8 | Int(ld[3])
            // length == 0 is a keepalive ping — echo it so the phone can
            // detect a half-open socket after the iPad/Mac app restarts.
            if length == 0 {
                var pong = Data(count: 4)
                connection.send(content: pong, completion: .contentProcessed { _ in })
                self.readLoop(connection: connection)
                return
            }
            guard length < 1_000_000 else {
                NSLog("[OTPBridge] Invalid length \(length), disconnecting")
                self.markDisconnected(ifCurrent: connection)
                return
            }
            self.readBytes(connection: connection, count: length) { payloadData in
                guard let data = payloadData else {
                    NSLog("[OTPBridge] Error reading payload")
                    self.markDisconnected(ifCurrent: connection)
                    return
                }
                self.processMessage(data)
                self.readLoop(connection: connection)
            }
        }
    }

    private func readFourBytes(connection: NWConnection, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, isComplete, error in
            if let error = error {
                NSLog("[OTPBridge] readFourBytes error: \(error)")
                completion(nil)
                return
            }
            // isComplete can arrive together with the last bytes — don't drop them.
            if let data, data.count == 4 {
                completion(data)
                return
            }
            if isComplete || data == nil {
                completion(nil)
                return
            }
            completion(data)
        }
    }

    private func readBytes(connection: NWConnection, count: Int, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, isComplete, error in
            if let error = error {
                NSLog("[OTPBridge] readBytes error: \(error)")
                completion(nil)
                return
            }
            if let data, data.count == count {
                completion(data)
                return
            }
            if isComplete || data == nil {
                completion(nil)
                return
            }
            completion(data)
        }
    }

    private func processMessage(_ data: Data) {
        if let secret = sharedSecret {
            do {
                let opened = try cryptoManager.openFrame(ciphertext: data, key: secret)
                guard keyPairStore.acceptRecvSeq(opened.seq) else {
                    NSLog("[OTPBridge] Rejected replayed frame")
                    return
                }
                let json = try JSONSerialization.jsonObject(with: opened.body) as? [String: Any]
                guard let type = json?["type"] as? String else { return }

                if type == "otp" {
                    guard FeatureSettings.shared.otpForwardingEnabled else {
                        NSLog("[OTPBridge] OTP received but forwarding is disabled — ignoring")
                        return
                    }
                    let sender = json?["sender"] as? String ?? "Unknown"
                    let otp = json?["otp"] as? String ?? ""
                    let company = json?["company"] as? String
                    // Android sends millis; convert to seconds for TimeInterval
                    let rawTs = json?["timestamp"] as? TimeInterval ?? (Date().timeIntervalSince1970 * 1000)
                    let timestamp = rawTs > 1_000_000_000_000 ? rawTs / 1000.0 : rawTs
                    // Never log the code itself — the unified log is readable by
                    // other local processes and persists in diagnostics.
                    NSLog("[OTPBridge] OTP received (\(otp.count) digits) from \(company ?? sender)")
                    DispatchQueue.main.async {
                        self.onOTPReceived?(sender, otp, company, timestamp)
                    }
                } else if type == "clipboard" {
                    guard FeatureSettings.shared.clipboardSyncEnabled else {
                        NSLog("[OTPBridge] Clipboard received but sync is disabled — ignoring")
                        return
                    }
                    if let text = json?["text"] as? String {
                        NSLog("[OTPBridge] Clipboard received from Android")
                        DispatchQueue.main.async {
                            ClipboardManager.shared.receiveFromAndroid(text)
                        }
                    }
                } else if type == "call" {
                    guard FeatureSettings.shared.callHandlingEnabled else {
                        NSLog("[OTPBridge] Call event received but call handling is disabled — ignoring")
                        return
                    }
                    let state = json?["state"] as? String ?? "idle"
                    let number = json?["number"] as? String ?? ""
                    let name = json?["name"] as? String
                    NSLog("[OTPBridge] Call \(state)")
                    DispatchQueue.main.async {
                        self.onCallReceived?(state, number, name)
                    }
                }
            } catch {
                // A failed decrypt is not a handshake. Treating the ciphertext as
                // one let a peer on the socket replace the paired phone.
                NSLog("[OTPBridge] Decryption failed (\(error)) — closing connection")
                connection?.cancel()
                connection = nil
                sharedSecret = nil
                isConnected = false
            }
        } else {
            handleHandshake(data)
        }
    }

    private func handleHandshake(_ data: Data) {
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let type = json?["type"] as? String, type == "handshake" else {
                NSLog("[OTPBridge] Not a handshake message")
                return
            }
            guard let deviceId = json?["device_id"] as? String,
                  let publicKeyB64 = json?["public_key"] as? String else {
                NSLog("[OTPBridge] Handshake missing fields")
                return
            }

            let publicKeyData = Data(base64Encoded: publicKeyB64) ?? Data()
            NSLog("[OTPBridge] Handshake from \(deviceId), keyLen=\(publicKeyData.count)")

            // Only the paired phone, or a device the user is actively pairing,
            // may establish a session. Without this any host on the LAN could
            // hand us a key and start receiving OTPs.
            let token = json?["token"] as? String
            guard pairingManager.shouldAcceptHandshake(publicKeyData: publicKeyData, token: token) else {
                NSLog("[OTPBridge] Handshake refused — closing connection")
                connection?.cancel()
                connection = nil
                isConnected = false
                return
            }

            let scannedQR = pairingManager.matchesPairingToken(token)
            try pairingManager.completePairing(deviceId: deviceId, publicKeyData: publicKeyData)
            if scannedQR {
                pairingManager.consumePairingToken()
            }
            NSLog("[OTPBridge] Pairing saved")

            sharedSecret = try cryptoManager.deriveSharedSecret(theirPublicKeyData: publicKeyData)
            NSLog("[OTPBridge] Shared secret derived")

            let response: [String: Any] = [
                "type": "handshake_ack",
                "device_id": cryptoManager.getDeviceId(),
                "public_key": cryptoManager.getPublicKeyData()?.base64EncodedString() ?? ""
            ]
            let responseData = try JSONSerialization.data(withJSONObject: response)
            sendBinary(responseData)
            NSLog("[OTPBridge] Handshake ack sent")

            isConnected = true

            DispatchQueue.main.async {
                self.onHandshakeReceived?(deviceId, publicKeyData)
                // A QR token means the user actually scanned, even if this
                // phone was already stored (re-pair of the same device).
                if scannedQR {
                    self.onNewPairingCompleted?(deviceId, publicKeyData)
                }
                // Honours the clipboard-sync setting instead of always starting.
                FeatureSettings.shared.applyClipboardState()
            }
            NSLog("[OTPBridge] Connection established!")
        } catch {
            NSLog("[OTPBridge] Handshake failed: \(error)")
        }
    }

    func sendBinary(_ data: Data) {
        sendQueue.sync { writeFrame(data) }
    }

    private func writeFrame(_ data: Data) {
        guard let conn = connection else {
            NSLog("[OTPBridge] No connection to send on")
            return
        }
        var frame = Data()
        frame.append(UInt8((data.count >> 24) & 0xFF))
        frame.append(UInt8((data.count >> 16) & 0xFF))
        frame.append(UInt8((data.count >> 8) & 0xFF))
        frame.append(UInt8(data.count & 0xFF))
        frame.append(data)
        conn.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                NSLog("[OTPBridge] Send error: \(error)")
            }
        })
    }

    func sendCallControl(_ action: String) {
        guard FeatureSettings.shared.callHandlingEnabled else { return }
        guard let secret = sharedSecret else { return }
        sendQueue.sync {
            do {
                let payload = try JSONSerialization.data(withJSONObject: ["type": "call_control", "action": action])
                let seq = keyPairStore.allocateSendSeq()
                let encrypted = try cryptoManager.seal(plaintext: payload, key: secret, seq: seq)
                writeFrame(encrypted)
                NSLog("[OTPBridge] Call control sent: \(action)")
            } catch {
                NSLog("[OTPBridge] Failed to send call control: \(error)")
            }
        }
    }

    func sendClipboard(_ text: String) {
        guard FeatureSettings.shared.clipboardSyncEnabled else { return }
        guard let secret = sharedSecret else { return }
        sendQueue.sync {
            do {
                let payload = try JSONSerialization.data(withJSONObject: ["type": "clipboard", "text": text])
                let seq = keyPairStore.allocateSendSeq()
                let encrypted = try cryptoManager.seal(plaintext: payload, key: secret, seq: seq)
                writeFrame(encrypted)
                NSLog("[OTPBridge] Clipboard sent to Android")
            } catch {
                NSLog("[OTPBridge] Failed to send clipboard: \(error)")
            }
        }
    }

    func restoreSharedSecret() {
        guard let pairedDevice = pairingManager.getPairedDevice() else { return }
        do {
            sharedSecret = try cryptoManager.deriveSharedSecret(theirPublicKeyData: pairedDevice.publicKey)
        } catch {
            NSLog("[OTPBridge] Failed to restore shared secret: \(error)")
        }
    }
}
