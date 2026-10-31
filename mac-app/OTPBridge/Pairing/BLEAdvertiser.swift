import Foundation
import CoreBluetooth
import Network

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
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newIP = self.currentIP()
            guard newIP != self.lastAdvertisedIP else { return }
            NSLog("[BLEAdvertiser] Wi-Fi path changed, new IP: \(newIP ?? "none") (was: \(self.lastAdvertisedIP ?? "none"))")
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

        let ip = currentIP() ?? "0.0.0.0"
        let payload = signedDiscovery(ip: ip)
        let ipData = payload.data(using: .utf8) ?? Data()

        let ipChar = CBMutableCharacteristic(
            type: BLEAdvertiser.ipCharUUID,
            properties: [.read],
            value: ipData,
            permissions: [.readable]
        )
        self.ipCharacteristic = ipChar

        let service = CBMutableService(type: BLEAdvertiser.serviceUUID, primary: true)
        service.characteristics = [ipChar]
        manager.removeAllServices()
        manager.add(service)
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEAdvertiser.serviceUUID],
            CBAdvertisementDataLocalNameKey: "Bridge"
        ])
        lastAdvertisedIP = ip
        NSLog("[BLEAdvertiser] Advertising on \(ip)")
    }

    private func signedDiscovery(ip: String) -> String {
        let id = CryptoManager.shared.getDeviceId()
        if let secret = PairingManager.shared.getPairedDevice()?.sharedSecret {
            return SessionCrypto.signedBeacon(ip: ip, port: 8420, deviceId: id, secret: secret)
        }
        return "OTPBRIDGE \(ip) 8420 \(id) \(String(repeating: "0", count: 64))"
    }

    private func currentIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: iface.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                            &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                address = String(cString: host)
            }
        }
        return address
    }
}

extension BLEAdvertiser: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn && pendingStart {
            startAdvertising()
        } else if peripheral.state == .poweredOn {
            startAdvertising()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { NSLog("[BLEAdvertiser] Add service error: \(error)") }
    }
}
