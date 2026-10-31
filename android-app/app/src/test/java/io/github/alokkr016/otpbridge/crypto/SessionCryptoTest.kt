package io.github.alokkr016.otpbridge.crypto

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionCryptoTest {

    @Test
    fun hkdfMatchesRfc5869Case1() {
        val ikm = ByteArray(22) { 0x0b }
        val salt = byteArrayOf(
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c
        )
        val info = byteArrayOf(0xf0.toByte(), 0xf1.toByte(), 0xf2.toByte(), 0xf3.toByte(), 0xf4.toByte(), 0xf5.toByte(), 0xf6.toByte(), 0xf7.toByte(), 0xf8.toByte(), 0xf9.toByte())
        val expected = hex(
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
        )
        assertArrayEquals(expected, SessionCrypto.hkdfSha256(ikm, salt, info, 42))
    }

    @Test
    fun deriveKeyIsIndependentOfPublicKeyOrder() {
        val raw = ByteArray(32) { it.toByte() }
        val a = ByteArray(32) { (it + 1).toByte() }
        val b = ByteArray(32) { (it + 9).toByte() }
        assertArrayEquals(
            SessionCrypto.deriveKey(raw, a, b),
            SessionCrypto.deriveKey(raw, b, a)
        )
    }

    @Test
    fun beaconMacRejectsATamperedIp() {
        val secret = ByteArray(32) { 7 }
        val signed = SessionCrypto.signedBeacon(secret, "192.168.1.20", 8420, "device-1")
        val mac = signed.substringAfterLast(' ')
        assertTrue(SessionCrypto.constantTimeEquals(mac, SessionCrypto.beaconMac(secret, "192.168.1.20", 8420, "device-1")))
        assertFalse(SessionCrypto.constantTimeEquals(mac, SessionCrypto.beaconMac(secret, "192.168.1.21", 8420, "device-1")))
    }

    private fun hex(value: String): ByteArray =
        value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
