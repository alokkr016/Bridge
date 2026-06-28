package io.github.alokkr016.otpbridge.service

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

class ServiceWatchdogWorker(
    private val context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    companion object {
        private const val TAG = "ServiceWatchdog"
        private const val WORK_NAME = "bridge_service_watchdog"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<ServiceWatchdogWorker>(
                4, TimeUnit.HOURS,
                30, TimeUnit.MINUTES  // flex window
            ).build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
            Log.d(TAG, "Watchdog scheduled (4h interval)")
        }
    }

    override fun doWork(): Result {
        if (!isServiceRunning()) {
            Log.w(TAG, "BridgeForegroundService not running — restarting")
            try {
                context.startForegroundService(
                    Intent(context, BridgeForegroundService::class.java)
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to restart service: ${e.message}")
                return Result.retry()
            }
        } else {
            Log.d(TAG, "BridgeForegroundService is alive — nothing to do")
        }
        return Result.success()
    }

    @Suppress("DEPRECATION")
    private fun isServiceRunning(): Boolean {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.getRunningServices(Int.MAX_VALUE)
            .any { it.service.className == BridgeForegroundService::class.java.name }
    }
}
