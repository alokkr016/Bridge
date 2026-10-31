package io.github.alokkr016.otpbridge.clipboard

import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import io.github.alokkr016.otpbridge.websocket.WebSocketClient

/**
 * Single owner of "read the clipboard and push it to the Mac".
 *
 * Android 10+ only returns a primary clip to a caller that currently has window
 * focus, so every entry point here must be driven by a focused UI component
 * (MainActivity, or ClipboardRelayActivity for the tile / notification paths).
 * Reads from a Service always come back null.
 */
object ClipboardSyncer {

    private const val TAG = "ClipboardSyncer"

    /** Last value we sent or received, so we never echo the Mac's own clip back. */
    @Volatile
    private var lastSyncedClip: String? = null

    /** Called when the Mac pushes us a clip, to suppress the return trip. */
    fun noteRemoteClip(text: String) {
        lastSyncedClip = text
    }

    /**
     * Sends text handed to us directly (e.g. the selection from an
     * ACTION_PROCESS_TEXT toolbar item), bypassing the clipboard entirely.
     *
     * Unlike syncNow this needs no window focus and applies no de-dupe: the
     * user explicitly asked for *this* selection to go, so sending the same
     * string twice is a legitimate request rather than an echo.
     *
     * @return true if something was sent.
     */
    fun sendText(context: Context, text: String?): Boolean {
        val trimmed = text?.takeIf { it.isNotBlank() } ?: run {
            Log.d(TAG, "No text supplied — nothing to send")
            return false
        }
        lastSyncedClip = trimmed
        Log.d(TAG, "Selection → Mac: ${trimmed.take(40)}")
        WebSocketClient.getInstance(context).sendClipboard(trimmed)
        return true
    }

    /**
     * Reads the current clip and sends it if it is new.
     * @return true if something was sent.
     */
    fun syncNow(context: Context): Boolean {
        val text = readClip(context)
        if (text.isNullOrEmpty()) {
            Log.d(TAG, "Clipboard empty or unreadable (no window focus?)")
            return false
        }
        if (text == lastSyncedClip) {
            Log.d(TAG, "Clipboard unchanged — nothing to send")
            return false
        }
        lastSyncedClip = text
        Log.d(TAG, "Clipboard → Mac: ${text.take(40)}")
        WebSocketClient.getInstance(context).sendClipboard(text)
        return true
    }

    private fun readClip(context: Context): String? = try {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()
    } catch (e: Exception) {
        Log.w(TAG, "Clipboard read failed: ${e.message}")
        null
    }
}
