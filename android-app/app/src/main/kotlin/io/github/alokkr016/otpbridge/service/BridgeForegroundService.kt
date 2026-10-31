package io.github.alokkr016.otpbridge.service

import android.Manifest
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.github.alokkr016.otpbridge.MainActivity
import io.github.alokkr016.otpbridge.R
import io.github.alokkr016.otpbridge.notification.NotificationHelper
import io.github.alokkr016.otpbridge.call.CallController
import io.github.alokkr016.otpbridge.clipboard.ClipboardRelayActivity
import io.github.alokkr016.otpbridge.clipboard.ClipboardTileService
import io.github.alokkr016.otpbridge.pairing.BLEScanner
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

class BridgeForegroundService : Service() {

    companion object {
        private const val TAG = "BridgeForegroundService"
        const val CHANNEL_ID = NotificationHelper.CHANNEL_ID
        const val NOTIFICATION_ID = 1002
    }

    private val webSocketClient by lazy { WebSocketClient.getInstance(this) }
    private val bleScanner by lazy { BLEScanner(this) }
    private val callController by lazy { CallController(this) }
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        NotificationHelper.createChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            startForegroundWithBestType()
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed: ${e.message} — running without foreground")
        }

        // Keep CPU + Wi-Fi alive even without foreground status
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "OTPBridge::WakeLock").apply {
            acquire(12 * 60 * 60 * 1000L) // 12 hours max
        }
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "OTPBridge::WifiLock").apply {
            acquire()
        }

        // When BLE discovers a new Mac IP, update stored IP and reconnect
        bleScanner.onIPDiscovered = { newIP ->
            Log.d(TAG, "BLE discovered new Mac IP: $newIP — reconnecting")
            webSocketClient.reconnect()
        }

        // Handshake means we have the right IP — stop burning BLE.
        webSocketClient.onHandshakeComplete = {
            Log.d(TAG, "Handshake complete — stopping BLE watch")
            bleScanner.stopWatching()
        }

        // Drop or failed connect: keep scanning until the Mac advertises a new IP
        webSocketClient.onDisconnected = {
            Log.d(TAG, "Connection lost — watching BLE for Mac IP")
            tryStartBLEScan()
        }

        callController.onCallState = { state, number, name ->
            webSocketClient.sendCall(state, number, name)
        }
        webSocketClient.onCallControl = { action ->
            callController.handleControl(action)
        }
        callController.start()

        // Ask SystemUI to bind the QS tile so it has a live state and reliably
        // delivers taps even when this process has been idle.
        ClipboardTileService.requestListening(this)

        webSocketClient.connect()

        return START_STICKY
    }

    private fun tryStartBLEScan() {
        val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        if (!hasPermission) {
            Log.w(TAG, "BLUETOOTH_SCAN permission not granted — skipping BLE scan")
            return
        }
        try {
            bleScanner.startWatching()
        } catch (e: SecurityException) {
            Log.w(TAG, "BLE scan denied: ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "BLE scan failed: ${e.message}")
        }
    }

    override fun onDestroy() {
        callController.stop()
        bleScanner.stopWatching()
        wakeLock?.release()
        wifiLock?.release()
        webSocketClient.disconnect()
        super.onDestroy()
    }

    private fun startForegroundWithBestType() {
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+: use connectedDevice if BLUETOOTH_CONNECT is granted (no 6h limit),
            // else fall back to dataSync. connectedDevice is designed for maintaining a
            // persistent connection to a paired device — exactly what we're doing.
            val hasBtConnect = ContextCompat.checkSelfPermission(
                this, Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
            val serviceType = if (hasBtConnect) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            }
            Log.d(TAG, "startForeground type=${if (hasBtConnect) "connectedDevice" else "dataSync (bt not granted)"}")
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, serviceType)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        // The service itself can't read the clipboard (no window focus), so this
        // action routes through the invisible relay activity, which can.
        val clipIntent = PendingIntent.getActivity(
            this, 1,
            Intent(this, ClipboardRelayActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_infinity)
            .setContentTitle("Bridge")
            .setContentText("Running in background")
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_menu_send,
                getString(R.string.send_clipboard),
                clipIntent
            )
            .setOngoing(true)
            .build()
    }
}
