package io.github.alokkr016.otpbridge.database

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface OTPDao {
    @Query("SELECT * FROM otp_messages ORDER BY timestamp DESC LIMIT 50")
    fun getRecentOTPs(): Flow<List<OTPEntity>>

    @Insert
    suspend fun insertOTP(otp: OTPEntity)

    @Query("UPDATE otp_messages SET synced = 1 WHERE id = :id")
    suspend fun markSynced(id: Long)

    @Query("DELETE FROM otp_messages WHERE timestamp < :before")
    suspend fun deleteOlderThan(before: Long)

    @Query("DELETE FROM otp_messages")
    suspend fun deleteAll()
}
