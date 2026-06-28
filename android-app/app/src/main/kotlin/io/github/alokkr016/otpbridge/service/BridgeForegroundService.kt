package io.github.alokkr016.otpbridge.service

import android.Manifest
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.github.alokkr016.otpbridge.MainActivity
import io.github.alokkr016.otpbridge.R
import io.github.alokkr016.otpbridge.notification.NotificationHelper
import io.github.alokkr016.otpbridge.pairing.BLEScanner
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

class BridgeForegroundService : Service() {

    companion object {
        private const val TAG = "BridgeForegroundService"
        const val CHANNEL_ID = "otp_bridge_channel"
        const val NOTIFICATION_ID = 1002
    }

    private val webSocketClient by lazy { WebSocketClient.getInstance(this) }
    private val bleScanner by lazy { BLEScanner(this) }
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var lastSentClip: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        NotificationHelper.createChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            startForeground(NOTIFICATION_ID, createNotification())
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

        // When TCP connection drops, scan BLE to find Mac's new IP (requires runtime BT permission)
        webSocketClient.onDisconnected = {
            Log.d(TAG, "Connection lost — starting BLE scan for Mac IP")
            tryStartBLEScan()
        }

        webSocketClient.connect()

        // Track clipboard text received from Mac so we don't echo it back
        webSocketClient.onClipboardReceived = { text -> lastSentClip = text }

        // Watch Android clipboard and forward changes to Mac
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
            val text = cm.primaryClip?.getItemAt(0)?.text?.toString() ?: return@OnPrimaryClipChangedListener
            if (text.isNotEmpty() && text != lastSentClip) {
                lastSentClip = null
                webSocketClient.sendClipboard(text)
            }
        }
        cm.addPrimaryClipChangedListener(clipboardListener!!)

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
            bleScanner.startScan()
        } catch (e: SecurityException) {
            Log.w(TAG, "BLE scan denied: ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "BLE scan failed: ${e.message}")
        }
    }

    override fun onDestroy() {
        clipboardListener?.let {
            (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).removePrimaryClipChangedListener(it)
        }
        bleScanner.stopScan()
        wakeLock?.release()
        wifiLock?.release()
        webSocketClient.disconnect()
        super.onDestroy()
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("OTP Bridge")
            .setContentText("Running in background")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
