import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'auto_update_service.dart';
import '../widgets/update_dialog.dart';
import '../main.dart';

class BackgroundUpdateScheduler {
  static final BackgroundUpdateScheduler _instance = BackgroundUpdateScheduler._internal();
  factory BackgroundUpdateScheduler() => _instance;
  BackgroundUpdateScheduler._internal();

  static const String _cachedUpdateKey = 'cached_app_update';
  static const String _lastUpdateCheckKey = 'last_update_check';
  static const int _updateCheckNotificationId = 8888;

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Initialize the background update scheduler
  Future<void> initialize() async {
    try {
      // Initialize timezone data
      tz.initializeTimeZones();

      // Schedule daily update checks at noon
      await _scheduleDailyUpdateCheck();

      // Check for cached update on startup
      await _checkCachedUpdate();
    } catch (e) {
    }
  }

  /// Schedule a daily update check at noon local time
  Future<void> _scheduleDailyUpdateCheck() async {
    try {
      // Cancel any existing scheduled notification
      await _localNotifications.cancel(_updateCheckNotificationId);

      // Calculate next noon
      final now = DateTime.now();
      final nextNoon = _getNextNoon(now);
      // Create notification channel for update checks (Android only)
      final androidImplementation = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        const AndroidNotificationChannel updateCheckChannel = AndroidNotificationChannel(
          'update_check',
          'Update Check',
          description: 'Background update checks',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        );
        await androidImplementation.createNotificationChannel(updateCheckChannel);
      }

      // Schedule notification that will trigger the update check
      // Note: On iOS, this will only work if the app is in foreground or background
      // For true background execution, we'd need WorkManager (Android) or Background Fetch (iOS)
      final tzDateTime = tz.TZDateTime.from(nextNoon, tz.local);

      // Create a silent notification that triggers the update check
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'update_check',
        'Update Check',
        channelDescription: 'Background update checks',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: false,
        playSound: false,
        enableVibration: false,
        silent: true,
      );

      const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iOSDetails,
      );

      try {
        await _localNotifications.zonedSchedule(
          _updateCheckNotificationId,
          'Update Check', // Title (won't be shown for silent notification on Android)
          'Checking for updates...', // Body (won't be shown for silent notification on Android)
          tzDateTime,
          notificationDetails,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'update_check',
        );
      } on PlatformException catch (e) {
        // Handle exact alarms permission error gracefully
        if (e.code == 'exact_alarms_not_permitted') {
          // Try without androidAllowWhileIdle for approximate scheduling
          try {
            await _localNotifications.zonedSchedule(
              _updateCheckNotificationId,
              'Update Check',
              'Checking for updates...',
              tzDateTime,
              notificationDetails,
              androidAllowWhileIdle: false, // Use approximate scheduling
              uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
              payload: 'update_check',
            );
          } catch (e2) {
          }
        } else {
          rethrow;
        }
      }

      // Also set up a periodic check using a timer when app is in foreground
      // This ensures we check even if scheduled notifications don't fire
      _setupPeriodicCheck();
    } catch (e) {
    }
  }

  /// Calculate the next noon time from the given date
  DateTime _getNextNoon(DateTime now) {
    final noon = DateTime(now.year, now.month, now.day, 12, 0, 0);
    
    // If it's already past noon today, schedule for tomorrow
    if (now.isAfter(noon)) {
      return noon.add(const Duration(days: 1));
    }
    
    // Otherwise, schedule for today at noon
    return noon;
  }

  /// Set up a periodic check that runs at noon each day
  /// This runs when the app is in foreground
  void _setupPeriodicCheck() {
    // Check immediately if it's around noon and hasn't been checked today
    _performUpdateCheckIfNeeded();

    // Set up a timer to check every hour to catch noon
    // This ensures we check at noon even if the app is running
    Timer.periodic(const Duration(hours: 1), (timer) {
      _performUpdateCheckIfNeeded();
    });
  }

  /// Perform update check if needed (at noon and not already checked today)
  Future<void> _performUpdateCheckIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckTimestamp = prefs.getInt(_lastUpdateCheckKey) ?? 0;
      final lastCheckDate = lastCheckTimestamp > 0 
          ? DateTime.fromMillisecondsSinceEpoch(lastCheckTimestamp)
          : DateTime(1970);
      final now = DateTime.now();

      // Check if we've already checked today
      if (lastCheckDate.year == now.year && 
          lastCheckDate.month == now.month && 
          lastCheckDate.day == now.day) {
        return; // Already checked today
      }

      // Check if it's around noon (11:30 AM - 12:30 PM)
      final currentHour = now.hour;
      final currentMinute = now.minute;
      if (currentHour == 11 && currentMinute < 30) {
        return; // Too early
      }
      if (currentHour == 12 && currentMinute > 30) {
        return; // Too late
      }
      if (currentHour != 11 && currentHour != 12) {
        return; // Not around noon
      }
      // Perform the update check
      await _checkForUpdates();

      // Update last check timestamp
      await prefs.setInt(_lastUpdateCheckKey, now.millisecondsSinceEpoch);
    } catch (e) {
    }
  }

  /// Check for updates and cache if available
  Future<void> _checkForUpdates() async {
    try {
      final updateInfo = await AutoUpdateService.checkForUpdates();

      if (updateInfo != null && updateInfo.isAvailable) {
        // Cache the update info
        await _cacheUpdate(updateInfo);
      } else {
        // Clear any cached update if no update is available
        await _clearCachedUpdate();
      }
    } catch (e) {
    }
  }

  /// Cache update info to show when app opens
  Future<void> _cacheUpdate(UpdateInfo updateInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final cacheData = {
        'currentVersion': currentVersion,
        'latestVersion': updateInfo.version,
        'releaseNotes': updateInfo.releaseNotes,
        'downloadUrl': updateInfo.downloadUrl,
        'cachedAt': DateTime.now().toIso8601String(),
      };

      await prefs.setString(_cachedUpdateKey, json.encode(cacheData));
    } catch (e) {
    }
  }

  /// Get cached update info
  Future<Map<String, dynamic>?> _getCachedUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cachedUpdateKey);

      if (cachedData == null) {
        return null;
      }

      final data = json.decode(cachedData) as Map<String, dynamic>;
      
      // Check if cache is still valid (not older than 7 days)
      final cachedAt = DateTime.parse(data['cachedAt'] as String);
      final now = DateTime.now();
      if (now.difference(cachedAt).inDays > 7) {
        await _clearCachedUpdate();
        return null;
      }

      return data;
    } catch (e) {
      return null;
    }
  }

  /// Clear cached update
  Future<void> _clearCachedUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedUpdateKey);
    } catch (e) {
    }
  }

  /// Check for cached update on app startup and show dialog if available
  Future<void> _checkCachedUpdate() async {

    try {
      final cachedData = await _getCachedUpdate();

      if (cachedData == null) {
        return;
      }

      // Check if we've already shown this version
      final latestVersion = cachedData['latestVersion'] as String;
      final hasShown = await AutoUpdateService.hasShownUpdateForVersion(latestVersion);

      if (hasShown) {
        return;
      }

      // Wait a bit for the app to fully initialize
      await Future.delayed(const Duration(seconds: 2));

      // Show update dialog
      final navigator = navigatorKey.currentState;
      if (navigator != null && !AutoUpdateService.isDialogShowing) {
        AutoUpdateService.setDialogShowing(true);
        await showDialog(
          context: navigator.context,
          barrierDismissible: false,
          builder: (context) => UpdateDialog(
            currentVersion: cachedData['currentVersion'] as String,
            latestVersion: latestVersion,
            releaseNotes: cachedData['releaseNotes'] as String? ?? '',
            downloadUrl: cachedData['downloadUrl'] as String? ?? '',
          ),
        ).then((_) {
          AutoUpdateService.setDialogShowing(false);
        });

        // Mark as shown and clear cache
        await AutoUpdateService.markUpdateShownForVersion(latestVersion);
        await _clearCachedUpdate();
      }
    } catch (e) {
    }
  }

  /// Manually trigger an update check (can be called from notification tap)
  Future<void> triggerUpdateCheck() async {
    await _checkForUpdates();
    // After checking, check if we should show the cached update
    await _checkCachedUpdate();
  }
}

