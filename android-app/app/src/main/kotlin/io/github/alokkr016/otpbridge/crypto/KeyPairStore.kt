package io.github.alokkr016.otpbridge.crypto

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.UUID

class KeyPairStore(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("crypto_prefs", Context.MODE_PRIVATE)

    fun saveKeyPair(keyPair: KeyPair) {
        val pubKey = Base64.encodeToString(keyPair.public.encoded, Base64.NO_WRAP)
        val privKey = Base64.encodeToString(keyPair.private.encoded, Base64.NO_WRAP)
        prefs.edit()
            .putString("public_key", pubKey)
            .putString("private_key", privKey)
            .apply()
    }

    fun loadKeyPair(): KeyPair? {
        val pubKeyStr = prefs.getString("public_key", null) ?: return null
        val privKeyStr = prefs.getString("private_key", null) ?: return null
        val pubKeyBytes = Base64.decode(pubKeyStr, Base64.NO_WRAP)
        val privKeyBytes = Base64.decode(privKeyStr, Base64.NO_WRAP)
        val kf = KeyFactory.getInstance("X25519")
        val pub = kf.generatePublic(X509EncodedKeySpec(pubKeyBytes))
        val priv = kf.generatePrivate(PKCS8EncodedKeySpec(privKeyBytes))
        return KeyPair(pub, priv)
    }

    fun getDeviceId(): String {
        var id = prefs.getString("device_id", null)
        if (id == null) {
            id = UUID.randomUUID().toString()
            prefs.edit().putString("device_id", id).apply()
        }
        return id
    }

    fun savePairedDevice(deviceId: String, publicKey: ByteArray, ip: String, port: Int, sharedSecret: ByteArray) {
        prefs.edit()
            .putString("paired_device_id", deviceId)
            .putString("paired_public_key", Base64.encodeToString(publicKey, Base64.NO_WRAP))
            .putString("paired_ip", ip)
            .putInt("paired_port", port)
            .putString("shared_secret", Base64.encodeToString(sharedSecret, Base64.NO_WRAP))
            .putBoolean("is_paired", true)
            .apply()
    }

    fun getPairedDevice(): PairedDevice? {
        if (!prefs.getBoolean("is_paired", false)) return null
        return PairedDevice(
            deviceId = prefs.getString("paired_device_id", "") ?: "",
            publicKey = Base64.decode(prefs.getString("paired_public_key", "") ?: "", Base64.NO_WRAP),
            ip = prefs.getString("paired_ip", "") ?: "",
            port = prefs.getInt("paired_port", 8420),
            sharedSecret = Base64.decode(prefs.getString("shared_secret", "") ?: "", Base64.NO_WRAP)
        )
    }

    fun isPaired(): Boolean = prefs.getBoolean("is_paired", false)

    fun clearPairing() {
        prefs.edit().remove("paired_device_id").remove("paired_public_key")
            .remove("paired_ip").remove("paired_port").remove("shared_secret")
            .putBoolean("is_paired", false).apply()
    }
}

data class PairedDevice(
    val deviceId: String,
    val publicKey: ByteArray,
    val ip: String,
    val port: Int,
    val sharedSecret: ByteArray
)
