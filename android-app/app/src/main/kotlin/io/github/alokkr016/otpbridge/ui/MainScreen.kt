package io.github.alokkr016.otpbridge.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.alokkr016.otpbridge.R
import io.github.alokkr016.otpbridge.database.OTPEntity
import io.github.alokkr016.otpbridge.ui.theme.OTPGreen
import io.github.alokkr016.otpbridge.viewmodel.MainViewModel
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            painter = painterResource(R.drawable.logo),
                            contentDescription = null,
                            modifier = Modifier
                                .size(28.dp)
                                .clip(RoundedCornerShape(7.dp))
                        )
                        Spacer(Modifier.width(10.dp))
                        Text("Bridge", fontWeight = FontWeight.SemiBold)
                    }
                },
                actions = {
                    ConnectionChip(isPaired = isPaired, isConnected = isConnected)
                    IconButton(onClick = { showSettings = true }) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        },
        bottomBar = {
            Surface(color = MaterialTheme.colorScheme.surface) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    MadeByAlok()
                }
            }
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        when {
            !isPaired -> {
                UnpairedHome(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    onPair = { showPairing = true }
                )
            }
            else -> {
                PairedHome(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    isConnected = isConnected,
                    needsRePair = needsRePair,
                    recentOTPs = recentOTPs,
                    copiedOtp = copiedOtp,
                    onCopy = ::copyOtp,
                    onReconnect = { viewModel.connectToMac() },
                    onRePair = { showPairing = true }
                )
            }
        }
    }
}

@Composable
private fun ConnectionChip(isPaired: Boolean, isConnected: Boolean) {
    val label = when {
        isConnected -> "Live"
        isPaired -> "Offline"
        else -> "Setup"
    }
    val color = when {
        isConnected -> OTPGreen
        isPaired -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(
        shape = CircleShape,
        color = color.copy(alpha = 0.14f),
        modifier = Modifier.padding(end = 4.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                Modifier
                    .size(7.dp)
                    .clip(CircleShape)
            ) {
                Surface(color = color, modifier = Modifier.fillMaxSize()) {}
            }
            Spacer(Modifier.width(6.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = color,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun UnpairedHome(modifier: Modifier, onPair: () -> Unit) {
    Column(
        modifier = modifier.padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Image(
            painter = painterResource(R.drawable.logo),
            contentDescription = null,
            modifier = Modifier
                .size(88.dp)
                .clip(RoundedCornerShape(22.dp))
        )
        Spacer(Modifier.height(24.dp))
        Text(
            "Codes from your phone,\non your Mac.",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(Modifier.height(10.dp))
        Text(
            "Pair once over Wi-Fi. OTPs, clipboard, and calls stay on your network — nothing goes to the cloud.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(28.dp))
        Button(
            onClick = onPair,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            shape = RoundedCornerShape(14.dp)
        ) {
            Icon(Icons.Default.QrCodeScanner, contentDescription = null)
            Spacer(Modifier.width(10.dp))
            Text("Pair with Mac", fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun PairedHome(
    modifier: Modifier,
    isConnected: Boolean,
    needsRePair: Boolean,
    recentOTPs: List<OTPEntity>,
    copiedOtp: String?,
    onCopy: (String) -> Unit,
    onReconnect: () -> Unit,
    onRePair: () -> Unit
) {
    val latest = recentOTPs.firstOrNull()
    val rest = recentOTPs.drop(1).take(2)

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (!isConnected) {
            item {
                OfflineBanner(
                    needsRePair = needsRePair,
                    onReconnect = onReconnect,
                    onRePair = onRePair
                )
            }
        }

        if (latest != null) {
            item {
                HeroOtpCard(
                    source = latest.company ?: latest.sender,
                    otp = latest.otp,
                    timestamp = latest.timestamp,
                    copied = copiedOtp == latest.otp,
                    onCopy = { onCopy(latest.otp) }
                )
            }
        } else {
            item { WaitingForOtpCard(isConnected) }
        }

        if (rest.isNotEmpty()) {
            item {
                Text(
                    "Recent",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }

        items(rest, key = { it.id }) { otp ->
            RecentOtpRow(
                source = otp.company ?: otp.sender,
                otp = otp.otp,
                timestamp = otp.timestamp,
                copied = copiedOtp == otp.otp,
                onCopy = { onCopy(otp.otp) }
            )
        }
    }
}

@Composable
private fun OfflineBanner(
    needsRePair: Boolean,
    onReconnect: () -> Unit,
    onRePair: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.error.copy(alpha = 0.12f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Default.WifiOff,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    if (needsRePair) "Re-pair required" else "Mac is offline",
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    if (needsRePair) "Mac key changed after restart. Scan the QR again."
                    else "Phone can see the Mac, but the session is not live.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            FilledTonalButton(onClick = if (needsRePair) onRePair else onReconnect) {
                Icon(
                    if (needsRePair) Icons.Default.QrCodeScanner else Icons.Default.Refresh,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text(if (needsRePair) "Pair" else "Retry")
            }
        }
    }
}

@Composable
private fun WaitingForOtpCard(isConnected: Boolean) {
    Surface(
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                if (isConnected) "Waiting for a code" else "Ready once you reconnect",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(Modifier.height(6.dp))
            Text(
                "When an SMS OTP arrives, it shows up here and copies to your Mac.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun HeroOtpCard(
    source: String,
    otp: String,
    timestamp: Long,
    copied: Boolean,
    onCopy: () -> Unit
) {
    Surface(
        onClick = onCopy,
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.primaryContainer,
        tonalElevation = 2.dp
    ) {
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SourceAvatar(source)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(source, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(
                        relativeTime(timestamp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                    )
                }
                Icon(
                    imageVector = if (copied) Icons.Default.Check else Icons.Default.ContentCopy,
                    contentDescription = if (copied) "Copied" else "Copy",
                    tint = if (copied) OTPGreen else MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
            Spacer(Modifier.height(16.dp))
            Text(
                groupedOtp(otp),
                fontSize = 36.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.primary,
                letterSpacing = 1.sp
            )
            Spacer(Modifier.height(6.dp))
            Text(
                if (copied) "Copied" else "Tap to copy",
                style = MaterialTheme.typography.labelMedium,
                color = if (copied) OTPGreen else MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
            )
        }
    }
}

@Composable
private fun RecentOtpRow(
    source: String,
    otp: String,
    timestamp: Long,
    copied: Boolean,
    onCopy: () -> Unit
) {
    Surface(
        onClick = onCopy,
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            SourceAvatar(source, size = 32)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    groupedOtp(otp),
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 16.sp
                )
                Text(
                    source,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1
                )
            }
            if (copied) {
                Icon(Icons.Default.Check, contentDescription = "Copied", tint = OTPGreen)
            } else {
                Text(
                    relativeTime(timestamp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun SourceAvatar(source: String, size: Int = 36) {
    val letter = source.trim().firstOrNull()?.uppercaseChar()?.toString() ?: "?"
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.22f),
        modifier = Modifier.size(size.dp)
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                letter,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.secondary
            )
        }
    }
}

private fun groupedOtp(otp: String): String {
    val digits = otp.filter { it.isDigit() }
    return if (digits.length == 6) "${digits.take(3)} ${digits.drop(3)}" else otp
}

private fun relativeTime(timestamp: Long): String {
    val seconds = (System.currentTimeMillis() - timestamp) / 1000
    return when {
        seconds < 45 -> "just now"
        seconds < 3600 -> "${seconds / 60}m ago"
        seconds < 86400 -> "${seconds / 3600}h ago"
        else -> {
            val sdf = java.text.SimpleDateFormat("MMM d", java.util.Locale.getDefault())
            sdf.format(java.util.Date(timestamp))
        }
    }
}
