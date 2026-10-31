package io.github.alokkr016.otpbridge.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.alokkr016.otpbridge.R
import io.github.alokkr016.otpbridge.viewmodel.MainViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val isPaired by viewModel.isPaired.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()
    val recentOTPs by viewModel.recentOTPs.collectAsState()
    var showPairing by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }

    if (showPairing) {
        PairingScreen(
            onPaired = { deviceId, publicKey, ip, port, token ->
                viewModel.completePairing(deviceId, publicKey, ip, port, token)
                showPairing = false
            },
            onDismiss = { showPairing = false }
        )
        return
    }

    if (showSettings) {
        SettingsScreen(
            pairedDevice = viewModel.pairedDevice,
            onBack = { showSettings = false }
        )
        return
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
                                .clip(RoundedCornerShape(6.dp))
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Text("Bridge")
                    }
                },
                actions = {
                    IconButton(onClick = { showSettings = true }) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
        ) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = if (isConnected)
                        MaterialTheme.colorScheme.primaryContainer
                    else
                        MaterialTheme.colorScheme.errorContainer
                )
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = if (isConnected) Icons.Default.Link else Icons.Default.LinkOff,
                        contentDescription = null,
                        tint = if (isConnected)
                            MaterialTheme.colorScheme.primary
                        else
                            MaterialTheme.colorScheme.error
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = if (isConnected) "Connected to Mac" else "Disconnected",
                            style = MaterialTheme.typography.titleMedium
                        )
                        Text(
                            text = if (isPaired) "Paired" else "Not paired",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            if (!isPaired) {
                Button(
                    onClick = { showPairing = true },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Pair with Mac")
                }
            } else {
                OutlinedButton(
                    onClick = { viewModel.connectToMac() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isConnected
                ) {
                    Text("Reconnect")
                }
                Spacer(modifier = Modifier.height(8.dp))

                var showUnpairDialog by remember { mutableStateOf(false) }
                OutlinedButton(
                    onClick = { showUnpairDialog = true },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Unpair")
                }
                if (showUnpairDialog) {
                    AlertDialog(
                        onDismissRequest = { showUnpairDialog = false },
                        title = { Text("Unpair device?") },
                        text = { Text("This will disconnect from your Mac and delete the pairing. You'll need to scan the QR code again to reconnect.") },
                        confirmButton = {
                            TextButton(
                                onClick = {
                                    showUnpairDialog = false
                                    viewModel.clearPairing()
                                }
                            ) {
                                Text("Unpair", color = MaterialTheme.colorScheme.error)
                            }
                        },
                        dismissButton = {
                            TextButton(onClick = { showUnpairDialog = false }) {
                                Text("Cancel")
                            }
                        }
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Recent OTPs",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f)
                )
                if (recentOTPs.isNotEmpty()) {
                    var showClearDialog by remember { mutableStateOf(false) }
                    TextButton(onClick = { showClearDialog = true }) {
                        Text("Clear", color = MaterialTheme.colorScheme.error)
                    }
                    if (showClearDialog) {
                        AlertDialog(
                            onDismissRequest = { showClearDialog = false },
                            title = { Text("Clear history?") },
                            text = { Text("All OTP history will be deleted.") },
                            confirmButton = {
                                TextButton(onClick = {
                                    showClearDialog = false
                                    viewModel.clearHistory()
                                }) {
                                    Text("Clear", color = MaterialTheme.colorScheme.error)
                                }
                            },
                            dismissButton = {
                                TextButton(onClick = { showClearDialog = false }) {
                                    Text("Cancel")
                                }
                            }
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))

            if (recentOTPs.isEmpty()) {
                Text(
                    text = "No OTPs received yet",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                LazyColumn {
                    items(recentOTPs) { otp ->
                        OTPHistoryItem(otp.company ?: otp.sender, otp.otp, otp.timestamp)
                    }
                }
            }
        }
    }
}

@Composable
fun OTPHistoryItem(sender: String, otp: String, timestamp: Long) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(text = sender, style = MaterialTheme.typography.titleSmall)
                Text(
                    text = otp,
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Text(
                text = formatTimestamp(timestamp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private fun formatTimestamp(timestamp: Long): String {
    val sdf = java.text.SimpleDateFormat("h:mm a", java.util.Locale.getDefault())
    return sdf.format(java.util.Date(timestamp))
}
