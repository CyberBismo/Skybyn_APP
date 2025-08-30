import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/permission_dialog.dart';

class AutoUpdateService {
  static final AutoUpdateService _instance = AutoUpdateService._internal();
  factory AutoUpdateService() => _instance;
  AutoUpdateService._internal();

  bool _isInitialized = false;
  bool _isCheckingForUpdates = false;

  /// Initialize the auto-update service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Only enable for Android
      if (Platform.isAndroid) {
        // For now, we'll just mark as initialized
        // Firebase App Distribution will be added when properly configured
        _isInitialized = true;
        print('✅ [AutoUpdate] Service initialized successfully');
        print('ℹ️ [AutoUpdate] Firebase App Distribution not yet configured');
        print('ℹ️ [AutoUpdate] Auto-updates will be disabled until configured');
      } else {
        print('ℹ️ [AutoUpdate] Service skipped for non-Android platform');
      }
    } catch (e) {
      print('❌ [AutoUpdate] Failed to initialize: $e');
    }
  }

  /// Check for available updates
  Future<bool> checkForUpdates({bool showDialog = true, BuildContext? context}) async {
    if (!_isInitialized || !Platform.isAndroid || _isCheckingForUpdates) {
      return false;
    }

    _isCheckingForUpdates = true;
    
    try {
      print('🔄 [AutoUpdate] Checking for updates...');
      
      // Check if we have permission to install from unknown sources
      if (!await _checkInstallPermission()) {
        print('⚠️ [AutoUpdate] No permission to install from unknown sources');
        
        // Show permission dialog if context is available
        if (context != null) {
          print('🔄 [AutoUpdate] Showing permission dialog...');
          final bool userGranted = await _showPermissionDialog(context);
          if (!userGranted) {
            print('❌ [AutoUpdate] User denied permission - update check skipped');
            return false;
          }
        }
        
        print('🔄 [AutoUpdate] Requesting system permission...');
        // Try to request permission
        final bool permissionGranted = await _requestInstallPermission();
        if (!permissionGranted) {
          print('❌ [AutoUpdate] System permission denied - update check skipped');
          return false;
        }
        
        print('✅ [AutoUpdate] Permission granted - continuing with update check');
      }
      
      // For now, Firebase App Distribution is not configured
      // This will be implemented when Firebase is properly set up
      print('ℹ️ [AutoUpdate] Firebase App Distribution not yet configured');
      print('ℹ️ [AutoUpdate] No updates available until configured');
      
      return false;
    } catch (e) {
      print('❌ [AutoUpdate] Error checking for updates: $e');
      return false;
    } finally {
      _isCheckingForUpdates = false;
    }
  }

  /// Start the update process
  Future<void> startUpdate() async {
    if (!_isInitialized || !Platform.isAndroid) return;
    
    try {
      print('🚀 [AutoUpdate] Starting update...');
      print('ℹ️ [AutoUpdate] Firebase App Distribution not yet configured');
      print('ℹ️ [AutoUpdate] Update process not available until configured');
    } catch (e) {
      print('❌ [AutoUpdate] Error starting update: $e');
      rethrow;
    }
  }

  /// Handle update progress
  void _handleUpdateProgress(dynamic progress) {
    // This will be implemented when Firebase App Distribution is configured
    print('ℹ️ [AutoUpdate] Update progress handling not yet configured');
  }

  /// Show update dialog to user
  Future<void> _showUpdateDialog(String currentVersion, String latestVersion, String? releaseNotes) async {
    // This will be called from the UI context
    // The actual dialog will be shown by the calling widget
    // For now, we'll just log the update availability
    print('📱 [AutoUpdate] Update available: $currentVersion -> $latestVersion');
    if (releaseNotes != null) {
      print('📝 [AutoUpdate] Release notes: $releaseNotes');
    }
  }

  /// Get release notes for the latest version
  Future<String?> _getReleaseNotes() async {
    // This will be implemented when Firebase App Distribution is configured
    return null;
  }

    /// Check if we have permission to install from unknown sources
  Future<bool> _checkInstallPermission() async {
    try {
      if (!Platform.isAndroid) return false;
      
      // Check if we can request package installs
      const platform = MethodChannel('auto_update_permissions');
      
      try {
        final bool hasPermission = await platform.invokeMethod('checkInstallPermission');
        print('ℹ️ [AutoUpdate] Install permission status: $hasPermission');
        return hasPermission;
      } on PlatformException catch (e) {
        print('⚠️ [AutoUpdate] Permission check failed: ${e.message}');
        // Fallback: assume permission is granted for now
        return true;
      }
    } catch (e) {
      print('❌ [AutoUpdate] Error checking install permission: $e');
      return false;
    }
  }

  /// Request permission to install from unknown sources
  Future<bool> _requestInstallPermission() async {
    try {
      if (!Platform.isAndroid) return false;
      
      const platform = MethodChannel('auto_update_permissions');
      
      try {
        final bool permissionGranted = await platform.invokeMethod('requestInstallPermission');
        print('ℹ️ [AutoUpdate] Install permission request result: $permissionGranted');
        return permissionGranted;
      } on PlatformException catch (e) {
        print('⚠️ [AutoUpdate] Permission request failed: ${e.message}');
        return false;
      }
    } catch (e) {
      print('❌ [AutoUpdate] Error requesting install permission: $e');
      return false;
    }
  }

  /// Show permission dialog to user
  Future<bool> _showPermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionDialog(
        onGranted: () {
          Navigator.of(context).pop(true);
        },
        onDenied: () {
          Navigator.of(context).pop(false);
        },
      ),
    ) ?? false;
  }

  /// Get current app version
  String getCurrentVersion() {
    // This will be implemented when Firebase App Distribution is configured
    return '1.0.0';
  }

  /// Get latest available version
  Future<String?> getLatestVersion() async {
    if (!_isInitialized || !Platform.isAndroid) return null;
    
    // This will be implemented when Firebase App Distribution is configured
    return null;
  }

  /// Check if update is in progress
  bool get isUpdateInProgress => _isCheckingForUpdates;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}
