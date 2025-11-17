import 'dart:async';
// import 'package:workmanager/workmanager.dart';  // Temporarily disabled due to compatibility issues
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
/// 
/// NOTE: Currently relies on push notifications for activity updates when app is closed.
/// WorkManager was disabled due to compatibility issues, but push notifications
/// will update activity when received, maintaining online status effectively.
class BackgroundActivityService {
  static const String _taskName = 'updateActivityTask';
  static const String _userIdKey = 'background_user_id';

  /// Initialize background activity updates
  /// Currently, we rely on push notifications to update activity when app is closed.
  /// When a push notification is received, it updates the user's last_active timestamp,
  /// which keeps them appearing as "online" for up to 5 minutes.
  static Future<void> initialize() async {
    try {
      // Check if user is logged in
      final authService = AuthService();
      final userId = await authService.getStoredUserId();
      
      if (userId == null || userId.isEmpty) {
        print('ℹ️ [BackgroundActivity] No user logged in, skipping background activity setup');
        return;
      }

      // Store user ID (may be used in future for other background tasks)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);

      // WorkManager is temporarily disabled due to compatibility issues
      // We rely on push notifications to update activity when app is closed
      // Push notifications already update activity in firebase_messaging_service.dart
      print('ℹ️ [BackgroundActivity] Using push notifications for activity updates');
      print('ℹ️ [BackgroundActivity] Activity will be updated when notifications are received');
      
      // Note: Push notifications already update activity in:
      // - firebase_messaging_service.dart (foreground and background handlers)
      // - api/firebase.php (when sending notifications)
      // This effectively maintains online status similar to Facebook/Messenger
      
    } catch (e) {
      print('❌ [BackgroundActivity] Error initializing background activity: $e');
      // Don't throw - allow app to continue without background tasks
    }
  }

  /// Cancel background activity updates
  static Future<void> cancel() async {
    try {
      // WorkManager is disabled, so nothing to cancel
      print('ℹ️ [BackgroundActivity] Background activity updates cancelled (using push notifications)');
    } catch (e) {
      print('❌ [BackgroundActivity] Error cancelling background activity: $e');
    }
  }
}

/// Update user activity via API
Future<void> _updateActivity(String userId) async {
  try {
    // Create HTTP client with standard SSL validation
    HttpClient httpClient;
    if (HttpOverrides.current != null) {
      httpClient = HttpOverrides.current!.createHttpClient(null);
    } else {
      httpClient = HttpClient();
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

