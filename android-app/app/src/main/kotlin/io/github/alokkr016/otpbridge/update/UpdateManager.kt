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
            if (!isAllowedUpdateUrl(apkUrl)) {
                return@withContext UpdateInfo(false, 0, "", "", "")
            }
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
        if (!isAllowedUpdateUrl(apkUrl)) return@withContext false
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

            if (!signatureMatchesInstalled(apkFile)) {
                apkFile.delete()
                return@withContext false
            }
            withContext(Dispatchers.Main) {
                installApk(apkFile)
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun isAllowedUpdateUrl(raw: String): Boolean {
        val url = try {
            URL(raw)
        } catch (_: Exception) {
            return false
        }
        if (!url.protocol.equals("https", ignoreCase = true)) return false
        val host = url.host.lowercase()
        if (host == "bridge-updater.alokraj016.workers.dev") return true
        return host == "github.com" || host.endsWith(".githubusercontent.com")
    }

    private fun signatureMatchesInstalled(apk: File): Boolean {
        val flags = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            android.content.pm.PackageManager.GET_SIGNATURES
        }
        val installed = try {
            context.packageManager.getPackageInfo(context.packageName, flags)
        } catch (_: Exception) {
            return false
        }
        val incoming = context.packageManager.getPackageArchiveInfo(apk.absolutePath, flags) ?: return false
        val installedSigs = signaturesOf(installed)
        val incomingSigs = signaturesOf(incoming)
        return installedSigs.isNotEmpty() && installedSigs == incomingSigs
    }

    private fun signaturesOf(info: android.content.pm.PackageInfo): Set<String> {
        val raw = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners?.map { it.toCharsString() }
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.map { it.toCharsString() }
        }
        return raw?.toSet().orEmpty()
    }

    private fun installApk(file: File) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            val settings = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(settings)
            return
        }

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
