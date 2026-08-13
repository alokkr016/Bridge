package io.github.alokkr016.otpbridge.clipboard

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Toast

/**
 * Handles the "Send to Bridge" item on the text-selection floating toolbar
 * (ACTION_PROCESS_TEXT) and the system share sheet (ACTION_SEND).
 *
 * The selected text arrives inside the Intent, so unlike the tile /
 * notification paths this needs no clipboard access and therefore no window
 * focus — the Android 10+ focus restriction simply does not apply here.
 */
class SendSelectionActivity : Activity() {

    companion object {
        private const val TAG = "SendSelection"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = extractText(intent)
        val sent = ClipboardSyncer.sendText(this, text)
        Toast.makeText(
            this,
            if (sent) "Sent to Mac" else "Nothing to send",
            Toast.LENGTH_SHORT
        ).show()

        // PROCESS_TEXT contracts on returning the (possibly edited) text. We
        // never modify it, so echo it back unchanged to leave the selection be.
        if (intent?.action == Intent.ACTION_PROCESS_TEXT && text != null) {
            setResult(
                RESULT_OK,
                Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, text)
            )
        }
        finish()
    }

    private fun extractText(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_PROCESS_TEXT ->
                intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                    ?: intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT_READONLY)?.toString()
            Intent.ACTION_SEND ->
                intent.getStringExtra(Intent.EXTRA_TEXT)
            else -> {
                Log.w(TAG, "Unexpected action: ${intent.action}")
                null
            }
        }
    }
}
