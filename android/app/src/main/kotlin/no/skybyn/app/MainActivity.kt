package no.skybyn.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.os.Bundle

class MainActivity: FlutterActivity() {
    private val CHANNEL = "no.skybyn.app/background_service"
    private val NOTIFICATION_CHANNEL = "no.skybyn.app/notification"

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
    }
    
    private fun handleNotificationIntent(intent: Intent?) {
        val notificationType = intent?.getStringExtra("websocket_message_type")
        if (notificationType != null) {
            android.util.Log.d("MainActivity", "Notification type received: $notificationType")
        }
    }

    private fun startBackgroundService() {
        val serviceIntent = Intent(this, BackgroundService::class.java)
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