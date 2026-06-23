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
    }

    private func handleNewConnection(_ newConnection: NWConnection) {
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

    private func readLoop(connection: NWConnection) {
        readFourBytes(connection: connection) { [weak self] lengthData in
            guard let self = self, let ld = lengthData else {
                NSLog("[OTPBridge] Connection closed or error reading length")
                self?.isConnected = false
                self?.connection = nil
                return
            }
            let length = Int(ld[0]) << 24 | Int(ld[1]) << 16 | Int(ld[2]) << 8 | Int(ld[3])
            guard length > 0, length < 1_000_000 else {
                NSLog("[OTPBridge] Invalid length, disconnecting")
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
                let decrypted = try cryptoManager.decrypt(ciphertext: data, key: secret)
                let json = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any]
                guard let type = json?["type"] as? String else { return }

                if type == "otp" {
                    let sender = json?["sender"] as? String ?? "Unknown"
                    let otp = json?["otp"] as? String ?? ""
                    let company = json?["company"] as? String
                    let timestamp = json?["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
                    NSLog("[OTPBridge] OTP received: \(otp) from \(company ?? sender)")
                    DispatchQueue.main.async {
                        self.onOTPReceived?(sender, otp, company, timestamp)
                    }
                }
            } catch {
                // Decryption failed with stored secret — Android re-paired or cleared data.
                // Reset and try treating this as a new handshake.
                NSLog("[OTPBridge] Decryption failed (\(error)), resetting and attempting re-handshake")
                sharedSecret = nil
                isConnected = false
                handleHandshake(data)
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

            try pairingManager.completePairing(deviceId: deviceId, publicKeyData: publicKeyData)
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
            }
            NSLog("[OTPBridge] Connection established!")
        } catch {
            NSLog("[OTPBridge] Handshake failed: \(error)")
        }
    }

    func sendBinary(_ data: Data) {
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

    func restoreSharedSecret() {
        guard let pairedDevice = pairingManager.getPairedDevice() else { return }
        do {
            sharedSecret = try cryptoManager.deriveSharedSecret(theirPublicKeyData: pairedDevice.publicKey)
        } catch {
            NSLog("[OTPBridge] Failed to restore shared secret: \(error)")
        }
    }
}
