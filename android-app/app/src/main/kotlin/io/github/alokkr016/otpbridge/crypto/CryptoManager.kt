package io.github.alokkr016.otpbridge.crypto

import android.content.Context
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
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
        return ka.generateSecret()
    }

    fun encrypt(plaintext: ByteArray, sharedSecret: ByteArray): ByteArray {
        val key = SecretKeySpec(sharedSecret, "ChaCha20")
        val cipher = Cipher.getInstance("ChaCha20-Poly1305/None/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val nonce = cipher.iv
        val ciphertext = cipher.doFinal(plaintext)
        val result = ByteArray(4 + nonce.size + ciphertext.size)
        val len = ciphertext.size
        result[0] = (len shr 24).toByte()
        result[1] = (len shr 16).toByte()
        result[2] = (len shr 8).toByte()
        result[3] = len.toByte()
        System.arraycopy(nonce, 0, result, 4, nonce.size)
        System.arraycopy(ciphertext, 0, result, 4 + nonce.size, ciphertext.size)
        return result
    }

    fun decrypt(data: ByteArray, sharedSecret: ByteArray): ByteArray {
        val len = ((data[0].toInt() and 0xFF) shl 24) or
                ((data[1].toInt() and 0xFF) shl 16) or
                ((data[2].toInt() and 0xFF) shl 8) or
                (data[3].toInt() and 0xFF)
        val nonce = data.copyOfRange(4, 4 + 12)
        val ciphertext = data.copyOfRange(4 + 12, 4 + 12 + len)
        val key = SecretKeySpec(sharedSecret, "ChaCha20")
        val cipher = Cipher.getInstance("ChaCha20-Poly1305/None/NoPadding")
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
            wrapped[0] = 0x30
            wrapped[1] = 0x2A
            wrapped[2] = 0x30
            wrapped[3] = 0x05
            wrapped[4] = 0x06
            wrapped[5] = 0x03
            wrapped[6] = 0x2B
            wrapped[7] = 0x65
            wrapped[8] = 0x6E
            wrapped[9] = 0x03
            wrapped[10] = 0x21
            wrapped[11] = 0x00
            System.arraycopy(encoded, 0, wrapped, 12, 32)
            return kf.generatePublic(java.security.spec.X509EncodedKeySpec(wrapped))
        }
        return kf.generatePublic(java.security.spec.X509EncodedKeySpec(encoded))
    }
}
