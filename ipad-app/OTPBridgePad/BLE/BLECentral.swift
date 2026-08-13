import Foundation
import CoreBluetooth

/// BLE central that subscribes to the phone's OTP characteristic.
///
/// This is the *background* path. iPadOS suspends NWListener when Bridge leaves
/// the foreground, but a `bluetooth-central` app with a restore identifier is
/// woken (or relaunched) by the system when a subscribed characteristic notifies.
/// We get roughly 10 seconds — just enough to decrypt, copy, notify, and store.
///
/// The iPad is deliberately the central, not a peripheral: backgrounded iOS
/// advertisements go into an overflow area Android frequently cannot see.
///
/// Note: a user force-quitting Bridge in the app switcher stops relaunch. Apple
/// does not allow working around that, and we don't try.
final class BLECentral: NSObject {

    static let shared = BLECentral()

    static let serviceUUID = CBUUID(string: "F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFEFF")
    static let otpCharUUID = CBUUID(string: "F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFE02")
    private static let restoreIdentifier = "io.github.alokkr016.bridge.ipad.central"

    /// Called with the decrypted JSON payload of an OTP notification.
    var onOTPPayload: (([String: Any]) -> Void)?

    private var central: CBCentralManager?
    private var phone: CBPeripheral?
    private let cryptoManager = CryptoManager.shared

    private override init() {
        super.init()
    }

    func start() {
        guard central == nil else {
            scanIfPossible()
            return
        }
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    private func scanIfPossible() {
        guard let central, central.state == .poweredOn else { return }
        if let phone, phone.state == .connected { return }
        // Scanning by service UUID is required for background scanning to work.
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
        NSLog("[BridgePad/BLE] Scanning for phone")
    }

    private func handle(payload data: Data) {
        guard let secret = PairingManager.shared.getPairedDevice()?.sharedSecret else {
            NSLog("[BridgePad/BLE] Notify received but not paired")
            return
        }
        do {
            let decrypted = try cryptoManager.decrypt(ciphertext: data, key: secret)
            guard let json = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else { return }
            DispatchQueue.main.async { self.onOTPPayload?(json) }
        } catch {
            NSLog("[BridgePad/BLE] Decrypt failed: \(error)")
        }
    }
}

extension BLECentral: CBCentralManagerDelegate {

    /// Called before didUpdateState when the system relaunched us for BLE.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored = peripherals.first {
            NSLog("[BridgePad/BLE] Restored peripheral \(restored.identifier)")
            phone = restored
            restored.delegate = self
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            NSLog("[BridgePad/BLE] Powered on")
            if let phone, phone.state != .connected {
                central.connect(phone, options: nil)
            } else {
                scanIfPossible()
            }
        case .unauthorized:
            NSLog("[BridgePad/BLE] Bluetooth unauthorized")
        default:
            NSLog("[BridgePad/BLE] State: \(central.state.rawValue)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        NSLog("[BridgePad/BLE] Discovered \(peripheral.name ?? "unknown")")
        central.stopScan()
        phone = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        NSLog("[BridgePad/BLE] Connected")
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        NSLog("[BridgePad/BLE] Disconnected — reconnecting")
        // Reconnect immediately; iOS holds the pending connect while suspended.
        central.connect(peripheral, options: nil)
    }
}

extension BLECentral: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.otpCharUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let char = service.characteristics?.first(where: { $0.uuid == Self.otpCharUUID }) else { return }
        peripheral.setNotifyValue(true, for: char)
        NSLog("[BridgePad/BLE] Subscribed to OTP characteristic")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.otpCharUUID, let data = characteristic.value else { return }
        NSLog("[BridgePad/BLE] OTP notify (\(data.count) bytes)")
        handle(payload: data)
    }
}
