package io.github.alokkr016.otpbridge.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

data class UpdateInfo(
    val hasUpdate: Boolean,
    val latestVersionCode: Int,
    val latestVersionName: String,
    val apkUrl: String,
    val notes: String
)

class UpdateManager(private val context: Context) {
    
    private val updateUrl = "https://bridge-updater.alokraj016.workers.dev/android"

    suspend fun checkForUpdates(): UpdateInfo = withContext(Dispatchers.IO) {
        try {
            val connection = URL(updateUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            connection.requestMethod = "GET"
            
            val jsonText = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(jsonText)
            
            val latestVersionCode = json.getInt("versionCode")
            val latestVersionName = json.getString("versionName")
            val apkUrl = json.getString("apkUrl")
            val notes = json.optString("notes", "")
            
            val currentVersionCode = getCurrentVersionCode()
            
            UpdateInfo(
                hasUpdate = latestVersionCode > currentVersionCode,
                latestVersionCode = latestVersionCode,
                latestVersionName = latestVersionName,
                apkUrl = apkUrl,
                notes = notes
            )
        } catch (e: Exception) {
            e.printStackTrace()
            UpdateInfo(false, 0, "", "", "")
        }
    }

    private fun getCurrentVersionCode(): Long {
        return try {
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            }
        } catch (e: Exception) {
            1
        }
    }

    suspend fun downloadAndInstallApk(apkUrl: String, onProgress: (Float) -> Unit): Boolean = withContext(Dispatchers.IO) {
        try {
            val url = URL(apkUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            connection.connect()

            val fileLength = connection.contentLength
            val apkFile = File(context.cacheDir, "update.apk")
            if (apkFile.exists()) {
                apkFile.delete()
            }

            connection.inputStream.use { input ->
                FileOutputStream(apkFile).use { output ->
                    val data = ByteArray(4096)
                    var total: Long = 0
                    var count: Int
                    while (input.read(data).also { count = it } != -1) {
                        total += count
                        if (fileLength > 0) {
                            onProgress(total.toFloat() / fileLength.toFloat())
                        }
                        output.write(data, 0, count)
                    }
                }
            }

            installApk(apkFile)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun installApk(file: File) {
        val authority = "${context.packageName}.fileprovider"
        val apkUri: Uri = FileProvider.getUriForFile(context, authority, file)
        
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}
