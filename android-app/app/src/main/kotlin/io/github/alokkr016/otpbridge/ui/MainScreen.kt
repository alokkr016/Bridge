package io.github.alokkr016.otpbridge.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.alokkr016.otpbridge.database.OTPEntity
import io.github.alokkr016.otpbridge.viewmodel.MainViewModel
import kotlinx.coroutines.delay

@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val isPaired by viewModel.isPaired.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()
    val needsRePair by viewModel.needsRePair.collectAsState()
    val pairedDevices by viewModel.pairedDevices.collectAsState()
    val recentOTPs by viewModel.recentOTPs.collectAsState()
    var showPairing by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var copiedOtp by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    LaunchedEffect(copiedOtp) {
        val code = copiedOtp ?: return@LaunchedEffect
        delay(2000)
        if (copiedOtp == code) copiedOtp = null
    }

    if (showPairing) {
        PairingScreen(
            onPaired = { deviceId, publicKey, ip, port, displayName, kind, pairingToken ->
                viewModel.completePairing(deviceId, publicKey, ip, port, displayName, kind, pairingToken)
                showPairing = false
            },
            onDismiss = { showPairing = false }
        )
        return
    }

    if (showSettings) {
        SettingsScreen(
            pairedDevices = pairedDevices,
            onAddDevice = {
                showSettings = false
                showPairing = true
            },
            onRemoveDevice = { viewModel.removeDevice(it) },
            onUnpairAll = { viewModel.clearPairing() },
            onClearHistory = { viewModel.clearHistory() },
            onBack = { showSettings = false }
        )
        return
    }

    fun copyOtp(otp: String) {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("OTP", otp))
        copiedOtp = otp
    }

    if (!isPaired) {
        UnpairedHome(onPair = { showPairing = true }, onSettings = { showSettings = true })
    } else {
        PairedHome(
            isConnected = isConnected,
            needsRePair = needsRePair,
            recentOTPs = recentOTPs,
            copiedOtp = copiedOtp,
            onCopy = ::copyOtp,
            onReconnect = { viewModel.connectToMac() },
            onRePair = { showPairing = true },
            onSettings = { showSettings = true }
        )
    }
}

@Composable
private fun ScreenChrome(
    status: String,
    onSettings: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 20.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text("Bridge", fontSize = 28.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    status,
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
            TextButton(onClick = onSettings) {
                Text("Settings", color = MaterialTheme.colorScheme.onSurface)
            }
        }
        content()
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            MadeByAlok()
        }
    }
}

@Composable
private fun UnpairedHome(onPair: () -> Unit, onSettings: () -> Unit) {
    ScreenChrome(status = "Not paired", onSettings = onSettings) {
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                "Codes from your phone, on your Mac.",
                fontSize = 36.sp,
                fontWeight = FontWeight.SemiBold,
                lineHeight = 42.sp
            )
            Spacer(Modifier.height(14.dp))
            Text(
                "Pair once over Wi-Fi. Codes, clipboard, and calls stay on your network.",
                fontSize = 16.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                lineHeight = 22.sp
            )
            Spacer(Modifier.height(28.dp))
            PillButton(text = "Pair with Mac", onClick = onPair)
        }
    }
}

@Composable
private fun PairedHome(
    isConnected: Boolean,
    needsRePair: Boolean,
    recentOTPs: List<OTPEntity>,
    copiedOtp: String?,
    onCopy: (String) -> Unit,
    onReconnect: () -> Unit,
    onRePair: () -> Unit,
    onSettings: () -> Unit
) {
    val latest = recentOTPs.firstOrNull()
    val rest = recentOTPs.drop(1).take(2)
    val status = when {
        isConnected -> "Live"
        needsRePair -> "Re-pair required"
        else -> "Offline"
    }

    ScreenChrome(status = status, onSettings = onSettings) {
        if (!isConnected) {
            Text(
                if (needsRePair) "The Mac key changed. Scan the QR again."
                else "The phone can see the Mac, but the session is not live.",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp)
            )
            TextButton(onClick = if (needsRePair) onRePair else onReconnect) {
                Text(
                    if (needsRePair) "Scan again" else "Retry",
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }

        if (latest != null) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    "${latest.company ?: latest.sender}  ·  ${relativeTime(latest.timestamp)}",
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    groupedOtp(latest.otp),
                    fontSize = 56.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 0.sp,
                    modifier = Modifier.clickable { onCopy(latest.otp) }
                )
                Spacer(Modifier.height(22.dp))
                PillButton(
                    text = if (copiedOtp == latest.otp) "Copied" else "Copy",
                    onClick = { onCopy(latest.otp) }
                )
            }
        } else {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    if (isConnected) "Waiting for a code" else "Ready once you reconnect",
                    fontSize = 36.sp,
                    fontWeight = FontWeight.SemiBold,
                    lineHeight = 42.sp
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    "When a code arrives, it shows up here and copies to your Mac.",
                    fontSize = 16.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 22.sp
                )
            }
        }

        if (rest.isNotEmpty()) {
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            rest.forEach { otp ->
                RecentLine(
                    source = otp.company ?: otp.sender,
                    otp = otp.otp,
                    timestamp = otp.timestamp,
                    copied = copiedOtp == otp.otp,
                    onCopy = { onCopy(otp.otp) }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            }
        }
    }
}

@Composable
private fun RecentLine(
    source: String,
    otp: String,
    timestamp: Long,
    copied: Boolean,
    onCopy: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onCopy)
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(groupedOtp(otp), fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.width(12.dp))
        Text(
            if (copied) "Copied" else source,
            fontSize = 14.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
            maxLines = 1
        )
        Text(
            relativeTime(timestamp),
            fontSize = 14.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun PillButton(text: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp),
        shape = RoundedCornerShape(50),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary
        )
    ) {
        Text(text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}

private fun groupedOtp(otp: String): String {
    val digits = otp.filter { it.isDigit() }
    return if (digits.length == 6) "${digits.take(3)} ${digits.drop(3)}" else otp
}

private fun relativeTime(timestamp: Long): String {
    val seconds = (System.currentTimeMillis() - timestamp) / 1000
    return when {
        seconds < 45 -> "now"
        seconds < 3600 -> "${seconds / 60}m"
        seconds < 86400 -> "${seconds / 3600}h"
        else -> {
            val sdf = java.text.SimpleDateFormat("MMM d", java.util.Locale.getDefault())
            sdf.format(java.util.Date(timestamp))
        }
    }
}
