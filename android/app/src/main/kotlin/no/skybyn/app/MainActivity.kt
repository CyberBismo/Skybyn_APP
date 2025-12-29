package no.skybyn.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import android.media.RingtoneManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "no.skybyn.app/background_service"
    private val NOTIFICATION_CHANNEL = "no.skybyn.app/notification"
    private val INSTALLER_CHANNEL = "no.skybyn.app/installer"
    private val SYSTEM_SOUNDS_CHANNEL = "no.skybyn.app/system_sounds"
    private var mediaPlayer: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" -> {
                    startBackgroundService()
                    result.success("Background service started")
                }
                "stopBackgroundService" -> {
                    stopBackgroundService()
                    result.success("Background service stopped")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Method channel for notification intents
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNotificationType" -> {
                    val notificationType = intent.getStringExtra("websocket_message_type")
                    // Clear the intent after reading to prevent multiple triggers
                    if (notificationType != null) {
                        intent.removeExtra("websocket_message_type")
                    }
                    result.success(notificationType)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Method channel for APK installation
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath != null) {
                        val installResult = installApk(apkPath)
                        result.success(installResult)
                    } else {
                        result.error("INVALID_ARGUMENT", "APK path is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Method channel for system sounds
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_SOUNDS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystemSounds" -> {
                    try {
                        val sounds = getSystemSounds()
                        result.success(sounds)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get system sounds: ${e.message}", null)
                    }
                }
                "playSound" -> {
                    try {
                        val soundId = call.argument<String>("soundId")
                        if (soundId != null) {
                            playSystemSound(soundId)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Sound ID is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to play sound: ${e.message}", null)
                    }
                }
                "playCustomSound" -> {
                    try {
                        val filePath = call.argument<String>("filePath")
                        if (filePath != null) {
                            playCustomSound(filePath)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "File path is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to play custom sound: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun installApk(apkPath: String): Boolean {
        try {
            val file = File(apkPath)
            if (!file.exists()) {
                return false
            }
            
            val intent = Intent(Intent.ACTION_VIEW).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                
                val apkUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    // Use FileProvider for Android 7.0+
                    FileProvider.getUriForFile(
                        this@MainActivity,
                        "${applicationContext.packageName}.fileprovider",
                        file
                    )
                } else {
                    // Use file:// URI for older Android versions
                    Uri.fromFile(file)
                }
                
                setDataAndType(apkUri, "application/vnd.android.package-archive")
            }
            
            startActivity(intent)
            
            // Close the app after a short delay to allow installer to open
            // The installer will handle installation and the app will restart after completion
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                finishAffinity() // Close all activities
                System.exit(0) // Exit the app
            }, 500) // 500ms delay to ensure installer opens first
            
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }
    
    private fun handleNotificationIntent(intent: Intent?) {
        val notificationType = intent?.getStringExtra("websocket_message_type")
        if (notificationType != null) {
            android.util.Log.d("MainActivity", "Notification type received: $notificationType")
        }
    }

    private fun startBackgroundService() {
        try {
            val serviceIntent = Intent(this, BackgroundService::class.java)
            // Use startForegroundService on Android 8.0+ for long-running services
            // Android 12+ (API 31+) requires app to be in foreground to start foreground service
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // Android 12+ - only start if app is in foreground
                    // Check if we have a visible activity
                    if (isTaskRoot || hasWindowFocus()) {
                        startForegroundService(serviceIntent)
                    } else {
                        // If not in foreground, try regular startService (will fail but won't crash)
                        // The service will be started when app comes to foreground
                        android.util.Log.w("MainActivity", "Cannot start foreground service - app not in foreground")
                    }
                } else {
                    // Android 8.0-11 - can start foreground service normally
                    startForegroundService(serviceIntent)
                }
            } else {
                // Android 7.1 and below - use regular startService
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error starting background service: ${e.message}")
            // If foreground service start fails, try regular service (may not work on Android 12+)
            try {
                val serviceIntent = Intent(this, BackgroundService::class.java)
                startService(serviceIntent)
            } catch (e2: Exception) {
                android.util.Log.e("MainActivity", "Error starting regular service: ${e2.message}")
            }
        }
    }

    private fun stopBackgroundService() {
        val serviceIntent = Intent(this, BackgroundService::class.java)
        stopService(serviceIntent)
    }
    
    private fun getSystemSounds(): List<Map<String, String>> {
        val sounds = mutableListOf<Map<String, String>>()
        
        try {
            // Get notification sounds
            val notificationManager = RingtoneManager(this)
            notificationManager.setType(RingtoneManager.TYPE_NOTIFICATION)
            val notificationCursor = notificationManager.cursor
            
            if (notificationCursor != null && notificationCursor.moveToFirst()) {
                do {
                    val id = notificationCursor.getString(RingtoneManager.ID_COLUMN_INDEX)
                    val title = notificationCursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                    val uriString = notificationCursor.getString(RingtoneManager.URI_COLUMN_INDEX)
                    
                    // Construct the full URI
                    val fullUri = Uri.parse("$uriString/$id")
                    
                    sounds.add(mapOf(
                        "id" to "notification_$id",
                        "title" to title,
                        "uri" to fullUri.toString()
                    ))
                } while (notificationCursor.moveToNext())
            }
            
            // Get ringtone sounds (can also be used for notifications)
            val ringtoneManager = RingtoneManager(this)
            ringtoneManager.setType(RingtoneManager.TYPE_RINGTONE)
            val ringtoneCursor = ringtoneManager.cursor
            
            if (ringtoneCursor != null && ringtoneCursor.moveToFirst()) {
                do {
                    val id = ringtoneCursor.getString(RingtoneManager.ID_COLUMN_INDEX)
                    val title = ringtoneCursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                    val uriString = ringtoneCursor.getString(RingtoneManager.URI_COLUMN_INDEX)
                    
                    // Construct the full URI
                    val fullUri = Uri.parse("$uriString/$id")
                    
                    // Check if we already have this sound (avoid duplicates)
                    val existingSound = sounds.find { it["uri"] == fullUri.toString() }
                    if (existingSound == null) {
                        sounds.add(mapOf(
                            "id" to "ringtone_$id",
                            "title" to title,
                            "uri" to fullUri.toString()
                        ))
                    }
                } while (ringtoneCursor.moveToNext())
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error getting system sounds: ${e.message}")
        }
        
        return sounds
    }
    
    private fun playSystemSound(soundId: String) {
        try {
            // Stop any currently playing sound
            mediaPlayer?.release()
            mediaPlayer = null
            
            if (soundId == "default") {
                // Use default notification sound
                val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                mediaPlayer = MediaPlayer.create(this, defaultSoundUri)
            } else {
                // Extract URI from sound ID
                val sounds = getSystemSounds()
                val sound = sounds.find { it["id"] == soundId }
                
                if (sound != null) {
                    val uri = Uri.parse(sound["uri"] ?: "")
                    mediaPlayer = MediaPlayer.create(this, uri)
                } else {
                    // Fallback to default
                    val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    mediaPlayer = MediaPlayer.create(this, defaultSoundUri)
                }
            }
            
            mediaPlayer?.let { player ->
                player.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                player.setOnCompletionListener { mp ->
                    mp.release()
                    mediaPlayer = null
                }
                player.start()
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error playing sound: ${e.message}")
            mediaPlayer?.release()
            mediaPlayer = null
        }
    }
    
    private fun playCustomSound(filePath: String) {
        try {
            // Stop any currently playing sound
            mediaPlayer?.release()
            mediaPlayer = null
            
            val file = File(filePath)
            if (!file.exists()) {
                android.util.Log.e("MainActivity", "Custom sound file does not exist: $filePath")
                // Fallback to default
                val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                mediaPlayer = MediaPlayer.create(this, defaultSoundUri)
            } else {
                // Use FileProvider for Android 7.0+ (API 24+)
                val fileUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        file
                    )
                } else {
                    Uri.fromFile(file)
                }
                mediaPlayer = MediaPlayer.create(this, fileUri)
            }
            
            mediaPlayer?.let { player ->
                player.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                player.setOnCompletionListener { mp ->
                    mp.release()
                    mediaPlayer = null
                }
                player.start()
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error playing custom sound: ${e.message}")
            mediaPlayer?.release()
            mediaPlayer = null
            // Fallback to default
            try {
                val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                mediaPlayer = MediaPlayer.create(this, defaultSoundUri)
                mediaPlayer?.start()
            } catch (e2: Exception) {
                android.util.Log.e("MainActivity", "Error playing default sound: ${e2.message}")
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        mediaPlayer?.release()
        mediaPlayer = null
    }
} 