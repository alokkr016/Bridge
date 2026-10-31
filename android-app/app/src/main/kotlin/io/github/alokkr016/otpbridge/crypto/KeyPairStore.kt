package io.github.alokkr016.otpbridge.crypto

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject
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

    fun savePairedDevice(
        deviceId: String,
        publicKey: ByteArray,
        ip: String,
        port: Int,
        sharedSecret: ByteArray,
        displayName: String? = null,
        kind: String? = null,
        pairingToken: String? = null
    ) {
        migrateLegacyIfNeeded()
        val devices = getPairedDevices().toMutableList()
        val idx = devices.indexOfFirst { it.deviceId == deviceId }
        val previous = devices.getOrNull(idx)
        val updated = PairedDevice(
            deviceId = deviceId,
            publicKey = publicKey,
            ip = ip,
            port = port,
            sharedSecret = sharedSecret,
            displayName = displayName?.takeIf { it.isNotBlank() } ?: previous?.displayName,
            kind = kind?.takeIf { it.isNotBlank() } ?: previous?.kind,
            pairingToken = pairingToken?.takeIf { it.isNotBlank() } ?: previous?.pairingToken,
            sendSeq = if (previous != null && previous.publicKey.contentEquals(publicKey)) previous.sendSeq else 0L,
            recvSeq = if (previous != null && previous.publicKey.contentEquals(publicKey)) previous.recvSeq else 0L
        )
        if (idx >= 0) devices[idx] = updated else devices.add(updated)
        persist(devices)
        Log.d(TAG, "Saved peer ${updated.label} ($deviceId) @ $ip:$port (total=${devices.size})")
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
                            sharedSecret = Base64.decode(o.getString("sharedSecret"), Base64.NO_WRAP),
                            displayName = o.optString("displayName").takeIf { it.isNotBlank() },
                            kind = o.optString("kind").takeIf { it.isNotBlank() },
                            pairingToken = o.optString("pairingToken").takeIf { it.isNotBlank() },
                            sendSeq = o.optLong("sendSeq"),
                            recvSeq = o.optLong("recvSeq")
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

    /**
     * Apply a discovered LAN IP only to the peer that owns [deviceId].
     * Never rewrite "the only peer" from an anonymous beacon — that used to
     * point the iPad pairing at the Mac's IP (and vice versa).
     */
    fun applyDiscoveredIp(newIP: String, deviceId: String? = null): PairedDevice? {
        val devices = getPairedDevices()
        if (devices.isEmpty()) return null
        val id = deviceId?.trim().orEmpty()
        if (id.isEmpty()) return null
        val compact = id.replace("-", "")
        val target = devices.find {
            it.deviceId.equals(id, ignoreCase = true) ||
                it.deviceId.replace("-", "").startsWith(compact, ignoreCase = true)
        } ?: return null
        if (target.ip == newIP) return null
        updateDeviceIp(target.deviceId, newIP)
        return target.copy(ip = newIP)
    }

    fun clearPairingToken(deviceId: String) {
        val devices = getPairedDevices().toMutableList()
        val idx = devices.indexOfFirst { it.deviceId == deviceId }
        if (idx < 0 || devices[idx].pairingToken == null) return
        devices[idx] = devices[idx].copy(pairingToken = null)
        persist(devices)
    }

    @Synchronized
    fun allocateSendSeq(deviceId: String): Long {
        val devices = getPairedDevices().toMutableList()
        val idx = devices.indexOfFirst { it.deviceId == deviceId }
        if (idx < 0) return 1L
        val next = devices[idx].sendSeq + 1L
        devices[idx] = devices[idx].copy(sendSeq = next)
        persist(devices)
        return next
    }

    @Synchronized
    fun acceptRecvSeq(deviceId: String, seq: Long): Boolean {
        if (seq <= 0L) return false
        val devices = getPairedDevices().toMutableList()
        val idx = devices.indexOfFirst { it.deviceId == deviceId }
        if (idx < 0) return false
        if (seq <= devices[idx].recvSeq) return false
        devices[idx] = devices[idx].copy(recvSeq = seq)
        persist(devices)
        return true
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
                    .put("displayName", d.displayName ?: "")
                    .put("kind", d.kind ?: "")
                    .put("pairingToken", d.pairingToken ?: "")
                    .put("sendSeq", d.sendSeq)
                    .put("recvSeq", d.recvSeq)
            )
        }
        prefs.edit()
            .putString(KEY_DEVICES, arr.toString())
            .putBoolean("is_paired", devices.isNotEmpty())
            .commit()
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
                    secure.edit().putBoolean(MIGRATED, true).apply()
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
    val displayName: String? = null,
    val kind: String? = null,
    val pairingToken: String? = null,
    val sendSeq: Long = 0L,
    val recvSeq: Long = 0L
) {
    val kindLabel: String
        get() = when (kind?.lowercase()) {
            "mac" -> "Mac"
            "ipad" -> "iPad"
            else -> "Computer"
        }

    val label: String
        get() = displayName?.takeIf { it.isNotBlank() } ?: "Unnamed $kindLabel"

    override fun equals(other: Any?): Boolean =
        other is PairedDevice && other.deviceId == deviceId

    override fun hashCode(): Int = deviceId.hashCode()
}
