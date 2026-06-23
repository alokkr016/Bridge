package io.github.alokkr016.otpbridge.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.github.alokkr016.otpbridge.MainActivity
import io.github.alokkr016.otpbridge.R
import io.github.alokkr016.otpbridge.notification.NotificationHelper
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

class BridgeForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "otp_bridge_channel"
        const val NOTIFICATION_ID = 1002
    }

    private val webSocketClient by lazy { WebSocketClient.getInstance(this) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        NotificationHelper.createChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        webSocketClient.connect()
        return START_STICKY
    }

    override fun onDestroy() {
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
