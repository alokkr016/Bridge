package io.github.alokkr016.otpbridge.database

import androidx.room.*

@Entity(tableName = "otp_messages")
data class OTPEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sender: String,
    val otp: String,
    val company: String? = null,
    val timestamp: Long,
    val synced: Boolean = false
)
