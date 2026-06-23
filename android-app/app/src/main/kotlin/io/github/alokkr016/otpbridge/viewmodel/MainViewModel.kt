package io.github.alokkr016.otpbridge.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.alokkr016.otpbridge.OTPBridgeApp
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
    val recentOTPs: StateFlow<List<OTPEntity>> = otpDao.getRecentOTPs()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        webSocketClient.onConnectionChanged = { connected ->
            (isConnected as MutableStateFlow).value = connected
        }

        OTNotificationListenerService.onOTPReceived = { otpMessage ->
            viewModelScope.launch {
                otpDao.insertOTP(
                    OTPEntity(
                        sender = otpMessage.sender,
                        otp = otpMessage.otp,
                        timestamp = otpMessage.timestamp
                    )
                )
            }
        }
    }

    fun connectToMac() {
        if (pairingManager.isPaired()) {
            webSocketClient.connect()
        }
    }

    fun completePairing(deviceId: String, publicKey: ByteArray, ip: String, port: Int) {
        pairingManager.completePairing(deviceId, publicKey, ip, port)
        (isPaired as MutableStateFlow).value = true
        webSocketClient.connect()
    }

    fun disconnect() {
        webSocketClient.disconnect()
    }

    fun clearPairing() {
        webSocketClient.disconnect()
        pairingManager.clearPairing()
        (isPaired as MutableStateFlow).value = false
    }
}
