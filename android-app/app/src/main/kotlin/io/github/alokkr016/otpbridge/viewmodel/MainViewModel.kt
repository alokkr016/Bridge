package io.github.alokkr016.otpbridge.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.alokkr016.otpbridge.OTPBridgeApp
import io.github.alokkr016.otpbridge.crypto.PairedDevice
import io.github.alokkr016.otpbridge.database.OTPEntity
import io.github.alokkr016.otpbridge.notification.OTNotificationListenerService
import io.github.alokkr016.otpbridge.pairing.PairingManager
import io.github.alokkr016.otpbridge.websocket.WebSocketClient
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val pairingManager = PairingManager(application)
    private val database = (application as OTPBridgeApp).database
    private val otpDao = database.otpDao()
    private val webSocketClient = WebSocketClient.getInstance(application)

    val isPaired: StateFlow<Boolean> = MutableStateFlow(pairingManager.isPaired())
    val isConnected: StateFlow<Boolean> = MutableStateFlow(false)
    val pairedDevices: StateFlow<List<PairedDevice>> =
        MutableStateFlow(pairingManager.getPairedDevices())
    val recentOTPs: StateFlow<List<OTPEntity>> = otpDao.getRecentOTPs()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val pairedDevice get() = pairingManager.getPairedDevice()

    init {
        (isConnected as MutableStateFlow).value = webSocketClient.isHandshakeComplete
        webSocketClient.onConnectionChanged = { connected ->
            (isConnected as MutableStateFlow).value = connected
        }

        OTNotificationListenerService.onOTPReceived = { otpMessage ->
            viewModelScope.launch {
                otpDao.insertOTP(
                    OTPEntity(
                        sender = otpMessage.sender,
                        otp = otpMessage.otp,
                        company = otpMessage.company,
                        timestamp = otpMessage.timestamp
                    )
                )
            }
        }
    }

    fun connectToMac() {
        if (pairingManager.isPaired()) {
            webSocketClient.reconnect()
        }
    }

    fun completePairing(deviceId: String, publicKey: ByteArray, ip: String, port: Int) {
        pairingManager.completePairing(deviceId, publicKey, ip, port)
        refreshPeers()
        webSocketClient.connect()
    }

    fun disconnect() {
        webSocketClient.disconnect()
    }

    fun clearPairing() {
        webSocketClient.disconnect()
        pairingManager.clearPairing()
        refreshPeers()
    }

    fun removeDevice(deviceId: String) {
        pairingManager.removeDevice(deviceId)
        refreshPeers()
        if (pairingManager.isPaired()) webSocketClient.connect()
        else webSocketClient.disconnect()
    }

    fun clearHistory() {
        viewModelScope.launch {
            otpDao.deleteAll()
        }
    }

    private fun refreshPeers() {
        (isPaired as MutableStateFlow).value = pairingManager.isPaired()
        (pairedDevices as MutableStateFlow).value = pairingManager.getPairedDevices()
    }
}
