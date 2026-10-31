package io.github.alokkr016.otpbridge.crypto

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.KeyFactory
import java.security.KeyPair
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.UUID

class KeyPairStore(context: Context) {

    private val prefs: SharedPreferences = openPrefs(context)

    fun saveKeyPair(keyPair: KeyPair) {
        val pubKey = Base64.encodeToString(keyPair.public.encoded, Base64.NO_WRAP)
        val privKey = Base64.encodeToString(keyPair.private.encoded, Base64.NO_WRAP)
        prefs.edit()
            .putString("public_key", pubKey)
            .putString("private_key", privKey)
            .commit()
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
            prefs.edit().putString("device_id", id).commit()
        }
        return id
    }

    fun savePairedDevice(
        deviceId: String,
        publicKey: ByteArray,
        ip: String,
        port: Int,
        sharedSecret: ByteArray,
        pairingToken: String? = null
    ) {
        val previous = getPairedDevice()
        val sameKey = previous != null && previous.publicKey.contentEquals(publicKey)
        prefs.edit()
            .putString("paired_device_id", deviceId)
            .putString("paired_public_key", Base64.encodeToString(publicKey, Base64.NO_WRAP))
            .putString("paired_ip", ip)
            .putInt("paired_port", port)
            .putString("shared_secret", Base64.encodeToString(sharedSecret, Base64.NO_WRAP))
            .putString("pairing_token", pairingToken ?: if (sameKey) previous?.pairingToken else null)
            .putLong("send_seq", if (sameKey) previous?.sendSeq ?: 0L else 0L)
            .putLong("recv_seq", if (sameKey) previous?.recvSeq ?: 0L else 0L)
            .putBoolean("is_paired", true)
            .commit()
    }

    fun getPairedDevice(): PairedDevice? {
        if (!prefs.getBoolean("is_paired", false)) return null
        val publicKey = prefs.getString("paired_public_key", null) ?: return null
        val secret = prefs.getString("shared_secret", null) ?: return null
        return PairedDevice(
            deviceId = prefs.getString("paired_device_id", "") ?: "",
            publicKey = Base64.decode(publicKey, Base64.NO_WRAP),
            ip = prefs.getString("paired_ip", "") ?: "",
            port = prefs.getInt("paired_port", 8420),
            sharedSecret = Base64.decode(secret, Base64.NO_WRAP),
            pairingToken = prefs.getString("pairing_token", null)?.takeIf { it.isNotBlank() },
            sendSeq = prefs.getLong("send_seq", 0L),
            recvSeq = prefs.getLong("recv_seq", 0L)
        )
    }

    fun clearPairingToken() {
        if (!prefs.contains("pairing_token")) return
        prefs.edit().remove("pairing_token").commit()
    }

    @Synchronized
    fun allocateSendSeq(): Long {
        val next = prefs.getLong("send_seq", 0L) + 1L
        prefs.edit().putLong("send_seq", next).commit()
        return next
    }

    @Synchronized
    fun acceptRecvSeq(seq: Long): Boolean {
        if (seq <= 0L) return false
        val current = prefs.getLong("recv_seq", 0L)
        if (seq <= current) return false
        prefs.edit().putLong("recv_seq", seq).commit()
        return true
    }

    fun isPaired(): Boolean = prefs.getBoolean("is_paired", false)

    fun clearPairing() {
        prefs.edit().remove("paired_device_id").remove("paired_public_key")
            .remove("paired_ip").remove("paired_port").remove("shared_secret")
            .remove("pairing_token").remove("send_seq").remove("recv_seq")
            .putBoolean("is_paired", false).commit()
    }

    companion object {
        private const val PLAIN_PREFS = "crypto_prefs"
        private const val SECURE_PREFS = "crypto_prefs_secure"
        private const val MIGRATED = "migrated_v1"

        private fun openPrefs(context: Context): SharedPreferences {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val secure = EncryptedSharedPreferences.create(
                context,
                SECURE_PREFS,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            val plain = context.getSharedPreferences(PLAIN_PREFS, Context.MODE_PRIVATE)
            if (!secure.getBoolean(MIGRATED, false)) {
                if (plain.all.isNotEmpty()) {
                    val editor = secure.edit()
                    for ((key, value) in plain.all) {
                        when (value) {
                            is String -> editor.putString(key, value)
                            is Boolean -> editor.putBoolean(key, value)
                            is Int -> editor.putInt(key, value)
                            is Long -> editor.putLong(key, value)
                            is Float -> editor.putFloat(key, value)
                        }
                    }
                    editor.putBoolean(MIGRATED, true).commit()
                    plain.edit().clear().commit()
                } else {
                    secure.edit().putBoolean(MIGRATED, true).commit()
                }
            }
            return secure
        }
    }
}

data class PairedDevice(
    val deviceId: String,
    val publicKey: ByteArray,
    val ip: String,
    val port: Int,
    val sharedSecret: ByteArray,
    val pairingToken: String? = null,
    val sendSeq: Long = 0L,
    val recvSeq: Long = 0L
)
