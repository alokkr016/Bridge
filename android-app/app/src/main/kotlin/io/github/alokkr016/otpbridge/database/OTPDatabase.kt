package io.github.alokkr016.otpbridge.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [OTPEntity::class], version = 1, exportSchema = false)
abstract class OTPDatabase : RoomDatabase() {
    abstract fun otpDao(): OTPDao

    companion object {
        @Volatile
        private var INSTANCE: OTPDatabase? = null

        fun getDatabase(context: Context): OTPDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    OTPDatabase::class.java,
                    "otp_bridge_database"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}
