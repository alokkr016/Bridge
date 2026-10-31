import Foundation
import CoreBluetooth
import Network

/// Best LAN IPv4 for QR pairing and BLE discovery.
/// Prefers en0, then any other en*, skips loopback and (unless nothing else) link-local.
enum LocalAddress {
    static func ipv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var en0: String?
        var en0LinkLocal: String?
        var other: String?
        var otherLinkLocal: String?

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: iface.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("127.") { continue }
            let linkLocal = ip.hasPrefix("169.254.")
            if name == "en0" {
                if linkLocal { en0LinkLocal = ip } else { en0 = ip }
            } else {
                if linkLocal { otherLinkLocal = ip } else if other == nil { other = ip }
            }
        }
        return en0 ?? other ?? en0LinkLocal ?? otherLinkLocal
    }

    /// Compact BLE local name: `B` + 8 hex digits of IPv4 + 8 hex of device id.
    /// Example: 192.168.0.108 / 3A8D8464-… → BC0A8006C3A8D8464
    static func bleName(for ip: String, deviceId: String? = nil) -> String {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return "Bridge" }
        var name = "B" + parts.map { String(format: "%02X", $0) }.joined()
        if let id = deviceId {
            let hex = id.replacingOccurrences(of: "-", with: "").prefix(8)
            if hex.count == 8 { name += hex.uppercased() }
        }
        return name
    }
}

/// Advertises the Mac's current IP over BLE so the Android app can find it
/// without needing the user to re-pair when the IP changes.
class BLEAdvertiser: NSObject {

    static let shared = BLEAdvertiser()

    // Same UUID on both sides — must match BLEScanner on Android
    static let serviceUUID = CBUUID(string: "F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFEFF")
    static let ipCharUUID  = CBUUID(string: "F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFE01")

    private var manager: CBPeripheralManager?
    private var ipCharacteristic: CBMutableCharacteristic?
    private var pendingStart = false

    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "io.github.alokkr016.otpbridge.ble.pathmonitor")
    private var lastAdvertisedIP: String?

    private override init() {}

    func start() {
        guard manager == nil else { return }
        manager = CBPeripheralManager(delegate: self, queue: .global())
        startPathMonitor()
    }

    func stop() {
        manager?.stopAdvertising()
        manager = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        lastAdvertisedIP = nil
    }

    private func startPathMonitor() {
        // All interfaces — Ethernet Macs never fire a .wifi-only monitor.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            let newIP = LocalAddress.ipv4()
            guard newIP != self.lastAdvertisedIP else { return }
            NSLog("[BLEAdvertiser] Path changed, new IP: \(newIP ?? "none") (was: \(self.lastAdvertisedIP ?? "none"))")
            self.startAdvertising()
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    private func startAdvertising() {
        guard let manager, manager.state == .poweredOn else {
            pendingStart = true
            return
        }
        pendingStart = false

        // value: nil → dynamic characteristic; we fill it on each read.
        let ipChar = CBMutableCharacteristic(
            type: BLEAdvertiser.ipCharUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        self.ipCharacteristic = ipChar

        let service = CBMutableService(type: BLEAdvertiser.serviceUUID, primary: true)
        service.characteristics = [ipChar]
        manager.removeAllServices()
        manager.add(service)
        // startAdvertising is called from didAdd — advertising before the
        // service is registered is silently dropped on macOS.
    }

    fileprivate func beginAdvertising() {
        guard let manager, manager.state == .poweredOn else { return }
        let ip = LocalAddress.ipv4() ?? "0.0.0.0"
        let name = LocalAddress.bleName(for: ip, deviceId: CryptoManager.shared.getDeviceId())
        manager.stopAdvertising()
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: name,
            CBAdvertisementDataServiceUUIDsKey: [BLEAdvertiser.serviceUUID]
        ])
        lastAdvertisedIP = ip
        NSLog("[BLEAdvertiser] Advertising \(name) (\(ip))")
    }

    fileprivate func signedDiscovery(ip: String) -> String {
        Self.signedDiscoveryPayload(ip: ip)
    }

    fileprivate static func signedDiscoveryPayload(ip: String) -> String {
        let id = CryptoManager.shared.getDeviceId()
        if let secret = PairingManager.shared.getPairedDevice()?.sharedSecret {
            return SessionCrypto.signedBeacon(ip: ip, port: 8420, deviceId: id, secret: secret)
        }
        return "OTPBRIDGE \(ip) 8420 \(id) \(String(repeating: "0", count: 64))"
    }
}

extension BLEAdvertiser: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            startAdvertising()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            NSLog("[BLEAdvertiser] Add service error: \(error)")
            return
        }
        beginAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            NSLog("[BLEAdvertiser] startAdvertising error: \(error)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BLEAdvertiser.ipCharUUID else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        let ip = LocalAddress.ipv4() ?? "0.0.0.0"
        let payload = signedDiscovery(ip: ip)
        let data = Data(payload.utf8)
        guard request.offset <= data.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }
}

/// Broadcasts the Mac's LAN IP over UDP so the phone can recover after DHCP
/// without depending on BLE. Handshake still authenticates the TCP session.
final class LanBeacon {
    static let shared = LanBeacon()
    static let port: UInt16 = 8421

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "io.github.alokkr016.otpbridge.lanbeacon")

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 2.0)
        t.setEventHandler { [weak self] in self?.send() }
        t.resume()
        timer = t
        NSLog("[LanBeacon] started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func send() {
        guard let ip = LocalAddress.ipv4() else { return }
        let payload = BLEAdvertiser.signedDiscoveryPayload(ip: ip)
        guard let data = payload.data(using: .utf8) else { return }
        // Global broadcast + /24 directed broadcast (some APs drop 255.255.255.255).
        send(data, to: "255.255.255.255")
        if let slash24 = directedBroadcast(for: ip) {
            send(data, to: slash24)
        }
    }

    private func directedBroadcast(for ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).255"
    }

    private func send(_ data: Data, to host: String) {
        var hints = addrinfo(
            ai_flags: AI_NUMERICHOST | AI_NUMERICSERV,
            ai_family: AF_INET,
            ai_socktype: SOCK_DGRAM,
            ai_protocol: IPPROTO_UDP,
            ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "\(LanBeacon.port)", &hints, &info) == 0, let info else { return }
        defer { freeaddrinfo(info) }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = sendto(fd, base, data.count, 0, info.pointee.ai_addr, info.pointee.ai_addrlen)
        }
    }
}
