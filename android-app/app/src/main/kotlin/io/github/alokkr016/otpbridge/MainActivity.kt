package io.github.alokkr016.otpbridge

import android.Manifest
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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
    }

    private val webSocketClient by lazy { WebSocketClient.getInstance(this) }
    private var clipboardManager: ClipboardManager? = null
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var lastSentClip: String? = null

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            startForegroundService()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkNotificationListenerPermission()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        setContent {
            OTPBridgeTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    MainScreen()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        requestPermissions()
        registerClipboardListener()
    }

    override fun onPause() {
        super.onPause()
        unregisterClipboardListener()
    }

    // Android 10+ only allows clipboard reads when the app has window focus.
    // Register here so we can read clips the moment the user switches to us.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            registerClipboardListener()
            // Also sync the current clipboard immediately when focus is gained
            syncCurrentClipboard()
        } else {
            unregisterClipboardListener()
        }
    }

    private fun registerClipboardListener() {
        val cm = clipboardManager ?: return
        if (clipboardListener != null) return
        // Also keep service informed of what Mac last sent so echo prevention works cross-process
        webSocketClient.onClipboardReceived = { text -> lastSentClip = text }
        clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
            syncCurrentClipboard()
        }
        cm.addPrimaryClipChangedListener(clipboardListener!!)
        Log.d(TAG, "Clipboard listener registered")
    }

    private fun unregisterClipboardListener() {
        clipboardListener?.let { clipboardManager?.removePrimaryClipChangedListener(it) }
        clipboardListener = null
    }

    private fun syncCurrentClipboard() {
        val text = try {
            clipboardManager?.primaryClip?.getItemAt(0)?.text?.toString()
        } catch (e: Exception) {
            Log.w(TAG, "Could not read clipboard: ${e.message}")
            null
        } ?: return
        if (text.isEmpty() || text == lastSentClip) return
        lastSentClip = null
        webSocketClient.sendClipboard(text)
        Log.d(TAG, "Clipboard synced to Mac")
    }

    private fun checkNotificationListenerPermission() {
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )?.contains(ComponentName(this, "io.github.alokkr016.otpbridge.notification.OTNotificationListenerService").flattenToString()) ?: false

        if (!enabled) {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }

    private fun requestPermissions() {
        val permissions = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            permissions.add(Manifest.permission.CAMERA)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.POST_NOTIFICATIONS)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_SMS)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.RECEIVE_SMS)
            }
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.RECEIVE_SMS)
            }
        }
        if (permissions.isNotEmpty()) {
            requestPermissionLauncher.launch(permissions.toTypedArray())
        } else {
            startForegroundService()
        }
    }

    private fun startForegroundService() {
        val intent = Intent(this, BridgeForegroundService::class.java)
        startForegroundService(intent)
    }
}
