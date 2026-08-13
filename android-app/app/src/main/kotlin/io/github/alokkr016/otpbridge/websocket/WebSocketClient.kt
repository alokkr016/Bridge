package io.github.alokkr016.otpbridge.websocket

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import io.github.alokkr016.otpbridge.crypto.CryptoManager
import io.github.alokkr016.otpbridge.crypto.KeyPairStore
import io.github.alokkr016.otpbridge.crypto.PairedDevice
import io.github.alokkr016.otpbridge.notification.OTNotificationListenerService
import io.github.alokkr016.otpbridge.otp.HandshakeAckMessage
import io.github.alokkr016.otpbridge.otp.HandshakeMessage
import io.github.alokkr016.otpbridge.otp.OTPMessage
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap

class WebSocketClient private constructor(private val context: Context) {

    companion object {
        private const val TAG = "WebSocketClient"
        private var instance: WebSocketClient? = null

        fun getInstance(context: Context): WebSocketClient {
            return instance ?: WebSocketClient(context.applicationContext).also { instance = it }
        }
    }

    private val cryptoManager = CryptoManager(context)
    private val keyPairStore = KeyPairStore(context)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val peers = ConcurrentHashMap<String, PeerSession>()

    val isHandshakeComplete: Boolean get() = peers.values.any { it.handshakeComplete }
    val isConnected: Boolean get() = peers.values.any { it.isConnected && it.handshakeComplete }

    var onConnectionChanged: ((Boolean) -> Unit)? = null
    var onClipboardReceived: ((String) -> Unit)? = null
    var onDisconnected: (() -> Unit)? = null
    var onHandshakeComplete: (() -> Unit)? = null
    var onCallControl: ((String) -> Unit)? = null

    private val recentlySentOTPs = mutableMapOf<String, Long>()

    fun connect() {
        val devices = keyPairStore.getPairedDevices()
        if (devices.isEmpty()) {
            Log.w(TAG, "No paired devices")
            return
        }
        val ids = devices.map { it.deviceId }.toSet()
        peers.keys.filter { it !in ids }.forEach { id ->
            peers.remove(id)?.close(reconnect = false)
        }
        for (device in devices) {
            val session = peers.getOrPut(device.deviceId) {
                PeerSession(device)
            }
            session.device = device
            session.ensureConnected()
        }
    }

    fun reconnect() {
        peers.values.forEach { it.close(reconnect = false) }
        peers.clear()
        connect()
    }

    fun disconnect() {
        peers.values.forEach { it.close(reconnect = false) }
        peers.clear()
        publishConnection()
    }

    fun destroy() {
        disconnect()
        scope.cancel()
    }

    fun sendCall(state: String, number: String, name: String?) {
        val obj = org.json.JSONObject()
            .put("type", "call")
            .put("state", state)
            .put("number", number)
        if (!name.isNullOrBlank()) obj.put("name", name)
        fanOut(obj.toString().toByteArray())
    }

    fun sendClipboard(text: String) {
        val payload = """{"type":"clipboard","text":${org.json.JSONObject.quote(text)}}""".toByteArray()
        fanOut(payload)
    }

    fun sendOTP(otpMessage: OTPMessage) {
        val ready = peers.values.filter { it.isConnected && it.handshakeComplete && it.sharedSecret != null }
        if (ready.isEmpty()) {
            Log.w(TAG, "Not ready to send OTP (peers=${peers.size})")
            return
        }
        val dedupKey = "${otpMessage.sender}:${otpMessage.otp}"
        val now = System.currentTimeMillis()
        val lastSent = recentlySentOTPs[dedupKey] ?: 0L
        if (now - lastSent < 10_000L) {
            Log.d(TAG, "Duplicate OTP suppressed: ${otpMessage.otp}")
            return
        }
        recentlySentOTPs[dedupKey] = now
        recentlySentOTPs.entries.removeIf { now - it.value > 60_000L }

        try {
            val jsonBytes = json.encodeToString(otpMessage).toByteArray()
            for (peer in ready) {
                peer.sendEncrypted(jsonBytes)
            }
            Log.d(TAG, "OTP sent to ${ready.size} peer(s): ${otpMessage.otp}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send OTP: ${e.message}")
        }
    }

    private fun fanOut(plain: ByteArray) {
        for (peer in peers.values) {
            if (peer.isConnected && peer.handshakeComplete && peer.sharedSecret != null) {
                peer.sendEncrypted(plain)
            }
        }
    }

    private fun publishConnection() {
        val up = isConnected
        scope.launch(Dispatchers.Main) {
            onConnectionChanged?.invoke(up)
            if (up) onHandshakeComplete?.invoke()
            else onDisconnected?.invoke()
        }
    }

    private inner class PeerSession(var device: PairedDevice) {
        var socket: Socket? = null
        var input: DataInputStream? = null
        var output: DataOutputStream? = null
        var sharedSecret: ByteArray? = device.sharedSecret
        var handshakeComplete = false
        var isConnected = false
        private var isConnecting = false
        private var reconnectDelay = 1000L
        private var readJob: Job? = null
        private var pingJob: Job? = null
        private var reconnectJob: Job? = null

        fun ensureConnected() {
            if (isConnected || isConnecting) return
            connectOnce()
        }

        private fun connectOnce() {
            if (isConnected || isConnecting) return
            isConnecting = true
            sharedSecret = device.sharedSecret
            scope.launch {
                try {
                    Log.d(TAG, "[${device.deviceId.take(8)}] Connecting to ${device.ip}:${device.port}")
                    val s = Socket()
                    s.keepAlive = true
                    s.soTimeout = 0
                    s.connect(InetSocketAddress(device.ip, device.port), 5000)
                    socket = s
                    input = DataInputStream(s.getInputStream())
                    output = DataOutputStream(s.getOutputStream())
                    isConnected = true
                    isConnecting = false
                    reconnectDelay = 1000L
                    sendHandshake()
                    startReading()
                    startPing()
                } catch (e: Exception) {
                    Log.e(TAG, "[${device.deviceId.take(8)}] Connection failed: ${e.message}")
                    isConnected = false
                    isConnecting = false
                    publishConnection()
                    scheduleReconnect()
                }
            }
        }

        private fun sendHandshake() {
            try {
                val keyPair = cryptoManager.getOrCreateKeyPair()
                val rawPubKey = keyPair.public.encoded.takeLast(32).toByteArray()
                val handshake = HandshakeMessage(
                    deviceId = cryptoManager.getDeviceId(),
                    publicKey = java.util.Base64.getEncoder().encodeToString(rawPubKey)
                )
                sendFrame(json.encodeToString(handshake).toByteArray())
                Log.d(TAG, "[${device.deviceId.take(8)}] Handshake sent")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send handshake: ${e.message}")
            }
        }

        private fun startReading() {
            val mySocket = socket
            readJob = scope.launch {
                try {
                    while (isConnected && isActive) {
                        val length = readInt() ?: break
                        if (length <= 0 || length > 1_000_000) break
                        val payload = readBytes(length) ?: break
                        handlePayload(payload)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "[${device.deviceId.take(8)}] Read error: ${e.message}")
                }
                if (socket === mySocket) handleDisconnect()
            }
        }

        private suspend fun handlePayload(payload: ByteArray) {
            if (handshakeComplete && sharedSecret != null) {
                try {
                    val decrypted = cryptoManager.decrypt(payload, sharedSecret!!)
                    val message = String(decrypted)
                    val msgJson = org.json.JSONObject(message)
                    when (msgJson.optString("type")) {
                        "otp" -> {
                            val otpMessage = json.decodeFromString(OTPMessage.serializer(), message)
                            OTNotificationListenerService.onOTPReceived?.invoke(otpMessage)
                        }
                        "clipboard" -> {
                            val text = msgJson.optString("text")
                            if (text.isNotEmpty()) {
                                withContext(Dispatchers.Main) {
                                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    cm.setPrimaryClip(ClipData.newPlainText("Bridge", text))
                                    onClipboardReceived?.invoke(text)
                                }
                            }
                        }
                        "call_control" -> {
                            val action = msgJson.optString("action")
                            withContext(Dispatchers.Main) { onCallControl?.invoke(action) }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "[${device.deviceId.take(8)}] Decrypt failed (${e.message}) — re-handshaking")
                    handshakeComplete = false
                    sharedSecret = device.sharedSecret
                    sendHandshake()
                }
            } else {
                val text = String(payload)
                try {
                    val ack = json.decodeFromString(HandshakeAckMessage.serializer(), text)
                    if (ack.type == "handshake_ack") {
                        val peerPubKeyBytes = try {
                            java.util.Base64.getDecoder().decode(ack.publicKey)
                        } catch (e: Exception) {
                            Log.e(TAG, "Malformed public key in ack: ${e.message}")
                            close(reconnect = true)
                            return
                        }
                        // The key must be the one captured from the QR code. Otherwise
                        // a rogue host answering on the paired IP could impersonate the
                        // peer and receive our OTPs.
                        if (!peerPubKeyBytes.contentEquals(device.publicKey)) {
                            Log.e(
                                TAG,
                                "[${device.deviceId.take(8)}] REJECTED handshake_ack: " +
                                    "public key does not match the paired device — possible impostor"
                            )
                            close(reconnect = false)
                            return
                        }
                        try {
                            val myKeyPair = cryptoManager.getOrCreateKeyPair()
                            val peerPubKey = cryptoManager.parsePublicKey(peerPubKeyBytes)
                            sharedSecret = cryptoManager.deriveSharedSecret(myKeyPair.private, peerPubKey)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to re-derive shared secret: ${e.message}")
                            close(reconnect = true)
                            return
                        }
                        handshakeComplete = true
                        Log.d(TAG, "[${device.deviceId.take(8)}] Handshake complete")
                        publishConnection()
                    }
                } catch (_: Exception) {}
            }
        }

        private fun startPing() {
            pingJob?.cancel()
            pingJob = scope.launch {
                while (isConnected && isActive) {
                    delay(15_000L)
                    if (!isConnected) break
                    try {
                        output?.write(byteArrayOf(0, 0, 0, 0))
                        output?.flush()
                    } catch (e: Exception) {
                        Log.e(TAG, "[${device.deviceId.take(8)}] Ping failed: ${e.message}")
                        if (socket != null) handleDisconnect()
                        break
                    }
                }
            }
        }

        fun sendEncrypted(plain: ByteArray) {
            val secret = sharedSecret ?: return
            scope.launch {
                try {
                    sendFrame(cryptoManager.encrypt(plain, secret))
                } catch (e: Exception) {
                    Log.e(TAG, "[${device.deviceId.take(8)}] Send failed: ${e.message}")
                }
            }
        }

        private fun sendFrame(data: ByteArray) {
            try {
                val lengthBytes = byteArrayOf(
                    ((data.size shr 24) and 0xFF).toByte(),
                    ((data.size shr 16) and 0xFF).toByte(),
                    ((data.size shr 8) and 0xFF).toByte(),
                    (data.size and 0xFF).toByte()
                )
                output?.write(lengthBytes)
                output?.write(data)
                output?.flush()
            } catch (e: Exception) {
                Log.e(TAG, "[${device.deviceId.take(8)}] Frame send failed: ${e.message}")
            }
        }

        private fun readInt(): Int? {
            return try {
                val bytes = ByteArray(4)
                input?.readFully(bytes)
                (bytes[0].toInt() and 0xFF) shl 24 or
                    (bytes[1].toInt() and 0xFF) shl 16 or
                    (bytes[2].toInt() and 0xFF) shl 8 or
                    (bytes[3].toInt() and 0xFF)
            } catch (_: Exception) {
                null
            }
        }

        private fun readBytes(length: Int): ByteArray? {
            return try {
                val bytes = ByteArray(length)
                input?.readFully(bytes)
                bytes
            } catch (_: Exception) {
                null
            }
        }

        private fun handleDisconnect() {
            isConnected = false
            isConnecting = false
            handshakeComplete = false
            sharedSecret = null
            try { socket?.close() } catch (_: Exception) {}
            socket = null
            input = null
            output = null
            publishConnection()
            scheduleReconnect()
        }

        private fun scheduleReconnect() {
            if (reconnectJob?.isActive == true) return
            reconnectJob = scope.launch {
                delay(reconnectDelay)
                reconnectDelay = minOf(reconnectDelay * 2, 30_000L)
                val latest = keyPairStore.getPairedDevices().find { it.deviceId == device.deviceId }
                if (latest == null) return@launch
                device = latest
                connectOnce()
            }
        }

        fun close(reconnect: Boolean) {
            reconnectJob?.cancel()
            readJob?.cancel()
            pingJob?.cancel()
            try { socket?.close() } catch (_: Exception) {}
            socket = null
            input = null
            output = null
            isConnected = false
            isConnecting = false
            handshakeComplete = false
            if (reconnect) scheduleReconnect()
        }
    }
}
