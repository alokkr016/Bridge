package io.github.alokkr016.otpbridge

import android.app.Application
import android.content.Intent
import android.os.Build
import io.github.alokkr016.otpbridge.database.OTPDatabase
import io.github.alokkr016.otpbridge.notification.NotificationHelper
import io.github.alokkr016.otpbridge.service.BridgeForegroundService

class OTPBridgeApp : Application() {

    val database by lazy { OTPDatabase.getDatabase(this) }

    override fun onCreate() {
        super.onCreate()
        NotificationHelper.createChannel(this)
        val intent = Intent(this, BridgeForegroundService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            android.util.Log.w("OTPBridgeApp", "Could not start foreground service: ${e.message}")
        }
    }
}
