package io.github.alokkr016.otpbridge.pairing

import android.content.Context
import android.util.Log
import io.github.alokkr016.otpbridge.crypto.CryptoManager
import io.github.alokkr016.otpbridge.crypto.KeyPairStore

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
        pairingToken: String? = null
    ) {
        Log.d("PairingManager", "completePairing: deviceId=$deviceId ip=$ip port=$port keyLen=${publicKeyBytes.size}")
        val keyPair = cryptoManager.getOrCreateKeyPair()
        val theirPublicKey = cryptoManager.parsePublicKey(publicKeyBytes)
        val sharedSecret = cryptoManager.deriveSharedSecret(keyPair.private, theirPublicKey)
        keyPairStore.savePairedDevice(deviceId, publicKeyBytes, ip, port, sharedSecret, pairingToken)
    }

    fun clearPairing() {
        keyPairStore.clearPairing()
    }

    fun getPairedDevice() = keyPairStore.getPairedDevice()
}
