package no.skybyn.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "no.skybyn.app/background_service"
    private val NOTIFICATION_CHANNEL = "no.skybyn.app/notification"
    private val INSTALLER_CHANNEL = "no.skybyn.app/installer"
    private val FLOATING_BUBBLE_CHANNEL = "no.skybyn.app/floating_bubble"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleNotificationIntent(intent)
        handleChatIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
        handleChatIntent(intent)
    }
    
    private fun handleChatIntent(intent: Intent?) {
        val openChat = intent?.getBooleanExtra("open_chat", false) ?: false
        val friendId = intent?.getStringExtra("friendId")
        if (openChat && friendId != null) {
            // Navigate to chat screen - this will be handled by Flutter routing
            // The friendId will be passed to Flutter via method channel if needed
            android.util.Log.d("MainActivity", "Opening chat for friend: $friendId")
        }
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
        
        // Method channel for floating bubble
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FLOATING_BUBBLE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showBubble" -> {
                    val friendId = call.argument<String>("friendId")
                    val friendName = call.argument<String>("friendName")
                    val avatarUrl = call.argument<String>("avatarUrl")
                    val unreadCount = call.argument<Int>("unreadCount") ?: 0
                    val message = call.argument<String>("message")
                    
                    if (friendId != null && friendName != null) {
                        showFloatingBubble(friendId, friendName, avatarUrl, unreadCount, message)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "friendId and friendName are required", null)
                    }
                }
                "updateBubble" -> {
                    val friendId = call.argument<String>("friendId")
                    val friendName = call.argument<String>("friendName")
                    val avatarUrl = call.argument<String>("avatarUrl")
                    val unreadCount = call.argument<Int>("unreadCount") ?: 0
                    val message = call.argument<String>("message")
                    
                    if (friendId != null && friendName != null) {
                        updateFloatingBubble(friendId, friendName, avatarUrl, unreadCount, message)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "friendId and friendName are required", null)
                    }
                }
                "hideBubble" -> {
                    hideFloatingBubble()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun showFloatingBubble(friendId: String, friendName: String, avatarUrl: String?, unreadCount: Int, message: String?) {
        val intent = Intent(this, FloatingBubbleService::class.java).apply {
            action = "SHOW_BUBBLE"
            putExtra("friendId", friendId)
            putExtra("friendName", friendName)
            putExtra("avatarUrl", avatarUrl ?: "")
            putExtra("unreadCount", unreadCount)
            putExtra("message", message ?: "")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
    
    private fun updateFloatingBubble(friendId: String, friendName: String, avatarUrl: String?, unreadCount: Int, message: String?) {
        val intent = Intent(this, FloatingBubbleService::class.java).apply {
            action = "UPDATE_BUBBLE"
            putExtra("friendId", friendId)
            putExtra("friendName", friendName)
            putExtra("avatarUrl", avatarUrl ?: "")
            putExtra("unreadCount", unreadCount)
            putExtra("message", message ?: "")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
    
    private fun hideFloatingBubble() {
        val intent = Intent(this, FloatingBubbleService::class.java).apply {
            action = "HIDE_BUBBLE"
        }
        stopService(intent)
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
        val serviceIntent = Intent(this, BackgroundService::class.java)
        // Use startForegroundService on Android 8.0+ for long-running services
        // The service will handle making the notification invisible
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopBackgroundService() {
        val serviceIntent = Intent(this, BackgroundService::class.java)
        stopService(serviceIntent)
    }
} 