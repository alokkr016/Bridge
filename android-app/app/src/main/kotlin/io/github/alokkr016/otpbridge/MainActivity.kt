package io.github.alokkr016.otpbridge

import android.Manifest
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import io.github.alokkr016.otpbridge.service.BridgeForegroundService
import io.github.alokkr016.otpbridge.ui.MainScreen
import io.github.alokkr016.otpbridge.ui.theme.OTPBridgeTheme
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val POLL_INTERVAL_MS = 500L
    }

    private val webSocketClient by lazy { WebSocketClient.getInstance(this) }
    private var clipboardManager: ClipboardManager? = null
    private var lastSentClip: String? = null
    private var lastSeenClip: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private var hasFocus = false

    // Poll every 500ms while in foreground — Samsung doesn't reliably deliver
    // OnPrimaryClipChangedListener callbacks to third-party apps.
    private val pollRunnable = object : Runnable {
        override fun run() {
            if (hasFocus) {
                checkAndSendClipboard()
                handler.postDelayed(this, POLL_INTERVAL_MS)
            }
        }
    }

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) startForegroundService()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkNotificationListenerPermission()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        webSocketClient.onClipboardReceived = { text ->
            lastSentClip = text
            lastSeenClip = text  // prevent echo-back
        }

        setContent {
            OTPBridgeTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    MainScreen()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        requestPermissions()
    }

    override fun onPause() {
        super.onPause()
        stopPolling()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        this.hasFocus = hasFocus
        if (hasFocus) {
            startPolling()
        } else {
            stopPolling()
        }
    }

    private fun startPolling() {
        handler.removeCallbacks(pollRunnable)
        handler.post(pollRunnable)
        Log.d(TAG, "Clipboard polling started")
    }

    private fun stopPolling() {
        hasFocus = false
        handler.removeCallbacks(pollRunnable)
        Log.d(TAG, "Clipboard polling stopped")
    }

    private fun checkAndSendClipboard() {
        val text = try {
            clipboardManager?.primaryClip?.getItemAt(0)?.text?.toString()
        } catch (e: Exception) {
            null
        }
        if (text.isNullOrEmpty()) return
        if (text == lastSeenClip) return  // unchanged or just received from Mac
        lastSeenClip = text
        lastSentClip = text
        webSocketClient.sendClipboard(text)
        Log.d(TAG, "Clipboard sent to Mac: ${text.take(40)}")
    }

    private fun checkNotificationListenerPermission() {
        val enabled = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        )?.contains(ComponentName(this, "io.github.alokkr016.otpbridge.notification.OTNotificationListenerService").flattenToString()) ?: false
        if (!enabled) startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
    }

    private fun requestPermissions() {
        val permissions = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
            permissions.add(Manifest.permission.CAMERA)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                permissions.add(Manifest.permission.POST_NOTIFICATIONS)
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED)
                permissions.add(Manifest.permission.READ_SMS)
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED)
                permissions.add(Manifest.permission.RECEIVE_SMS)
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED)
                permissions.add(Manifest.permission.RECEIVE_SMS)
        }
        if (permissions.isNotEmpty()) requestPermissionLauncher.launch(permissions.toTypedArray())
        else startForegroundService()
    }

    private fun startForegroundService() {
        startForegroundService(Intent(this, BridgeForegroundService::class.java))
    }
}
