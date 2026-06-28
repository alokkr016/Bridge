package io.github.alokkr016.otpbridge.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.alokkr016.otpbridge.crypto.PairedDevice

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    pairedDevice: PairedDevice?,
    onBack: () -> Unit
) {
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
            InfoRow(label = "App", value = "OTP Bridge")
            InfoRow(label = "Protocol", value = "X25519 + AES-256-GCM over TCP :8420")
            InfoRow(label = "Network", value = "Local Wi-Fi only — no cloud")
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
