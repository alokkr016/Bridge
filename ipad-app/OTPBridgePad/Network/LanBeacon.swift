import Foundation

/// Broadcasts this iPad's LAN IP over UDP so the phone can find it again after
/// DHCP moves it, without the user re-pairing. The TCP handshake still
/// authenticates the session, so this is only a discovery hint.
///
/// Battery note: the Mac beacons every 2s forever, which is fine when plugged in.
/// Here it is deliberately demand-driven instead —
///
///  * Android only listens on UDP 8421 while it is actively hunting for a peer
///    IP (BLEScanner's `watching` flag), so a constant beacon would be shouting
///    at nobody the vast majority of the time.
///  * We beacon only while foreground AND not connected, i.e. exactly the window
///    where the phone might be searching.
///  * It stops the moment a phone connects, and on backgrounding.
///  * A 3s interval with a hard cap means a bounded burst, not an endless timer.
///
/// Net effect: a few dozen tiny UDP packets after a network change, then silence.
final class LanBeacon {

    static let shared = LanBeacon()
    static let port: UInt16 = 8421

    /// Long enough for the phone to notice a dropped socket and start listening.
    private static let interval: TimeInterval = 3.0
    /// Stop after this long so a forgotten beacon can't run all day.
    private static let maxDuration: TimeInterval = 120.0

    private var timer: DispatchSourceTimer?
    private var startedAt: Date?
    private let queue = DispatchQueue(label: "io.github.alokkr016.bridge.ipad.lanbeacon")

    private init() {}

    var isRunning: Bool { timer != nil }

    /// Starts a bounded beacon burst. Safe to call repeatedly.
    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.startedAt = Date()
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now(), repeating: Self.interval)
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            self.timer = t
            NSLog("[BridgePad/LanBeacon] started")
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.timer != nil else { return }
            self.timer?.cancel()
            self.timer = nil
            self.startedAt = nil
            NSLog("[BridgePad/LanBeacon] stopped")
        }
    }

    private func tick() {
        if let startedAt, Date().timeIntervalSince(startedAt) > Self.maxDuration {
            NSLog("[BridgePad/LanBeacon] max duration reached — stopping")
            timer?.cancel()
            timer = nil
            self.startedAt = nil
            return
        }
        // A phone is already connected; nothing is searching for us.
        if TCPServer.shared.isConnected {
            NSLog("[BridgePad/LanBeacon] peer connected — stopping")
            timer?.cancel()
            timer = nil
            startedAt = nil
            return
        }
        send()
    }

    private func send() {
        guard let ip = LocalAddress.ipv4() else { return }
        let payload = "OTPBRIDGE \(ip) 8420 \(CryptoManager.shared.getDeviceId())"
        guard let data = payload.data(using: .utf8) else { return }
        // Global broadcast plus the /24 directed broadcast — some APs drop
        // 255.255.255.255 but forward the directed form.
        sendDatagram(data, to: "255.255.255.255")
        if let slash24 = directedBroadcast(for: ip) {
            sendDatagram(data, to: slash24)
        }
    }

    private func directedBroadcast(for ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).255"
    }

    private func sendDatagram(_ data: Data, to host: String) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        _ = data.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
