import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import '../config/constants.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:http/io_client.dart';

/// Background service to update user activity periodically
/// This keeps users appearing as "online" even when the app is closed
/// Similar to how Facebook/Messenger maintain online status
class BackgroundActivityService {
  static const String _taskName = 'updateActivityTask';
  static const String _userIdKey = 'background_user_id';

  /// Initialize background activity updates
  /// This sets up periodic background tasks to update user activity
  static Future<void> initialize() async {
    try {
      // Check if user is logged in
      final authService = AuthService();
      final userId = await authService.getStoredUserId();
      
      if (userId == null || userId.isEmpty) {
        print('ℹ️ [BackgroundActivity] No user logged in, skipping background activity setup');
        return;
      }

      // Store user ID for background task
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);

      // Initialize WorkManager
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      // Register periodic task to update activity every 5 minutes
      // This keeps users appearing as "online" for up to 5 minutes after app closes
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 5),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        initialDelay: const Duration(minutes: 1), // Start after 1 minute
      );

      print('✅ [BackgroundActivity] Background activity updates initialized');
    } catch (e) {
      print('❌ [BackgroundActivity] Error initializing background activity: $e');
    }
  }

  /// Cancel background activity updates
  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(_taskName);
      print('✅ [BackgroundActivity] Background activity updates cancelled');
    } catch (e) {
      print('❌ [BackgroundActivity] Error cancelling background activity: $e');
    }
  }
}

/// Background task callback
/// This runs in a separate isolate when the background task executes
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('🔄 [BackgroundActivity] Executing background activity update task');

      // Get user ID from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(BackgroundActivityService._userIdKey);

      if (userId == null || userId.isEmpty) {
        print('⚠️ [BackgroundActivity] No user ID found, skipping activity update');
        return Future.value(true);
      }

      // Update activity via API
      await _updateActivity(userId);

      print('✅ [BackgroundActivity] Activity updated successfully');
      return Future.value(true);
    } catch (e) {
      print('❌ [BackgroundActivity] Error in background task: $e');
      return Future.value(false);
    }
  });
}

/// Update user activity via API
Future<void> _updateActivity(String userId) async {
  try {
    // Create HTTP client with SSL handling
    HttpClient httpClient;
    if (HttpOverrides.current != null) {
      httpClient = HttpOverrides.current!.createHttpClient(null);
    } else {
      httpClient = HttpClient();
    }
    
    if (kDebugMode) {
      httpClient.badCertificateCallback = (cert, host, port) => true;
    }
    
    httpClient.userAgent = 'Skybyn-App/1.0';
    httpClient.connectionTimeout = const Duration(seconds: 10);
    final client = IOClient(httpClient);

    // Call update activity API
    final response = await client.post(
      Uri.parse(ApiConstants.updateActivity),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-API-Key': ApiConstants.apiKey,
      },
      body: {
        'userID': userId,
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = response.body;
      if (data.contains('"responseCode":"1"')) {
        print('✅ [BackgroundActivity] Activity updated successfully for user $userId');
      } else {
        print('⚠️ [BackgroundActivity] Activity update returned non-success: $data');
      }
    } else {
      print('⚠️ [BackgroundActivity] Activity update failed with status ${response.statusCode}');
    }
  } catch (e) {
    print('❌ [BackgroundActivity] Error updating activity: $e');
    rethrow;
  }
}

