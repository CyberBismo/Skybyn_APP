package no.skybyn.app

import android.app.*
import android.content.Intent
import android.content.Context
import android.os.IBinder
import android.os.Build
import androidx.core.app.NotificationCompat
import android.app.NotificationManager
import android.app.NotificationChannel
import android.util.Log

/**
 * Simplified BackgroundService - only handles foreground service for calls
 * All WebSocket and notification logic is handled by Flutter services:
 * - WebSocketService: Real-time chat when app is in foreground
 * - FirebaseMessagingService: Push notifications when app is closed/background
 * - WorkManager: Periodic message sync
 */
class BackgroundService : Service() {
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "skybyn_background_service"
    private val CHANNEL_NAME = "Skybyn Background Service"
    private val ADMIN_CHANNEL_ID = "admin_notifications"
    private val ADMIN_CHANNEL_NAME = "Admin Notifications"
    
    private var isRunning = false

    override fun onCreate() {
        super.onCreate()
        Log.d("BackgroundService", "onCreate called")
        createNotificationChannel()
        createAdminNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("BackgroundService", "Service started")
        
        if (!isRunning) {
            // Start as foreground service (required for long-running services on Android 8.0+)
            // This is only used during calls to keep the app active
            val notification = createNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            
            isRunning = true
            Log.d("BackgroundService", "Foreground service started for call")
        }
        
        return START_STICKY // Restart service if killed
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("BackgroundService", "Service destroyed")
        isRunning = false
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Delete existing channel if it exists to ensure clean state
            try {
                notificationManager.deleteNotificationChannel(CHANNEL_ID)
            } catch (e: Exception) {
                // Channel doesn't exist, that's fine
            }
            
            // Create channel with IMPORTANCE_LOW - minimal visibility but still shows in background activity list
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Skybyn running during calls"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
                enableLights(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(false)
            }
            
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

        // Create minimal notification for foreground service (required by Android)
        // This is only shown during calls
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Skybyn")
            .setContentText("")
            .setContentIntent(pendingIntent)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true) // REQUIRED: Foreground services must be ongoing
            .setAutoCancel(false) // REQUIRED: Cannot auto-cancel or service will be killed
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setLocalOnly(true)
            .build()
    }
    
    private fun createAdminNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ADMIN_CHANNEL_ID,
                ADMIN_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Important system notifications from administrators"
                setShowBadge(true)
                enableVibration(true)
                enableLights(true)
                lightColor = android.graphics.Color.parseColor("#2196F3")
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}
