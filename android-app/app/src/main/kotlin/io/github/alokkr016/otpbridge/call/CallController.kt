package io.github.alokkr016.otpbridge.call

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.provider.ContactsContract
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Watches cellular call state and answers or ends the ringing or active call.
 * Audio stays on the phone. This is control only.
 */
class CallController(private val context: Context) {

    companion object {
        private const val TAG = "CallController"
    }

    var onCallState: ((state: String, number: String, name: String?) -> Unit)? = null

    private var lastNumber = ""
    private var lastName: String? = null
    private var lastState = "idle"
    private var listening = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent?.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
            val extra = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
            val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER).orEmpty()
            val mapped = when (extra) {
                TelephonyManager.EXTRA_STATE_RINGING -> "ringing"
                TelephonyManager.EXTRA_STATE_OFFHOOK -> "offhook"
                else -> "idle"
            }
            handleState(mapped, number)
        }
    }

    fun start() {
        if (listening) return
        if (!has(Manifest.permission.READ_PHONE_STATE)) {
            Log.w(TAG, "READ_PHONE_STATE not granted — call control disabled")
            return
        }
        listening = true
        val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
        try {
            ContextCompat.registerReceiver(
                context,
                receiver,
                filter,
                ContextCompat.RECEIVER_EXPORTED
            )
            Log.d(TAG, "Call listener started")
        } catch (e: Exception) {
            listening = false
            Log.w(TAG, "Could not listen for calls: ${e.message}")
        }
    }

    fun stop() {
        if (!listening) return
        listening = false
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
    }

    fun handleControl(action: String) {
        when (action) {
            "answer" -> answer()
            "hangup" -> hangup()
            else -> Log.w(TAG, "Unknown call action")
        }
    }

    private fun answer() {
        if (!has(Manifest.permission.ANSWER_PHONE_CALLS)) {
            Log.w(TAG, "ANSWER_PHONE_CALLS not granted")
            return
        }
        try {
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            @Suppress("DEPRECATION")
            tm.acceptRingingCall()
            Log.d(TAG, "Accepted ringing call")
        } catch (e: Exception) {
            Log.e(TAG, "Answer failed: ${e.message}")
        }
    }

    private fun hangup() {
        if (!has(Manifest.permission.ANSWER_PHONE_CALLS)) {
            Log.w(TAG, "ANSWER_PHONE_CALLS not granted")
            return
        }
        try {
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                tm.endCall()
                Log.d(TAG, "Ended call")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Hangup failed: ${e.message}")
        }
    }

    private fun handleState(mapped: String, incomingNumber: String) {
        if (incomingNumber.isNotBlank()) {
            lastNumber = incomingNumber
            lastName = lookupName(incomingNumber)
        }
        if (mapped == "idle") {
            lastNumber = ""
            lastName = null
        }
        // The first PHONE_STATE is often missing the number; a second fire fills it in.
        if (mapped == lastState && incomingNumber.isBlank()) return
        lastState = mapped
        Log.d(TAG, "Call state=$mapped")
        onCallState?.invoke(mapped, lastNumber, lastName)
    }

    private fun lookupName(number: String): String? {
        if (!has(Manifest.permission.READ_CONTACTS) || number.isBlank()) return null
        return try {
            val uri = android.net.Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                android.net.Uri.encode(number)
            )
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Contact lookup failed: ${e.message}")
            null
        }
    }

    private fun has(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
}
