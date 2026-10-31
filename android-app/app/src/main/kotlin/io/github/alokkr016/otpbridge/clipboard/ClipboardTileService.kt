package io.github.alokkr016.otpbridge.clipboard

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/**
 * Quick Settings tile: "Send clipboard".
 *
 * A TileService is still a Service and has no window focus, so it cannot read
 * the clipboard itself — it launches ClipboardRelayActivity, which can.
 */
class ClipboardTileService : TileService() {

    companion object {
        private const val TAG = "ClipboardTile"

        /**
         * Nudges SystemUI to bind us so the tile shows a live state. Without an
         * active binding some OEM shells (One UI) can drop the first onClick.
         */
        fun requestListening(context: android.content.Context) {
            try {
                requestListeningState(
                    context,
                    ComponentName(context, ClipboardTileService::class.java)
                )
            } catch (e: Exception) {
                Log.w(TAG, "requestListeningState failed: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        Log.d(TAG, "onBind ${intent?.action}")
        return super.onBind(intent)
    }

    override fun onTileAdded() {
        super.onTileAdded()
        Log.d(TAG, "Tile added to Quick Settings")
        refreshTile()
    }

    override fun onStartListening() {
        super.onStartListening()
        Log.d(TAG, "onStartListening")
        refreshTile()
    }

    private fun refreshTile() {
        qsTile?.let {
            // Keep the tile ACTIVE so One UI always treats it as live and
            // reliably delivers onClick even after the service is unbound.
            it.state = Tile.STATE_ACTIVE
            it.subtitle = "Send to Mac"
            it.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        Log.d(TAG, "Tile tapped — launching relay")

        val intent = Intent(this, ClipboardRelayActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // API 34+ requires the PendingIntent overload.
                val pending = PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                startActivityAndCollapse(pending)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        } catch (e: Exception) {
            // startActivityAndCollapse can throw if we're not in a foreground
            // state; fall back to a plain start so the tap is never lost.
            Log.w(TAG, "startActivityAndCollapse failed (${e.message}) — plain start")
            try {
                startActivity(intent)
            } catch (e2: Exception) {
                Log.e(TAG, "Could not launch relay: ${e2.message}")
            }
        }
    }
}
