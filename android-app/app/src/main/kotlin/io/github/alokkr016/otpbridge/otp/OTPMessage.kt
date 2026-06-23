package io.github.alokkr016.otpbridge.otp

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class OTPMessage(
    @SerialName("type") val type: String = "otp",
    @SerialName("sender") val sender: String,
    @SerialName("otp") val otp: String,
    @SerialName("timestamp") val timestamp: Long = System.currentTimeMillis()
)

@Serializable
data class HandshakeMessage(
    @SerialName("type") val type: String = "handshake",
    @SerialName("device_id") val deviceId: String,
    @SerialName("public_key") val publicKey: String
)

@Serializable
data class HandshakeAckMessage(
    @SerialName("type") val type: String = "handshake_ack",
    @SerialName("device_id") val deviceId: String,
    @SerialName("public_key") val publicKey: String
)
