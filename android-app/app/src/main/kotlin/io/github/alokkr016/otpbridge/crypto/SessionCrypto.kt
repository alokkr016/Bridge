package io.github.alokkr016.otpbridge.crypto

import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Shared session cryptography. Android, Mac, and iPad must derive the same
 * bytes, so this is a straight RFC 5869 HKDF-SHA256 with fixed labels.
 */
object SessionCrypto {

    private val SALT = "otpbridge-hkdf-salt-v2".toByteArray(Charsets.UTF_8)
    private val INFO_LABEL = "otpbridge-session-v2".toByteArray(Charsets.UTF_8)

    fun deriveKey(rawSecret: ByteArray, myPublicKey: ByteArray, theirPublicKey: ByteArray): ByteArray {
        return hkdfSha256(rawSecret, SALT, info(myPublicKey, theirPublicKey), 32)
    }

    fun beaconMessage(ip: String, port: Int, deviceId: String): String =
        "OTPBRIDGE $ip $port $deviceId"

    fun beaconMac(sharedSecret: ByteArray, ip: String, port: Int, deviceId: String): String {
        val mac = hmacSha256(sharedSecret, beaconMessage(ip, port, deviceId).toByteArray(Charsets.UTF_8))
        return mac.joinToString("") { "%02x".format(it) }
    }

    fun signedBeacon(sharedSecret: ByteArray, ip: String, port: Int, deviceId: String): String {
        val message = beaconMessage(ip, port, deviceId)
        return "$message ${beaconMac(sharedSecret, ip, port, deviceId)}"
    }

    fun constantTimeEquals(a: String, b: String): Boolean {
        return MessageDigest.isEqual(
            a.toByteArray(Charsets.UTF_8),
            b.toByteArray(Charsets.UTF_8)
        )
    }

    /**
     * RFC 5869 HKDF-SHA256. Exposed so a known-answer test can pin the bytes
     * the Apple apps reproduce.
     */
    fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val extractKey = if (salt.isEmpty()) ByteArray(32) else salt
        val prk = hmacSha256(extractKey, ikm)
        val okm = ByteArray(length)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.update(previous)
            mac.update(info)
            mac.update(counter.toByte())
            previous = mac.doFinal()
            val take = minOf(previous.size, length - offset)
            System.arraycopy(previous, 0, okm, offset, take)
            offset += take
            counter++
        }
        return okm
    }

    private fun info(first: ByteArray, second: ByteArray): ByteArray {
        val (left, right) = if (compare(first, second) <= 0) first to second else second to first
        val out = ByteArray(INFO_LABEL.size + 1 + left.size + right.size)
        System.arraycopy(INFO_LABEL, 0, out, 0, INFO_LABEL.size)
        var cursor = INFO_LABEL.size
        out[cursor] = 0
        cursor++
        System.arraycopy(left, 0, out, cursor, left.size)
        cursor += left.size
        System.arraycopy(right, 0, out, cursor, right.size)
        return out
    }

    private fun compare(a: ByteArray, b: ByteArray): Int {
        val n = minOf(a.size, b.size)
        for (i in 0 until n) {
            val diff = (a[i].toInt() and 0xFF) - (b[i].toInt() and 0xFF)
            if (diff != 0) return diff
        }
        return a.size - b.size
    }

    private fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }
}
