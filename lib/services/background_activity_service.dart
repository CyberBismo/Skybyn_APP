import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'workmanager_callback.dart';

/// Background service to update user activity periodically
/// This keeps users appearing as "online" even when the app is fully closed
/// Similar to how Facebook/Messenger maintain online status
/// 
/// NOTE: WorkManager does NOT require a persistent notification.
/// It runs background tasks periodically without showing any notification.
class BackgroundActivityService {
  static const String _taskName = 'updateActivityTask';
  static const String _userIdKey = 'background_user_id';

  /// Initialize background activity updates using WorkManager
  /// WorkManager runs periodic tasks even when the app is fully closed
  /// No notification is required - it's a background task scheduler
  static Future<void> initialize() async {
    try {
      // Check if user is logged in
      final authService = AuthService();
      final userId = await authService.getStoredUserId();
      
      if (userId == null || userId.isEmpty) {
        // User not logged in, cancel any existing tasks
        await cancel();
        return;
      }

      // Store user ID for background task
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);

      // Initialize WorkManager with callback dispatcher
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      // Register periodic task to update activity every 15 minutes
      // Constraints ensure it runs even when device is idle or battery is low
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15), // Minimum 15 minutes on Android
        constraints: Constraints(
          networkType: NetworkType.connected, // Only when network is available
          requiresBatteryNotLow: false, // Run even on low battery
          requiresCharging: false, // Run even when not charging
          requiresDeviceIdle: false, // Run even when device is in use
          requiresStorageNotLow: false, // Run even when storage is low
        ),
        initialDelay: const Duration(minutes: 1), // Start after 1 minute
      );
      
    } catch (e) {
      // Don't throw - allow app to continue without background tasks
      // WorkManager may not be available on all devices or may have permission issues
    }
  }

  /// Cancel background activity updates
  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(_taskName);
    } catch (e) {
      // Silently fail
    }
  }
}

