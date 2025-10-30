package no.skybyn.app

import android.app.*
import android.content.Intent
import android.os.IBinder
import android.os.Build
import androidx.core.app.NotificationCompat
import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.Context
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import android.os.Handler
import android.os.Looper

class BackgroundService : Service() {
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "skybyn_background_service"
    private val CHANNEL_NAME = "Skybyn Background Service"
    
    private var executor: ScheduledExecutorService? = null
    private var isRunning = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        executor = Executors.newScheduledThreadPool(1)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("BackgroundService", "Service started")
        
        if (!isRunning) {
            startForeground(NOTIFICATION_ID, createNotification())
            startBackgroundTasks()
            isRunning = true
            
            // Remove notification after 30 seconds
            Handler(Looper.getMainLooper()).postDelayed({
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
            }, 30000) // 30 seconds
        }
        
        return START_STICKY // Restart service if killed
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("BackgroundService", "Service destroyed")
        stopBackgroundTasks()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "" // "Keeps Skybyn running in background"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Skybyn")
            .setContentText("")
            .setSmallIcon(R.drawable.notification_icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(false)
            .build()
    }

    private fun startBackgroundTasks() {
        Log.d("BackgroundService", "Starting background tasks")
        
        // Schedule periodic task to keep service alive
        executor?.scheduleAtFixedRate({
            try {
                // Here you could implement actual background tasks
                // Service heartbeat removed to reduce log noise
            } catch (e: Exception) {
                Log.e("BackgroundService", "Error in background task: ${e.message}")
            }
        }, 0, 30, TimeUnit.SECONDS) // Run every 30 seconds
    }

    private fun stopBackgroundTasks() {
        Log.d("BackgroundService", "Stopping background tasks")
        executor?.shutdown()
        isRunning = false
    }
} 