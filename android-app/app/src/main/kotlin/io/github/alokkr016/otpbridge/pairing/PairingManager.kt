package io.github.alokkr016.otpbridge.pairing

import android.content.Context
import android.util.Log
import io.github.alokkr016.otpbridge.crypto.CryptoManager
import io.github.alokkr016.otpbridge.crypto.KeyPairStore
import io.github.alokkr016.otpbridge.crypto.PairedDevice

class PairingManager(context: Context) {

    private val cryptoManager = CryptoManager(context)
    private val keyPairStore = KeyPairStore(context)

    fun isPaired(): Boolean = keyPairStore.isPaired()

    fun getDeviceId(): String = cryptoManager.getDeviceId()

    fun completePairing(
        deviceId: String,
        publicKeyBytes: ByteArray,
        ip: String,
        port: Int,
        displayName: String? = null,
        kind: String? = null,
        pairingToken: String? = null
    ) {
        Log.d("PairingManager", "completePairing: deviceId=$deviceId ip=$ip port=$port name=$displayName kind=$kind")
        val keyPair = cryptoManager.getOrCreateKeyPair()
        val theirPublicKey = cryptoManager.parsePublicKey(publicKeyBytes)
        val sharedSecret = cryptoManager.deriveSharedSecret(keyPair.private, theirPublicKey)
        keyPairStore.savePairedDevice(
            deviceId, publicKeyBytes, ip, port, sharedSecret, displayName, kind, pairingToken
        )
        Log.d("PairingManager", "Pairing saved (${keyPairStore.getPairedDevices().size} peers)")
    }

    fun clearPairing() {
        keyPairStore.clearPairing()
    }

    fun removeDevice(deviceId: String) {
        keyPairStore.removeDevice(deviceId)
    }

    fun getPairedDevice(): PairedDevice? = keyPairStore.getPairedDevice()

    fun getPairedDevices(): List<PairedDevice> = keyPairStore.getPairedDevices()
}
