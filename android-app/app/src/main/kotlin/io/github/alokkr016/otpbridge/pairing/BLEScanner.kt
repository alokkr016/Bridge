package io.github.alokkr016.otpbridge.pairing

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID

/**
 * Scans for the Mac's BLE advertisement to discover its current IP address.
 * When found, updates the stored IP in KeyPairStore and triggers a reconnect.
 * This lets the Android app reconnect automatically when the Mac's IP changes
 * (e.g. different Wi-Fi network) without requiring a full re-pair.
 */
class BLEScanner(private val context: Context) {

    companion object {
        private const val TAG = "BLEScanner"
        val SERVICE_UUID: UUID = UUID.fromString("F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFEFF")
        val IP_CHAR_UUID: UUID = UUID.fromString("F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFE01")
        private const val SCAN_PERIOD_MS = 10_000L
    }

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val scanner get() = bluetoothManager.adapter?.bluetoothLeScanner
    private val keyPairStore = io.github.alokkr016.otpbridge.crypto.KeyPairStore(context)
    private val handler = Handler(Looper.getMainLooper())
    private var scanning = false
    private var gatt: BluetoothGatt? = null

    var onIPDiscovered: ((String) -> Unit)? = null

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            Log.d(TAG, "Found BLE device: ${result.device.address}")
            stopScan()
            connectToDevice(result.device)
        }
        override fun onScanFailed(errorCode: Int) {
            Log.w(TAG, "Scan failed: $errorCode")
            scanning = false
        }
    }

    fun startScan() {
        if (scanning) return
        val leScanner = scanner ?: run {
            Log.w(TAG, "BLE not available")
            return
        }
        scanning = true
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            leScanner.startScan(listOf(filter), settings, scanCallback)
        } catch (e: SecurityException) {
            Log.w(TAG, "BLE scan permission denied: ${e.message}")
            scanning = false
            return
        }
        Log.d(TAG, "BLE scan started")
        handler.postDelayed({ stopScan() }, SCAN_PERIOD_MS)
    }

    fun stopScan() {
        if (!scanning) return
        scanning = false
        scanner?.stopScan(scanCallback)
        Log.d(TAG, "BLE scan stopped")
    }

    private fun connectToDevice(device: BluetoothDevice) {
        gatt = device.connectGatt(context, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    Log.d(TAG, "GATT connected — discovering services")
                    gatt.discoverServices()
                } else {
                    Log.d(TAG, "GATT disconnected")
                    gatt.close()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                val char = gatt.getService(SERVICE_UUID)
                    ?.getCharacteristic(IP_CHAR_UUID)
                if (char != null) {
                    gatt.readCharacteristic(char)
                } else {
                    Log.w(TAG, "IP characteristic not found")
                    gatt.disconnect()
                }
            }

            @Deprecated("Deprecated in API 33")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS && characteristic.uuid == IP_CHAR_UUID) {
                    acceptSignedDiscovery(characteristic.value?.toString(Charsets.UTF_8).orEmpty())
                    gatt.disconnect()
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS && characteristic.uuid == IP_CHAR_UUID) {
                    acceptSignedDiscovery(value.toString(Charsets.UTF_8))
                    gatt.disconnect()
                }
            }
        })
    }

    private fun acceptSignedDiscovery(text: String) {
        val parts = text.trim().split(Regex("\\s+"))
        if (parts.size != 5 || parts[0] != "OTPBRIDGE") {
            Log.w(TAG, "Rejected discovery without a signature")
            return
        }
        val ip = parts[1]
        val port = parts[2].toIntOrNull() ?: return
        val deviceId = parts[3]
        val mac = parts[4]
        if (mac.length != 64) return
        val device = keyPairStore.getPairedDevice() ?: return
        if (!device.deviceId.equals(deviceId, ignoreCase = true)) return
        val expected = io.github.alokkr016.otpbridge.crypto.SessionCrypto.beaconMac(
            device.sharedSecret, ip, port, deviceId
        )
        if (!io.github.alokkr016.otpbridge.crypto.SessionCrypto.constantTimeEquals(expected, mac)) {
            Log.w(TAG, "Rejected forged discovery")
            return
        }
        if (device.ip == ip) return
        keyPairStore.savePairedDevice(
            deviceId = device.deviceId,
            publicKey = device.publicKey,
            ip = ip,
            port = port,
            sharedSecret = device.sharedSecret
        )
        handler.post { onIPDiscovered?.invoke(ip) }
    }
}
