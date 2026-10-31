package io.github.alokkr016.otpbridge.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import io.github.alokkr016.otpbridge.R

object NotificationHelper {

    const val CHANNEL_ID = "otp_bridge_status"
    private const val NOTIFICATION_ID = 1001

    fun createChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Bridge",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Shows Bridge is running"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    fun showConnectionStatus(context: Context, connected: Boolean) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_infinity)
            .setContentTitle("Bridge")
            .setContentText(if (connected) "Connected to Mac" else "Disconnected")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    fun dismissConnectionStatus(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(NOTIFICATION_ID)
    }
}
