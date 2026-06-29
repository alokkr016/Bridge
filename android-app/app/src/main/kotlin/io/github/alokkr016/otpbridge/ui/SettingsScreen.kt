package io.github.alokkr016.otpbridge.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.alokkr016.otpbridge.crypto.PairedDevice
import io.github.alokkr016.otpbridge.update.UpdateInfo
import io.github.alokkr016.otpbridge.update.UpdateManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    pairedDevice: PairedDevice?,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val updateManager = remember { UpdateManager(context) }

    var isChecking by remember { mutableStateOf(false) }
    var statusMessage by remember { mutableStateOf("") }
    var updateInfo by remember { mutableStateOf<UpdateInfo?>(null) }
    var isDownloading by remember { mutableStateOf(false) }
    var downloadProgress by remember { mutableStateOf(0f) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Connection", style = MaterialTheme.typography.titleMedium)

            if (pairedDevice != null) {
                InfoRow(label = "Mac IP", value = pairedDevice.ip)
                InfoRow(label = "Port", value = pairedDevice.port.toString())
                InfoRow(label = "Device ID", value = pairedDevice.deviceId.take(16) + "…")
            } else {
                Text(
                    text = "Not paired with any Mac.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Divider()

            Text("About", style = MaterialTheme.typography.titleMedium)
            InfoRow(label = "App", value = "Bridge")
            InfoRow(label = "Protocol", value = "X25519 + AES-256-GCM over TCP :8420")
            InfoRow(label = "Network", value = "Local Wi-Fi only — no cloud")

            Divider()

            Text("Updates", style = MaterialTheme.typography.titleMedium)
            
            if (updateInfo == null) {
                Button(
                    onClick = {
                        isChecking = true
                        statusMessage = "Checking for updates..."
                        scope.launch {
                            val info = updateManager.checkForUpdates()
                            isChecking = false
                            updateInfo = info
                            if (info.hasUpdate) {
                                statusMessage = "New version v${info.latestVersionName} available!"
                            } else {
                                statusMessage = "Bridge is up to date ✓"
                            }
                        }
                    },
                    enabled = !isChecking,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (isChecking) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text("Check for Updates")
                }
            } else {
                Text(statusMessage, style = MaterialTheme.typography.bodyMedium)
                if (updateInfo?.hasUpdate == true) {
                    Spacer(modifier = Modifier.height(4.dp))
                    if (isDownloading) {
                        LinearProgressIndicator(
                            progress = downloadProgress,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)
                        )
                        Text("Downloading: ${(downloadProgress * 100).toInt()}%", style = MaterialTheme.typography.bodySmall)
                    } else {
                        Button(
                            onClick = {
                                isDownloading = true
                                scope.launch {
                                    val success = updateManager.downloadAndInstallApk(updateInfo!!.apkUrl) { progress ->
                                        downloadProgress = progress
                                    }
                                    isDownloading = false
                                    if (!success) {
                                        statusMessage = "Download failed. Please try again."
                                    }
                                }
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("Download and Install Update")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}
