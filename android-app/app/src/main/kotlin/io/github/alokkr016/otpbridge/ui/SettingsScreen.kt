package io.github.alokkr016.otpbridge.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.alokkr016.otpbridge.BuildConfig
import io.github.alokkr016.otpbridge.crypto.PairedDevice
import io.github.alokkr016.otpbridge.update.UpdateInfo
import io.github.alokkr016.otpbridge.update.UpdateManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    pairedDevices: List<PairedDevice>,
    onAddDevice: () -> Unit = {},
    onRemoveDevice: (String) -> Unit = {},
    onUnpairAll: () -> Unit = {},
    onClearHistory: () -> Unit = {},
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
    var deviceToRemove by remember { mutableStateOf<PairedDevice?>(null) }
    var showUnpairAll by remember { mutableStateOf(false) }
    var showClearDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp)
            .padding(bottom = 28.dp)
    ) {
        TextButton(onClick = onBack, modifier = Modifier.padding(top = 8.dp)) {
            Text("Back", color = MaterialTheme.colorScheme.onSurface)
        }
        Text(
            "Settings",
            fontSize = 32.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(bottom = 20.dp)
        )
        Column(verticalArrangement = Arrangement.spacedBy(28.dp)) {
            SettingsCard(title = "Paired devices") {
                if (pairedDevices.isEmpty()) {
                    Text(
                        "Not paired. Scan the QR code on your Mac or iPad.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    pairedDevices.forEachIndexed { index, device ->
                        if (index > 0) Divider(modifier = Modifier.padding(vertical = 4.dp))
                        Column(
                            Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                device.label,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            InfoRow(label = "Type", value = device.kindLabel)
                            InfoRow(label = "Address", value = "${device.ip}:${device.port}")
                            if (device.displayName.isNullOrBlank()) {
                                Text(
                                    "Scan this device’s QR again to save its computer name.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            TextButton(onClick = { deviceToRemove = device }) {
                                Text("Remove", color = MaterialTheme.colorScheme.error)
                            }
                        }
                    }
                }
                PillButton(text = "Add Mac or iPad", onClick = onAddDevice)
            }

            SettingsCard(title = "About") {
                InfoRow(label = "App", value = "Bridge")
                InfoRow(label = "Version", value = BuildConfig.VERSION_NAME)
                InfoRow(label = "Encryption", value = "X25519 + AES-256-GCM")
                InfoRow(label = "Network", value = "Local Wi-Fi only")
                MadeByAlok()
            }

            SettingsCard(title = "Updates") {
                if (updateInfo == null) {
                    Button(
                        onClick = {
                            isChecking = true
                            statusMessage = "Checking…"
                            scope.launch {
                                val info = updateManager.checkForUpdates()
                                isChecking = false
                                updateInfo = info
                                statusMessage = if (info.hasUpdate) {
                                    "v${info.latestVersionName} is available"
                                } else {
                                    "You’re on the latest version"
                                }
                            }
                        },
                        enabled = !isChecking,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(50),
                    ) {
                        if (isChecking) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                color = MaterialTheme.colorScheme.onPrimary,
                                strokeWidth = 2.dp
                            )
                            Spacer(Modifier.width(8.dp))
                        }
                        Text("Check for updates")
                    }
                } else {
                    Text(statusMessage, style = MaterialTheme.typography.bodyMedium)
                    if (updateInfo?.hasUpdate == true) {
                        if (isDownloading) {
                            LinearProgressIndicator(
                                progress = downloadProgress,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 8.dp)
                            )
                            Text(
                                "Downloading ${(downloadProgress * 100).toInt()}%",
                                style = MaterialTheme.typography.bodySmall
                            )
                        } else {
                            Button(
                                onClick = {
                                    isDownloading = true
                                    scope.launch {
                                        val success = updateManager.downloadAndInstallApk(updateInfo!!.apkUrl) { progress ->
                                            downloadProgress = progress
                                        }
                                        isDownloading = false
                                        if (!success) statusMessage = "Download failed. Try again."
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(50)
                            ) { Text("Download and install") }
                        }
                    }
                }
            }

            SettingsCard(title = "Danger") {
                TextButton(onClick = { showClearDialog = true }) {
                    Text("Clear history", color = MaterialTheme.colorScheme.error)
                }
                if (pairedDevices.isNotEmpty()) {
                    TextButton(onClick = { showUnpairAll = true }) {
                        Text("Unpair all devices", color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }

    if (showClearDialog) {
        AlertDialog(
            onDismissRequest = { showClearDialog = false },
            title = { Text("Clear history?") },
            text = { Text("All OTP history on this phone will be deleted.") },
            confirmButton = {
                TextButton(onClick = {
                    showClearDialog = false
                    onClearHistory()
                }) { Text("Clear", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showClearDialog = false }) { Text("Cancel") }
            }
        )
    }

    deviceToRemove?.let { device ->
        AlertDialog(
            onDismissRequest = { deviceToRemove = null },
            title = { Text("Remove this device?") },
            text = { Text("Bridge will stop sending OTPs to ${device.label} (${device.ip}). Scan its QR code to pair again.") },
            confirmButton = {
                TextButton(onClick = {
                    onRemoveDevice(device.deviceId)
                    deviceToRemove = null
                }) { Text("Remove", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { deviceToRemove = null }) { Text("Cancel") }
            }
        )
    }

    if (showUnpairAll) {
        AlertDialog(
            onDismissRequest = { showUnpairAll = false },
            title = { Text("Unpair all devices?") },
            text = { Text("Bridge will forget every Mac and iPad. You’ll scan each QR code again.") },
            confirmButton = {
                TextButton(onClick = {
                    showUnpairAll = false
                    onUnpairAll()
                    onBack()
                }) { Text("Unpair all", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showUnpairAll = false }) { Text("Cancel") }
            }
        )
    }
}

@Composable
internal fun MadeByAlok() {
    val context = LocalContext.current
    val link = "https://github.com/alokkr016"
    val alpha by rememberInfiniteTransition(label = "heart").animateFloat(
        initialValue = 1f,
        targetValue = 0.25f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 650),
            repeatMode = RepeatMode.Reverse
        ),
        label = "alpha"
    )
    val credit = buildAnnotatedString {
        append("Made with ")
        withStyle(SpanStyle(color = Color.Red.copy(alpha = alpha))) {
            append("♥")
        }
        append(" by ")
        pushStringAnnotation(tag = "URL", annotation = link)
        withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) {
            append("Alok")
        }
        pop()
    }
    ClickableText(
        text = credit,
        style = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurfaceVariant),
        modifier = Modifier.padding(top = 4.dp)
    ) { offset ->
        credit.getStringAnnotations(tag = "URL", start = offset, end = offset)
            .firstOrNull()
            ?.let { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it.item))) }
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            title,
            fontSize = 14.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        content()
    }
}

@Composable
private fun PillButton(text: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp),
        shape = RoundedCornerShape(50)
    ) {
        Text(text, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium
        )
    }
}
