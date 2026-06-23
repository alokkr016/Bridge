package io.github.alokkr016.otpbridge.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.github.alokkr016.otpbridge.MainActivity
import io.github.alokkr016.otpbridge.R
import io.github.alokkr016.otpbridge.notification.NotificationHelper
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

class BridgeForegroundService : Service() {

    companion object {
        private const val TAG = "BridgeForegroundService"
        const val CHANNEL_ID = "otp_bridge_channel"
        const val NOTIFICATION_ID = 1002
    }

    private val webSocketClient by lazy { WebSocketClient.getInstance(this) }
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

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

        webSocketClient.connect()
        return START_STICKY
    }

    override fun onDestroy() {
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
