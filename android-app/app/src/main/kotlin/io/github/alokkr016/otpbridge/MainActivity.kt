package io.github.alokkr016.otpbridge

import android.Manifest
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import io.github.alokkr016.otpbridge.service.BridgeForegroundService
import io.github.alokkr016.otpbridge.service.ServiceWatchdogWorker
import io.github.alokkr016.otpbridge.ui.MainScreen
import io.github.alokkr016.otpbridge.ui.theme.OTPBridgeTheme
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val PREF_BATTERY_PROMPT_SHOWN = "battery_opt_prompt_shown"
    }

    private val webSocketClient by lazy { WebSocketClient.getInstance(this) }
    private var clipboardManager: ClipboardManager? = null
    private var lastSentClip: String? = null
    private var showBatteryDialog by mutableStateOf(false)

    // Fires while MainActivity is the foreground app — Android 10+ allows clipboard
    // reads inside this callback when the activity is visible.
    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        sendClipboardIfNew()
    }

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        // Start service as long as core permissions are satisfied, regardless of BT result.
        // BLUETOOTH_CONNECT is used to upgrade the FGS type — not required to run.
        startForegroundService()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkNotificationListenerPermission()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        // Track what Mac sends us so we don't echo it back
        webSocketClient.onClipboardReceived = { text -> lastSentClip = text }
        ServiceWatchdogWorker.schedule(this)

        setContent {
            OTPBridgeTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    MainScreen()
                }
            }

            if (showBatteryDialog) {
                AlertDialog(
                    onDismissRequest = { dismissBatteryDialog() },
                    title = { Text("Keep Bridge Running") },
                    text = {
                        Text(
                            "Samsung's battery optimizer can stop the app after a few hours, " +
                            "causing you to miss OTPs.\n\n" +
                            "Go to Settings → Battery → Background usage limits → " +
                            "Never sleeping apps → Add Bridge."
                        )
                    },
                    confirmButton = {
                        TextButton(onClick = {
                            dismissBatteryDialog()
                            openBatterySettings()
                        }) { Text("Open Settings") }
                    },
                    dismissButton = {
                        TextButton(onClick = { dismissBatteryDialog() }) { Text("Later") }
                    }
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        requestPermissions()
        maybeShowBatteryOptimizationDialog()
        clipboardManager?.addPrimaryClipChangedListener(clipListener)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // OS only grants clipboard access once the window has focus — not during onResume.
            // Reading here avoids the "application is not in focus" denial from ClipboardService.
            sendClipboardIfNew()
        }
    }

    override fun onPause() {
        super.onPause()
        clipboardManager?.removePrimaryClipChangedListener(clipListener)
    }

    private fun sendClipboardIfNew() {
        val text = try {
            clipboardManager?.primaryClip?.getItemAt(0)?.text?.toString()
        } catch (e: Exception) { null }
        if (text.isNullOrEmpty()) return
        if (text == lastSentClip) return
        lastSentClip = text
        Log.d(TAG, "Clipboard → Mac: ${text.take(40)}")
        webSocketClient.sendClipboard(text)
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED)
                permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }
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
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED)
            permissions.add(Manifest.permission.READ_PHONE_STATE)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ANSWER_PHONE_CALLS) != PackageManager.PERMISSION_GRANTED)
            permissions.add(Manifest.permission.ANSWER_PHONE_CALLS)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED)
            permissions.add(Manifest.permission.READ_CALL_LOG)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED)
            permissions.add(Manifest.permission.READ_CONTACTS)
        if (permissions.isNotEmpty()) requestPermissionLauncher.launch(permissions.toTypedArray())
        else startForegroundService()
    }

    private fun startForegroundService() {
        startForegroundService(Intent(this, BridgeForegroundService::class.java))
    }

    private fun maybeShowBatteryOptimizationDialog() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val prefs = getSharedPreferences("otp_bridge_prefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean(PREF_BATTERY_PROMPT_SHOWN, false)) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        showBatteryDialog = true
    }

    private fun dismissBatteryDialog() {
        showBatteryDialog = false
        getSharedPreferences("otp_bridge_prefs", Context.MODE_PRIVATE)
            .edit().putBoolean(PREF_BATTERY_PROMPT_SHOWN, true).apply()
    }

    private fun openBatterySettings() {
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }
}
