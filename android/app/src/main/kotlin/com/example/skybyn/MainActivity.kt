package com.example.skybyn

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "auto_update_permissions"
    private val REQUEST_INSTALL_PERMISSION = 1001

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkInstallPermission" -> {
                    result.success(checkInstallPermission())
                }
                "requestInstallPermission" -> {
                    requestInstallPermission(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkInstallPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Android 8.0+ uses REQUEST_INSTALL_PACKAGES permission
            ContextCompat.checkSelfPermission(this, Manifest.permission.REQUEST_INSTALL_PACKAGES) == PackageManager.PERMISSION_GRANTED
        } else {
            // Android 7.1 and below check if unknown sources is enabled
            Settings.Secure.getInt(contentResolver, Settings.Secure.INSTALL_NON_MARKET_APPS, 0) == 1
        }
    }

    private fun requestInstallPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Request REQUEST_INSTALL_PACKAGES permission
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.REQUEST_INSTALL_PACKAGES) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.REQUEST_INSTALL_PACKAGES), REQUEST_INSTALL_PERMISSION)
                // Store the result callback to handle the permission result
                permissionResultCallback = result
            } else {
                result.success(true)
            }
        } else {
            // For older versions, guide user to enable unknown sources
            try {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                intent.data = Uri.parse("package:$packageName")
                startActivityForResult(intent, REQUEST_INSTALL_PERMISSION)
                // Store the result callback to handle the activity result
                permissionResultCallback = result
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }

    private var permissionResultCallback: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == REQUEST_INSTALL_PERMISSION) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionResultCallback?.success(granted)
            permissionResultCallback = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == REQUEST_INSTALL_PERMISSION) {
            val granted = checkInstallPermission()
            permissionResultCallback?.success(granted)
            permissionResultCallback = null
        }
    }
}
