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

    fun completePairing(deviceId: String, publicKeyBytes: ByteArray, ip: String, port: Int) {
        Log.d("PairingManager", "completePairing: deviceId=$deviceId ip=$ip port=$port keyLen=${publicKeyBytes.size}")
        val keyPair = cryptoManager.getOrCreateKeyPair()
        Log.d("PairingManager", "My public key length: ${keyPair.public.encoded.size}")
        val theirPublicKey = cryptoManager.parsePublicKey(publicKeyBytes)
        Log.d("PairingManager", "Parsed their public key: ${theirPublicKey.algorithm}")
        val sharedSecret = cryptoManager.deriveSharedSecret(keyPair.private, theirPublicKey)
        Log.d("PairingManager", "Derived shared secret: ${sharedSecret.size} bytes")
        keyPairStore.savePairedDevice(deviceId, publicKeyBytes, ip, port, sharedSecret)
        Log.d("PairingManager", "Pairing saved successfully")
    }

    fun clearPairing() {
        keyPairStore.clearPairing()
    }

    fun getPairedDevice() = keyPairStore.getPairedDevice()
}
