package no.skybyn.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.os.Bundle

class MainActivity: FlutterActivity() {
    private val CHANNEL = "no.skybyn.app/background_service"

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