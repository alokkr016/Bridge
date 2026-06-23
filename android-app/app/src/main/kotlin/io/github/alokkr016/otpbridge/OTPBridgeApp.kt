package io.github.alokkr016.otpbridge

import android.app.Application
import io.github.alokkr016.otpbridge.database.OTPDatabase
import io.github.alokkr016.otpbridge.notification.NotificationHelper

class OTPBridgeApp : Application() {

    val database by lazy { OTPDatabase.getDatabase(this) }

    override fun onCreate() {
        super.onCreate()
        NotificationHelper.createChannel(this)
    }
}
