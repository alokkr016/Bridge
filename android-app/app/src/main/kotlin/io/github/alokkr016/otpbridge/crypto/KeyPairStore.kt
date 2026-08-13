package io.github.alokkr016.otpbridge.crypto

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyFactory
import java.security.KeyPair
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
        migrateLegacyIfNeeded()
        val devices = getPairedDevices().toMutableList()
        val updated = PairedDevice(deviceId, publicKey, ip, port, sharedSecret)
        val idx = devices.indexOfFirst { it.deviceId == deviceId }
        if (idx >= 0) devices[idx] = updated else devices.add(updated)
        persist(devices)
        Log.d(TAG, "Saved peer $deviceId @ $ip:$port (total=${devices.size})")
    }

    fun getPairedDevices(): List<PairedDevice> {
        migrateLegacyIfNeeded()
        val raw = prefs.getString(KEY_DEVICES, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    add(
                        PairedDevice(
                            deviceId = o.getString("deviceId"),
                            publicKey = Base64.decode(o.getString("publicKey"), Base64.NO_WRAP),
                            ip = o.getString("ip"),
                            port = o.optInt("port", 8420),
                            sharedSecret = Base64.decode(o.getString("sharedSecret"), Base64.NO_WRAP)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse paired devices", e)
            emptyList()
        }
    }

    fun getPairedDevice(): PairedDevice? = getPairedDevices().firstOrNull()

    fun isPaired(): Boolean = getPairedDevices().isNotEmpty()

    fun removeDevice(deviceId: String) {
        persist(getPairedDevices().filter { it.deviceId != deviceId })
    }

    fun updateDeviceIp(deviceId: String, ip: String) {
        val devices = getPairedDevices().toMutableList()
        val idx = devices.indexOfFirst { it.deviceId == deviceId }
        if (idx < 0) return
        val d = devices[idx]
        if (d.ip == ip) return
        devices[idx] = d.copy(ip = ip)
        persist(devices)
        Log.d(TAG, "Updated IP for $deviceId → $ip")
    }

    /** BLE only gives us an IP. Update the single peer, or the one that already used this IP. */
    fun applyDiscoveredIp(newIP: String): PairedDevice? {
        val devices = getPairedDevices()
        if (devices.isEmpty()) return null
        if (devices.any { it.ip == newIP }) return null
        val target = if (devices.size == 1) devices.first() else return null
        updateDeviceIp(target.deviceId, newIP)
        return target.copy(ip = newIP)
    }

    fun clearPairing() {
        prefs.edit()
            .remove(KEY_DEVICES)
            .remove("paired_device_id")
            .remove("paired_public_key")
            .remove("paired_ip")
            .remove("paired_port")
            .remove("shared_secret")
            .putBoolean("is_paired", false)
            .apply()
    }

    private fun persist(devices: List<PairedDevice>) {
        val arr = JSONArray()
        for (d in devices) {
            arr.put(
                JSONObject()
                    .put("deviceId", d.deviceId)
                    .put("publicKey", Base64.encodeToString(d.publicKey, Base64.NO_WRAP))
                    .put("ip", d.ip)
                    .put("port", d.port)
                    .put("sharedSecret", Base64.encodeToString(d.sharedSecret, Base64.NO_WRAP))
            )
        }
        prefs.edit()
            .putString(KEY_DEVICES, arr.toString())
            .putBoolean("is_paired", devices.isNotEmpty())
            .apply()
    }

    private fun migrateLegacyIfNeeded() {
        if (prefs.contains(KEY_DEVICES)) return
        if (!prefs.getBoolean("is_paired", false)) {
            persist(emptyList())
            return
        }
        val id = prefs.getString("paired_device_id", null) ?: return persist(emptyList())
        val pk = prefs.getString("paired_public_key", null) ?: return persist(emptyList())
        val ip = prefs.getString("paired_ip", null) ?: return persist(emptyList())
        val secret = prefs.getString("shared_secret", null) ?: return persist(emptyList())
        val migrated = PairedDevice(
            deviceId = id,
            publicKey = Base64.decode(pk, Base64.NO_WRAP),
            ip = ip,
            port = prefs.getInt("paired_port", 8420),
            sharedSecret = Base64.decode(secret, Base64.NO_WRAP)
        )
        persist(listOf(migrated))
        Log.d(TAG, "Migrated legacy single pairing for $id")
    }

    companion object {
        private const val TAG = "KeyPairStore"
        private const val KEY_DEVICES = "paired_devices_json"
    }
}

data class PairedDevice(
    val deviceId: String,
    val publicKey: ByteArray,
    val ip: String,
    val port: Int,
    val sharedSecret: ByteArray
) {
    override fun equals(other: Any?): Boolean =
        other is PairedDevice && other.deviceId == deviceId

    override fun hashCode(): Int = deviceId.hashCode()
}
