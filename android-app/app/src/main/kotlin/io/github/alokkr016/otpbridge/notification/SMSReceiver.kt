package io.github.alokkr016.otpbridge.notification

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import io.github.alokkr016.otpbridge.otp.OTPExtractor
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

class SMSReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SMSReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        val smsMap = mutableMapOf<String, StringBuilder>()

        for (msg in messages) {
            val sender = msg.displayOriginatingAddress ?: msg.originatingAddress ?: "Unknown"
            smsMap.getOrPut(sender) { StringBuilder() }.append(msg.messageBody ?: "")
        }

        for ((sender, body) in smsMap) {
            val fullText = body.toString()
            Log.d(TAG, "SMS from $sender: $fullText")

            val otpMessage = OTPExtractor.extractOTP(sender, fullText)
            if (otpMessage != null) {
                Log.d(TAG, "OTP extracted: ${otpMessage.otp} from ${otpMessage.sender}")
                OTNotificationListenerService.onOTPReceived?.invoke(otpMessage)
                WebSocketClient.getInstance(context).sendOTP(otpMessage)
            }
        }
    }
}
