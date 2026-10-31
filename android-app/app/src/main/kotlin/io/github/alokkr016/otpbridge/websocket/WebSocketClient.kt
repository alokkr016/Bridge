package io.github.alokkr016.otpbridge.websocket

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import io.github.alokkr016.otpbridge.crypto.CryptoManager
import io.github.alokkr016.otpbridge.crypto.KeyPairStore
import io.github.alokkr016.otpbridge.notification.OTNotificationListenerService
import io.github.alokkr016.otpbridge.otp.HandshakeAckMessage
import io.github.alokkr016.otpbridge.otp.HandshakeMessage
import io.github.alokkr016.otpbridge.otp.OTPMessage
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.Socket
import java.net.InetSocketAddress

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

    private var socket: Socket? = null
    private var input: DataInputStream? = null
    private var output: DataOutputStream? = null
    private var sharedSecret: ByteArray? = null
    private var handshakeComplete = false
    private val writeLock = Any()
    private var rejectedPublicKey: ByteArray? = null
    val isHandshakeComplete: Boolean get() = handshakeComplete
    var isConnected = false
        private set
    private var isConnecting = false
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var reconnectJob: Job? = null
    private var reconnectDelay = 1000L
    private var readJob: Job? = null
    private var pingJob: Job? = null

    var onConnectionChanged: ((Boolean) -> Unit)? = null
    var onClipboardReceived: ((String) -> Unit)? = null
    var onDisconnected: (() -> Unit)? = null
    var onHandshakeComplete: (() -> Unit)? = null

    fun connect() {
        if (isConnected || isConnecting) {
            Log.d(TAG, "Already connected/connecting, skipping connect()")
            return
        }
        isConnecting = true
        val pairedDevice = keyPairStore.getPairedDevice() ?: run {
            Log.w(TAG, "No paired device found")
            isConnecting = false
            return
        }
        val rejected = rejectedPublicKey
        if (rejected != null && rejected.contentEquals(pairedDevice.publicKey)) {
            Log.e(TAG, "Paired key was rejected — re-pair required")
            isConnecting = false
            return
        }

        sharedSecret = pairedDevice.sharedSecret

        scope.launch {
            try {
                Log.d(TAG, "Connecting to ${pairedDevice.ip}:${pairedDevice.port}")
                val s = Socket()
                s.keepAlive = true          // OS-level TCP keepalive
                s.soTimeout = 30_000        // 30s read timeout — forces disconnect detection
                s.connect(InetSocketAddress(pairedDevice.ip, pairedDevice.port), 5000)
                socket = s
                input = DataInputStream(s.getInputStream())
                output = DataOutputStream(s.getOutputStream())
                isConnected = true
                isConnecting = false
                reconnectDelay = 1000L
                Log.d(TAG, "Connected")
                sendHandshake()
                startReading()
                startPing()
            } catch (e: Exception) {
                Log.e(TAG, "Connection failed: ${e.message}")
                isConnected = false
                isConnecting = false
                withContext(Dispatchers.Main) {
                    onConnectionChanged?.invoke(false)
                }
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
                publicKey = java.util.Base64.getEncoder().encodeToString(rawPubKey),
                token = keyPairStore.getPairedDevice()?.pairingToken
            )
            val message = json.encodeToString(handshake).toByteArray()
            synchronized(writeLock) { writeFrame(message) }
            Log.d(TAG, "Handshake sent")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send handshake: ${e.message}")
        }
    }

    private fun startReading() {
        val mySocket = socket  // capture at start; detect if we've been replaced
        readJob = scope.launch {
            try {
                while (isConnected && isActive) {
                    val length = readInt() ?: break
                    if (length <= 0 || length > 1_000_000) break
                    val payload = readBytes(length) ?: break

                    if (handshakeComplete && sharedSecret != null) {
                        try {
                            val opened = cryptoManager.open(payload, sharedSecret!!)
                            val device = keyPairStore.getPairedDevice()
                            if (device == null || !keyPairStore.acceptRecvSeq(opened.seq)) {
                                Log.w(TAG, "Rejected replayed frame")
                                continue
                            }
                            val message = String(opened.body)
                            val msgJson = org.json.JSONObject(message)
                            when (msgJson.optString("type")) {
                                "otp" -> {
                                    val otpMessage = json.decodeFromString(OTPMessage.serializer(), message)
                                    Log.d(TAG, "OTP received, length=${otpMessage.otp.length}")
                                    OTNotificationListenerService.onOTPReceived?.invoke(otpMessage)
                                }
                                "clipboard" -> {
                                    val text = msgJson.optString("text")
                                    if (text.isNotEmpty()) {
                                        withContext(Dispatchers.Main) {
                                            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                            cm.setPrimaryClip(ClipData.newPlainText("Bridge", text))
                                            onClipboardReceived?.invoke(text)
                                            Log.d(TAG, "Clipboard received from Mac")
                                        }
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Decryption failed (${e.message}) — re-handshaking")
                            handshakeComplete = false
                            sharedSecret = keyPairStore.getPairedDevice()?.sharedSecret
                            sendHandshake()
                        }
                    } else {
                        val text = String(payload)
                        Log.d(TAG, "Received handshake frame (${text.length} chars)")
                        try {
                            val ack = json.decodeFromString(HandshakeAckMessage.serializer(), text)
                            if (ack.type == "handshake_ack") {
                                val device = keyPairStore.getPairedDevice()
                                val macPubKeyBytes = try {
                                    java.util.Base64.getDecoder().decode(ack.publicKey)
                                } catch (e: Exception) {
                                    Log.e(TAG, "Malformed public key in ack: ${e.message}")
                                    continue
                                }
                                if (device == null || !macPubKeyBytes.contentEquals(device.publicKey)) {
                                    Log.e(TAG, "REJECTED handshake_ack: public key does not match the paired device")
                                    rejectedPublicKey = device?.publicKey?.copyOf()
                                    handleDisconnect(reconnect = false)
                                    return@launch
                                }
                                rejectedPublicKey = null
                                try {
                                    val myKeyPair = cryptoManager.getOrCreateKeyPair()
                                    val macPubKey = cryptoManager.parsePublicKey(macPubKeyBytes)
                                    sharedSecret = cryptoManager.deriveSharedSecret(myKeyPair.private, macPubKey)
                                    keyPairStore.clearPairingToken()
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to derive shared secret: ${e.message}")
                                    continue
                                }
                                handshakeComplete = true
                                withContext(Dispatchers.Main) {
                                    onConnectionChanged?.invoke(true)
                                    onHandshakeComplete?.invoke()
                                }
                            }
                        } catch (_: Exception) {}
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Read error: ${e.message}")
            }
            // Only handle disconnect if we are still the active socket (not already replaced by a reconnect)
            if (socket === mySocket) {
                handleDisconnect()
            } else {
                Log.d(TAG, "Old read loop exited, new connection already active — ignoring")
            }
        }
    }

    private fun startPing() {
        pingJob?.cancel()
        pingJob = scope.launch {
            while (isConnected && isActive) {
                delay(15_000L)
                if (!isConnected) break
                try {
                    // Send a raw 4-byte zero-length ping frame; Mac ignores zero-length frames
                    val pingBytes = byteArrayOf(0, 0, 0, 0)
                    output?.write(pingBytes)
                    output?.flush()
                } catch (e: Exception) {
                    Log.e(TAG, "Ping failed — connection broken: ${e.message}")
                    if (socket !== null) handleDisconnect()
                    break
                }
            }
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
        } catch (e: Exception) {
            null
        }
    }

    private fun readBytes(length: Int): ByteArray? {
        return try {
            val bytes = ByteArray(length)
            input?.readFully(bytes)
            bytes
        } catch (e: Exception) {
            null
        }
    }

    fun sendClipboard(text: String) {
        if (!isConnected || !handshakeComplete || sharedSecret == null) return
        scope.launch {
            try {
                val payload = """{"type":"clipboard","text":${org.json.JSONObject.quote(text)}}""".toByteArray()
                sendEncrypted(payload)
                Log.d(TAG, "Clipboard sent to Mac")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send clipboard: ${e.message}")
            }
        }
    }

    // Dedup key → timestamp of last send; prevents double-send when both SMSReceiver
    // and NotificationListener fire for the same SMS within 10 seconds.
    private val recentlySentOTPs = mutableMapOf<String, Long>()

    fun sendOTP(otpMessage: OTPMessage) {
        if (!isConnected || !handshakeComplete || sharedSecret == null) {
            Log.w(TAG, "Not ready to send OTP (connected=$isConnected, handshake=$handshakeComplete)")
            return
        }
        val dedupKey = "${otpMessage.sender}:${otpMessage.otp}"
        val now = System.currentTimeMillis()
        val lastSent = recentlySentOTPs[dedupKey] ?: 0L
        if (now - lastSent < 10_000L) {
            Log.d(TAG, "Duplicate OTP suppressed")
            return
        }
        recentlySentOTPs[dedupKey] = now
        // Prune old entries to avoid memory leak
        recentlySentOTPs.entries.removeIf { now - it.value > 60_000L }

        scope.launch {
            try {
                val jsonBytes = json.encodeToString(otpMessage).toByteArray()
                sendEncrypted(jsonBytes)
                Log.d(TAG, "OTP sent, length=${otpMessage.otp.length}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send OTP: ${e.message}")
            }
        }
    }

    private fun sendEncrypted(plain: ByteArray) {
        val secret = sharedSecret ?: return
        synchronized(writeLock) {
            val seq = keyPairStore.allocateSendSeq()
            val frame = cryptoManager.seal(plain, secret, seq)
            writeFrame(frame)
        }
    }

    private fun writeFrame(data: ByteArray) {
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
            Log.e(TAG, "Send failed: ${e.message}")
        }
    }

    private fun handleDisconnect(reconnect: Boolean = true) {
        isConnected = false
        isConnecting = false
        handshakeComplete = false
        sharedSecret = null
        try {
            socket?.close()
        } catch (_: Exception) {}
        socket = null
        input = null
        output = null
        scope.launch(Dispatchers.Main) {
            onConnectionChanged?.invoke(false)
            onDisconnected?.invoke()
        }
        if (reconnect) scheduleReconnect()
    }

    fun reconnect() {
        reconnectJob?.cancel()
        readJob?.cancel()
        pingJob?.cancel()
        try { socket?.close() } catch (_: Exception) {}
        socket = null; input = null; output = null
        isConnected = false; isConnecting = false; handshakeComplete = false; sharedSecret = null
        reconnectDelay = 1000L
        connect()
    }

    private fun scheduleReconnect() {
        if (reconnectJob?.isActive == true) return
        reconnectJob = scope.launch {
            delay(reconnectDelay)
            reconnectDelay = minOf(reconnectDelay * 2, 30000L)
            Log.d(TAG, "Attempting reconnect...")
            connect()
        }
    }

    fun disconnect() {
        reconnectJob?.cancel()
        readJob?.cancel()
        pingJob?.cancel()
        scope.launch(Dispatchers.IO) {
            handleDisconnect()
        }
    }

    fun destroy() {
        disconnect()
        scope.cancel()
    }
}
