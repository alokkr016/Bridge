package io.github.alokkr016.otpbridge.pairing

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.util.UUID

/**
 * Finds the paired Mac after its LAN IP changes.
 *
 * Primary path: the Mac encodes IPv4 in its BLE local name (`B` + 8 hex digits).
 * That avoids a GATT round-trip and avoids Android's service-UUID scan filter,
 * which silently misses macOS advertisements (128-bit UUID lives in the overflow
 * / scan-response packet).
 *
 * Fallback: if the advert looks like Bridge but has no encoded name, connect
 * GATT and read the IP characteristic.
 */
class BLEScanner(private val context: Context) {

    companion object {
        private const val TAG = "BLEScanner"
        val SERVICE_UUID: UUID = UUID.fromString("F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFEFF")
        val IP_CHAR_UUID: UUID = UUID.fromString("F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFE01")
        private const val SCAN_PERIOD_MS = 12_000L
        private const val SCAN_PAUSE_MS = 15_000L
        private const val GATT_TIMEOUT_MS = 8_000L
        private const val UDP_BEACON_PORT = 8421
        private val ENCODED_NAME = Regex("^B[0-9A-Fa-f]{8}([0-9A-Fa-f]{8})?$")
        private val IPV4 = Regex("^((25[0-5]|2[0-4]\\d|[01]?\\d\\d?)\\.){3}(25[0-5]|2[0-4]\\d|[01]?\\d\\d?)$")
        private val DEVICE_ID = Regex("^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$")

        data class Discovery(val ip: String, val deviceId: String?)

        fun decodeBleName(name: String): Discovery? {
            if (!ENCODED_NAME.matches(name)) return null
            val body = name.substring(1)
            val ipBytes = body.substring(0, 8).chunked(2).map { it.toInt(16) }
            val ip = ipBytes.joinToString(".")
            if (ip == "0.0.0.0" || !IPV4.matches(ip)) return null
            val hint = if (body.length >= 16) body.substring(8, 16) else null
            return Discovery(ip, hint)
        }

        fun parseBeacon(text: String): Discovery? {
            val parts = text.trim().split(Regex("\\s+"))
            if (parts.size < 3 || parts[0] != "OTPBRIDGE" || !IPV4.matches(parts[1])) return null
            val id = parts.getOrNull(3)?.takeIf { it.isNotBlank() }
            return Discovery(parts[1], id)
        }
    }

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val scanner get() = bluetoothManager.adapter?.bluetoothLeScanner
    private val keyPairStore = io.github.alokkr016.otpbridge.crypto.KeyPairStore(context)
    private val handler = Handler(Looper.getMainLooper())
    private var scanning = false
    private var watching = false
    private var gatt: BluetoothGatt? = null
    private var udpSocket: DatagramSocket? = null
    private var udpThread: Thread? = null
    private val seenAds = LinkedHashSet<String>()

    var onIPDiscovered: ((String) -> Unit)? = null

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            handleScanResult(result)
        }
        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach(::handleScanResult)
        }
        override fun onScanFailed(errorCode: Int) {
            Log.w(TAG, "Scan failed: $errorCode")
            scanning = false
            scheduleNextScan()
        }
    }

    /** Keep scanning in short bursts until [stopWatching] or an IP is found. */
    fun startWatching() {
        if (watching) {
            Log.d(TAG, "Already watching for Mac IP")
            return
        }
        watching = true
        Log.d(TAG, "Start watching for Mac IP (UDP + BLE)")
        startUdpListen()
        startScan()
    }

    fun stopWatching() {
        watching = false
        handler.removeCallbacksAndMessages(null)
        stopUdpListen()
        stopScan()
        closeGatt()
        Log.d(TAG, "Stopped watching")
    }

    fun startScan() {
        if (scanning) return
        val leScanner = scanner ?: run {
            Log.w(TAG, "BLE not available")
            scheduleNextScan()
            return
        }
        scanning = true
        // No service-UUID filter. macOS puts the 128-bit UUID in the overflow
        // packet; a filter on it makes the Mac invisible.
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            leScanner.startScan(emptyList(), settings, scanCallback)
        } catch (e: SecurityException) {
            Log.w(TAG, "BLE scan permission denied: ${e.message}")
            scanning = false
            return
        }
        Log.d(TAG, "BLE scan started")
        handler.postDelayed({
            stopScan()
            scheduleNextScan()
        }, SCAN_PERIOD_MS)
    }

    fun stopScan() {
        if (!scanning) return
        scanning = false
        try {
            scanner?.stopScan(scanCallback)
        } catch (_: SecurityException) {
        }
        Log.d(TAG, "BLE scan stopped")
    }

    private fun scheduleNextScan() {
        if (!watching || scanning || gatt != null) return
        handler.postDelayed({
            if (watching && !scanning) startScan()
        }, SCAN_PAUSE_MS)
    }

    private fun handleScanResult(result: ScanResult) {
        val record = result.scanRecord
        val deviceName = try { result.device.name } catch (_: SecurityException) { null }
        val addr = result.device.address
        if (seenAds.add(addr) && seenAds.size <= 40) {
            Log.d(TAG, "BLE seen $addr name=${record?.deviceName ?: deviceName} uuids=${record?.serviceUuids}")
        }
        val names = listOfNotNull(record?.deviceName, deviceName)
        for (name in names) {
            val found = decodeBleName(name)
            if (found != null) {
                Log.d(TAG, "Peer from BLE name $name → ${found.ip} id=${found.deviceId}")
                stopScan()
                applyIP(found.ip, found.deviceId)
                return
            }
        }
        val looksLikeBridge = names.any { it.equals("Bridge", ignoreCase = true) } ||
            record?.serviceUuids?.any { it.uuid == SERVICE_UUID } == true
        if (looksLikeBridge && gatt == null) {
            Log.d(TAG, "Bridge advert without encoded IP — GATT fallback")
            stopScan()
            connectToDevice(result.device)
        }
    }

    private fun connectToDevice(device: BluetoothDevice) {
        closeGatt()
        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    Log.d(TAG, "GATT connected — discovering services")
                    gatt.discoverServices()
                } else {
                    Log.d(TAG, "GATT disconnected status=$status")
                    closeGatt()
                    scheduleNextScan()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                val char = gatt.getService(SERVICE_UUID)?.getCharacteristic(IP_CHAR_UUID)
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
                    handleRead(characteristic.value)
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
                    handleRead(value)
                    gatt.disconnect()
                }
            }
        }
        gatt = try {
            device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        } catch (e: SecurityException) {
            Log.w(TAG, "GATT connect denied: ${e.message}")
            null
        }
        handler.postDelayed({
            if (gatt != null) {
                Log.w(TAG, "GATT timeout")
                closeGatt()
                scheduleNextScan()
            }
        }, GATT_TIMEOUT_MS)
    }

    private fun handleRead(value: ByteArray?) {
        val text = value?.toString(Charsets.UTF_8)?.trim().orEmpty()
        val found = parseBeacon(text) ?: run {
            if (IPV4.matches(text) && text != "0.0.0.0") Discovery(text, null) else null
        }
        Log.d(TAG, "GATT read: $text → ${found?.ip} id=${found?.deviceId}")
        if (found != null) applyIP(found.ip, found.deviceId)
    }

    private fun applyIP(newIP: String, deviceId: String?) {
        val updated = keyPairStore.applyDiscoveredIp(newIP, deviceId) ?: run {
            Log.d(TAG, "Ignoring discovery $newIP id=$deviceId (no matching peer)")
            return
        }
        Log.d(TAG, "Updating peer ${updated.deviceId.take(8)} IP → $newIP")
        watching = false
        handler.removeCallbacksAndMessages(null)
        handler.post { onIPDiscovered?.invoke(newIP) }
    }

    private fun startUdpListen() {
        if (udpThread?.isAlive == true) return
        udpThread = Thread({
            try {
                val sock = DatagramSocket(null).apply {
                    reuseAddress = true
                    broadcast = true
                    bind(InetSocketAddress(UDP_BEACON_PORT))
                    soTimeout = 1500
                }
                udpSocket = sock
                Log.d(TAG, "UDP beacon listen on $UDP_BEACON_PORT")
                val buf = ByteArray(128)
                while (watching && !Thread.currentThread().isInterrupted) {
                    try {
                        val packet = DatagramPacket(buf, buf.size)
                        sock.receive(packet)
                        val text = String(packet.data, 0, packet.length, Charsets.UTF_8).trim()
                        val parts = text.split(Regex("\\s+"))
                        val found = parseBeacon(text)
                        if (found != null) {
                            Log.d(TAG, "UDP beacon ${found.ip} id=${found.deviceId} from ${packet.address.hostAddress}")
                            handler.post { applyIP(found.ip, found.deviceId) }
                        }
                    } catch (_: SocketTimeoutException) {
                    }
                }
                sock.close()
            } catch (e: Exception) {
                Log.w(TAG, "UDP listen failed: ${e.message}")
            }
        }, "bridge-lan-beacon").apply {
            isDaemon = true
            start()
        }
    }

    private fun stopUdpListen() {
        try { udpSocket?.close() } catch (_: Exception) {}
        udpSocket = null
        udpThread?.interrupt()
        udpThread = null
    }

    private fun closeGatt() {
        try {
            gatt?.disconnect()
            gatt?.close()
        } catch (_: Exception) {
        }
        gatt = null
    }
}
