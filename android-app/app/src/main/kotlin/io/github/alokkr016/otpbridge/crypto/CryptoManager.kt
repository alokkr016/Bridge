package io.github.alokkr016.otpbridge.crypto

import android.content.Context
import org.json.JSONObject
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class CryptoManager(context: Context) {

    private val keyPairStore = KeyPairStore(context)

    fun generateKeyPair(): KeyPair {
        val gen = KeyPairGenerator.getInstance("X25519")
        val keyPair = gen.generateKeyPair()
        keyPairStore.saveKeyPair(keyPair)
        return keyPair
    }

    fun getOrCreateKeyPair(): KeyPair {
        return keyPairStore.loadKeyPair() ?: generateKeyPair()
    }

    fun deriveSharedSecret(myPrivateKey: java.security.PrivateKey, theirPublicKey: java.security.PublicKey): ByteArray {
        val ka = KeyAgreement.getInstance("X25519")
        ka.init(myPrivateKey)
        ka.doPhase(theirPublicKey, true)
        val rawSecret = ka.generateSecret()
        val myPublic = getOrCreateKeyPair().public
        return SessionCrypto.deriveKey(rawSecret, raw32(myPublic), raw32(theirPublicKey))
    }

    fun seal(plaintext: ByteArray, aesKey: ByteArray, seq: Long): ByteArray {
        val wrapper = JSONObject()
            .put("v", 2)
            .put("seq", seq)
            .put("body", String(plaintext, Charsets.UTF_8))
        return encrypt(wrapper.toString().toByteArray(Charsets.UTF_8), aesKey)
    }

    fun open(data: ByteArray, aesKey: ByteArray): OpenedFrame {
        val outer = JSONObject(String(decrypt(data, aesKey), Charsets.UTF_8))
        if (outer.optInt("v") != 2) throw IllegalArgumentException("unsupported frame")
        val seq = outer.getLong("seq")
        if (seq <= 0L) throw IllegalArgumentException("bad sequence")
        val body = outer.getString("body").toByteArray(Charsets.UTF_8)
        return OpenedFrame(seq, body)
    }

    private fun raw32(key: java.security.Key): ByteArray {
        val encoded = key.encoded
        return if (encoded.size >= 32) encoded.copyOfRange(encoded.size - 32, encoded.size) else encoded
    }

    fun encrypt(plaintext: ByteArray, aesKey: ByteArray): ByteArray {
        val key = SecretKeySpec(aesKey, "AES")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val nonce = ByteArray(12)
        SecureRandom().nextBytes(nonce)
        val spec = GCMParameterSpec(128, nonce)
        cipher.init(Cipher.ENCRYPT_MODE, key, spec)
        val ciphertext = cipher.doFinal(plaintext)
        // Wire format: [12-byte nonce][ciphertext+tag] — no inner length prefix
        // The outer TCP frame length is added by sendFrame() in WebSocketClient.
        val result = ByteArray(nonce.size + ciphertext.size)
        System.arraycopy(nonce, 0, result, 0, nonce.size)
        System.arraycopy(ciphertext, 0, result, nonce.size, ciphertext.size)
        return result
    }

    fun decrypt(data: ByteArray, aesKey: ByteArray): ByteArray {
        val nonce = data.copyOfRange(0, 12)
        val ciphertext = data.copyOfRange(12, data.size)
        val key = SecretKeySpec(aesKey, "AES")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(128, nonce)
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        return cipher.doFinal(ciphertext)
    }

    fun getPublicKey(): ByteArray {
        return getOrCreateKeyPair().public.encoded
    }

    fun getDeviceId(): String {
        return keyPairStore.getDeviceId()
    }

    fun parsePublicKey(encoded: ByteArray): java.security.PublicKey {
        val kf = KeyFactory.getInstance("X25519")
        if (encoded.size == 32) {
            val wrapped = ByteArray(44)
            wrapped[0] = 0x30; wrapped[1] = 0x2A; wrapped[2] = 0x30; wrapped[3] = 0x05
            wrapped[4] = 0x06; wrapped[5] = 0x03; wrapped[6] = 0x2B; wrapped[7] = 0x65
            wrapped[8] = 0x6E; wrapped[9] = 0x03; wrapped[10] = 0x21; wrapped[11] = 0x00
            System.arraycopy(encoded, 0, wrapped, 12, 32)
            return kf.generatePublic(java.security.spec.X509EncodedKeySpec(wrapped))
        }
        return kf.generatePublic(java.security.spec.X509EncodedKeySpec(encoded))
    }
}

data class OpenedFrame(val seq: Long, val body: ByteArray)
