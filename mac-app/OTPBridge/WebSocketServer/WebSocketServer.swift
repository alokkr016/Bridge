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
    private let sendQueue = DispatchQueue(label: "io.github.alokkr016.otpbridge.send")

    var onOTPReceived: ((String, String, String?, TimeInterval) -> Void)?

    var isConnected = false {
        didSet {
            DispatchQueue.main.async {
                self.onConnectionChanged?(self.isConnected)
            }
        }
    }

    var onConnectionChanged: ((Bool) -> Void)?
    var onHandshakeReceived: ((String, Data) -> Void)?

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

    private func readLoop(connection: NWConnection) {
        readFourBytes(connection: connection) { [weak self] lengthData in
            guard let self = self, let ld = lengthData else {
                NSLog("[OTPBridge] Connection closed or error reading length")
                self?.isConnected = false
                self?.connection = nil
                return
            }
            let length = Int(ld[0]) << 24 | Int(ld[1]) << 16 | Int(ld[2]) << 8 | Int(ld[3])
            // length == 0 is a keepalive ping — just loop back and read the next frame
            if length == 0 { self.readLoop(connection: connection); return }
            guard length < 1_000_000 else {
                NSLog("[OTPBridge] Invalid length \(length), disconnecting")
                self.isConnected = false
                self.connection = nil
                return
            }
            self.readBytes(connection: connection, count: length) { payloadData in
                guard let data = payloadData else {
                    NSLog("[OTPBridge] Error reading payload")
                    self.isConnected = false
                    self.connection = nil
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
            if isComplete { completion(nil); return }
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
            if isComplete { completion(nil); return }
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
                    let sender = json?["sender"] as? String ?? "Unknown"
                    let otp = json?["otp"] as? String ?? ""
                    let company = json?["company"] as? String
                    let rawTs = json?["timestamp"] as? TimeInterval ?? (Date().timeIntervalSince1970 * 1000)
                    let timestamp = rawTs > 1_000_000_000_000 ? rawTs / 1000.0 : rawTs
                    NSLog("[OTPBridge] OTP received, length=\(otp.count)")
                    DispatchQueue.main.async {
                        self.onOTPReceived?(sender, otp, company, timestamp)
                    }
                } else if type == "clipboard" {
                    if let text = json?["text"] as? String {
                        NSLog("[OTPBridge] Clipboard received from Android")
                        DispatchQueue.main.async {
                            ClipboardManager.shared.receiveFromAndroid(text)
                        }
                    }
                }
            } catch {
                NSLog("[OTPBridge] Decryption failed (\(error)), closing connection")
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
            let token = json?["token"] as? String
            NSLog("[OTPBridge] Handshake from \(deviceId), keyLen=\(publicKeyData.count)")
            guard pairingManager.shouldAcceptHandshake(publicKeyData: publicKeyData, token: token) else {
                NSLog("[OTPBridge] REJECTED handshake")
                connection?.cancel()
                connection = nil
                return
            }

            try pairingManager.completePairing(deviceId: deviceId, publicKeyData: publicKeyData)
            pairingManager.consumePairingToken()
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
                ClipboardManager.shared.startSyncing()
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

    func sendClipboard(_ text: String) {
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
