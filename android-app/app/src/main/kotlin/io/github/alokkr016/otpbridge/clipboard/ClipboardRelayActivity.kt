package io.github.alokkr016.otpbridge.clipboard

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast

/**
 * Invisible, no-UI activity whose only job is to hold window focus long enough
 * to legally read the clipboard on Android 10+, then finish.
 *
 * The clipboard is read in onWindowFocusChanged rather than onCreate: focus is
 * precisely what ClipboardService checks, and it is not yet granted at onCreate.
 * A short timeout finishes the activity anyway if focus never arrives, so this
 * can never linger as an invisible window.
 */
class ClipboardRelayActivity : Activity() {

    companion object {
        private const val TAG = "ClipboardRelay"
        private const val FOCUS_TIMEOUT_MS = 1500L
    }

    private var handled = false
    private val timeout = Handler(Looper.getMainLooper())
    private val bailout = Runnable {
        if (!handled) {
            Log.w(TAG, "Never got window focus — giving up")
            finishQuietly()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // No setContentView — the theme is fully transparent and borderless.
        timeout.postDelayed(bailout, FOCUS_TIMEOUT_MS)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled) return
        handled = true
        timeout.removeCallbacks(bailout)

        val sent = ClipboardSyncer.syncNow(this)
        Toast.makeText(
            this,
            if (sent) "Clipboard sent to Mac" else "Nothing new to send",
            Toast.LENGTH_SHORT
        ).show()
        finishQuietly()
    }

    override fun onDestroy() {
        timeout.removeCallbacks(bailout)
        super.onDestroy()
    }

    private fun finishQuietly() {
        // Suppress the activity transition so nothing flashes on screen.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
        finish()
    }
}
