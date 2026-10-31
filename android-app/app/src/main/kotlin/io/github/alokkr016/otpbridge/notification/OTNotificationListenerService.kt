package io.github.alokkr016.otpbridge.notification

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.github.alokkr016.otpbridge.otp.OTPExtractor
import io.github.alokkr016.otpbridge.otp.OTPMessage
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

class OTNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "OTNotificationListener"
        var onOTPReceived: ((OTPMessage) -> Unit)? = null

        private val MESSAGING_PACKAGES = setOf(
            "com.google.android.apps.messaging",
            "com.android.mms",
            "com.android.messaging",
            "com.samsung.android.messaging",
            "com.samsung.android.messagingapplication",
            "com.sonyericsson.conversations",
            "com.oneplus.mms"
        )
    }

    private val webSocketClient by lazy { WebSocketClient.getInstance(this) }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.isOngoing) return
        if (sbn.packageName == "io.github.alokkr016.otpbridge") return

        val notification = sbn.notification
        val extras = notification.extras
        val allText = StringBuilder()

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        allText.append(title).append(" ")

        extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.let { allText.append(it).append(" ") }
        extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.let { allText.append(it).append(" ") }
        extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()?.let { allText.append(it).append(" ") }
        extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.let { allText.append(it).append(" ") }
        extras.getCharSequence(Notification.EXTRA_INFO_TEXT)?.toString()?.let { allText.append(it).append(" ") }

        val fullText = allText.toString().trim()
        if (fullText.isBlank()) return

        val otpMessage = OTPExtractor.extractOTP(
            title,
            fullText,
            allowBareTitle = sbn.packageName in MESSAGING_PACKAGES
        )

        if (otpMessage != null) {
            Log.d(TAG, "OTP extracted, length=${otpMessage.otp.length}")
            onOTPReceived?.invoke(otpMessage)
            webSocketClient.sendOTP(otpMessage)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
    }
}
