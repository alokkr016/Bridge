import Foundation
import Network
import CryptoKit

/// TCP server on port 8420, wire-compatible with the Mac's WebSocketServer so the
/// existing Android WebSocketClient can connect to the iPad unchanged.
///
/// Framing: [4-byte big-endian length][payload]; length 0 is a keepalive ping.
/// Handshake is cleartext JSON, everything after is AES-256-GCM.
///
/// iPadOS suspends NWListener in the background — that is expected. BLECentral is
/// the background path; this is the foreground/Split-View path.
final class TCPServer {

    static let shared = TCPServer()

    private var listener: NWListener?
    private var connection: NWConnection?
    private var sharedSecret: Data?
    private let cryptoManager = CryptoManager.shared
    private let pairingManager = PairingManager.shared

    var onOTPReceived: ((String, String, String?, TimeInterval) -> Void)?
    var onClipboardReceived: ((String) -> Void)?
    var onHandshakeReceived: ((String, Data) -> Void)?
    var onNewPairingCompleted: ((String, Data) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    /// Posted on connect/disconnect. A Notification rather than only the
    /// single-assignment `onConnectionChanged` closure, so several observers
    /// (HomeView and LanBeacon) can react without overwriting each other.
    static let connectionChanged = Notification.Name("bridgePadConnectionChanged")

    private(set) var isConnected = false {
        didSet {
            guard oldValue != isConnected else { return }
            let connected = isConnected
            DispatchQueue.main.async {
                self.onConnectionChanged?(connected)
                NotificationCenter.default.post(
                    name: Self.connectionChanged,
                    object: nil,
                    userInfo: ["connected": connected]
                )
            }
        }
    }

    private init() {}

    /// Re-derives the shared secret from the stored pairing so a reconnect after
    /// relaunch doesn't require the user to pair again.
    func restoreSharedSecret() {
        guard let device = pairingManager.getPairedDevice() else { return }
        sharedSecret = device.sharedSecret
        NSLog("[BridgePad] Restored shared secret for \(device.deviceId)")
    }

    func start() {
        if let existing = listener {
            switch existing.state {
            case .ready, .setup, .waiting:
                NSLog("[BridgePad] Server already listening (\(existing.state))")
                return
            default:
                break
            }
        }
        // Replace only the listener. Cancelling a live connection here is what
        // left the UI Offline after the user closed and reopened the app:
        // scenePhase .active called start() → stop() → handshake torn down
        // while the phone still thought it was connected.
        listener?.cancel()
        listener = nil

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: 8420)!)

            listener?.newConnectionHandler = { [weak self] newConnection in
                NSLog("[BridgePad] New TCP connection")
                self?.handleNewConnection(newConnection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    NSLog("[BridgePad] Listening on 8420")
                case .failed(let error):
                    NSLog("[BridgePad] Listener failed: \(error) — restarting")
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
            NSLog("[BridgePad] Failed to start server: \(error)")
        }
    }

    /// - Parameter clearSecret: false when merely restarting the socket, so a
    ///   backgrounded/foregrounded app keeps its pairing.
    func stop(clearSecret: Bool = true) {
        listener?.cancel()
        connection?.cancel()
        listener = nil
        connection = nil
        if clearSecret { sharedSecret = nil }
        isConnected = false
    }

    private func handleNewConnection(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        // A new socket must re-handshake; keep the stored secret as a fallback
        // only after the handshake replaces it.
        isConnected = false
        newConnection.start(queue: .global())
        readLoop(connection: newConnection)
    }

    /// Only the current connection may flip state — a cancelled predecessor's
    /// read loop finishing after a reconnect would otherwise report Offline
    /// while the new socket is healthy. (Same fix as the Mac app.)
    private func markDisconnected(ifCurrent candidate: NWConnection) {
        guard connection === candidate else {
            NSLog("[BridgePad] Ignoring close from stale connection")
            return
        }
        isConnected = false
        connection = nil
    }

    private func readLoop(connection: NWConnection) {
        readExactly(connection: connection, count: 4) { [weak self] lengthData in
            guard let self = self, let ld = lengthData else {
                self?.markDisconnected(ifCurrent: connection)
                return
            }
            let length = Int(ld[0]) << 24 | Int(ld[1]) << 16 | Int(ld[2]) << 8 | Int(ld[3])
            if length == 0 {
                var pong = Data(count: 4)
                connection.send(content: pong, completion: .contentProcessed { _ in })
                self.readLoop(connection: connection)
                return
            }
            guard length > 0, length < 1_000_000 else {
                NSLog("[BridgePad] Invalid frame length \(length)")
                self.markDisconnected(ifCurrent: connection)
                return
            }
            self.readExactly(connection: connection, count: length) { payload in
                guard let data = payload else {
                    self.markDisconnected(ifCurrent: connection)
                    return
                }
                self.processMessage(data)
                self.readLoop(connection: connection)
            }
        }
    }

    private func readExactly(connection: NWConnection, count: Int, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, isComplete, error in
            if let error {
                NSLog("[BridgePad] read error: \(error)")
                completion(nil)
                return
            }
            // isComplete can arrive alongside the final bytes — don't drop them.
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
        guard let secret = sharedSecret else {
            handleHandshake(data)
            return
        }
        do {
            let decrypted = try cryptoManager.decrypt(ciphertext: data, key: secret)
            guard let json = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any],
                  let type = json["type"] as? String else { return }
            route(type: type, json: json)
        } catch {
            // Stored secret no longer matches — the phone re-paired or cleared
            // data. Reset and try treating this frame as a fresh handshake.
            NSLog("[BridgePad] Decrypt failed (\(error)) — attempting re-handshake")
            sharedSecret = nil
            isConnected = false
            handleHandshake(data)
        }
    }

    private func route(type: String, json: [String: Any]) {
        switch type {
        case "otp":
            let sender = json["sender"] as? String ?? "Unknown"
            let otp = json["otp"] as? String ?? ""
            let company = json["company"] as? String
            let rawTs = json["timestamp"] as? TimeInterval ?? (Date().timeIntervalSince1970 * 1000)
            let timestamp = rawTs > 1_000_000_000_000 ? rawTs / 1000.0 : rawTs
            // Never log the code itself — the log is readable by other local
            // processes and persists in diagnostics.
            NSLog("[BridgePad] OTP received (\(otp.count) digits) from \(company ?? sender)")
            DispatchQueue.main.async {
                self.onOTPReceived?(sender, otp, company, timestamp)
            }
        case "clipboard":
            if let text = json["text"] as? String {
                DispatchQueue.main.async { self.onClipboardReceived?(text) }
            }
        case "call":
            // Call UI is intentionally out of scope on iPad.
            break
        default:
            NSLog("[BridgePad] Ignoring message type: \(type)")
        }
    }

    private func handleHandshake(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String, type == "handshake" else {
                NSLog("[BridgePad] Not a handshake")
                return
            }
            guard let deviceId = json["device_id"] as? String,
                  let publicKeyB64 = json["public_key"] as? String,
                  let publicKeyData = Data(base64Encoded: publicKeyB64) else {
                NSLog("[BridgePad] Handshake missing fields")
                return
            }

            // Only the paired phone, or a device the user is actively pairing,
            // may establish a session. Without this any host on the LAN could
            // hand us a key and start receiving OTPs.
            let token = json["token"] as? String
            guard pairingManager.shouldAcceptHandshake(publicKeyData: publicKeyData, token: token) else {
                NSLog("[BridgePad] Handshake refused — closing connection")
                connection?.cancel()
                connection = nil
                isConnected = false
                return
            }

            let scannedQR = pairingManager.matchesPairingToken(token)
            _ = try pairingManager.completePairing(deviceId: deviceId, publicKeyData: publicKeyData)
            if scannedQR {
                pairingManager.consumePairingToken()
            }
            sharedSecret = try cryptoManager.deriveSharedSecret(theirPublicKeyData: publicKeyData)

            let response: [String: Any] = [
                "type": "handshake_ack",
                "device_id": cryptoManager.getDeviceId(),
                "public_key": cryptoManager.getPublicKeyData()?.base64EncodedString() ?? ""
            ]
            sendBinary(try JSONSerialization.data(withJSONObject: response))
            isConnected = true
            NSLog("[BridgePad] Handshake complete with \(deviceId)")

            DispatchQueue.main.async {
                self.onHandshakeReceived?(deviceId, publicKeyData)
                if scannedQR {
                    self.onNewPairingCompleted?(deviceId, publicKeyData)
                }
            }
        } catch {
            NSLog("[BridgePad] Handshake failed: \(error)")
        }
    }

    /// Frames and sends raw bytes: [4-byte big-endian length][payload].
    func sendBinary(_ data: Data) {
        guard let conn = connection else { return }
        var framed = Data()
        let len = UInt32(data.count)
        framed.append(UInt8((len >> 24) & 0xFF))
        framed.append(UInt8((len >> 16) & 0xFF))
        framed.append(UInt8((len >> 8) & 0xFF))
        framed.append(UInt8(len & 0xFF))
        framed.append(data)
        conn.send(content: framed, completion: .contentProcessed { error in
            if let error { NSLog("[BridgePad] send error: \(error)") }
        })
    }

    /// Sends the iPad's clipboard to the phone (encrypted), matching the Mac.
    func sendClipboard(_ text: String) {
        guard let secret = sharedSecret else { return }
        do {
            let payload = try JSONSerialization.data(withJSONObject: ["type": "clipboard", "text": text])
            sendBinary(try cryptoManager.encrypt(plaintext: payload, key: secret))
        } catch {
            NSLog("[BridgePad] Failed to send clipboard: \(error)")
        }
    }
}
