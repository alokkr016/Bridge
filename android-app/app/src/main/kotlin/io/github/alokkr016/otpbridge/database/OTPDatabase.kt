package io.github.alokkr016.otpbridge.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(entities = [OTPEntity::class], version = 2, exportSchema = false)
abstract class OTPDatabase : RoomDatabase() {
    abstract fun otpDao(): OTPDao

    companion object {
        @Volatile
        private var INSTANCE: OTPDatabase? = null

        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE otp_messages ADD COLUMN company TEXT")
            }
        }

        fun getDatabase(context: Context): OTPDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    OTPDatabase::class.java,
                    "otp_bridge_database"
                )
                    .addMigrations(MIGRATION_1_2)
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
