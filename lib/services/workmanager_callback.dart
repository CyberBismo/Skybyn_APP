import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../config/constants.dart';

/// WorkManager callback dispatcher
/// This handles background tasks when the app is fully closed
/// 
/// NOTE: WorkManager does NOT require a persistent notification.
/// It runs background tasks periodically without showing any notification.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == 'updateActivityTask') {
        // Get stored user ID
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('background_user_id');
        
        if (userId == null || userId.isEmpty) {
          return Future.value(true); // User not logged in, skip
        }

        // Update activity via API
        await _updateActivity(userId);
        
        return Future.value(true); // Task completed successfully
      }
      
      return Future.value(false); // Unknown task
    } catch (e) {
      // Silently fail - activity updates are not critical
      return Future.value(false);
    }
  });
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
        // Activity updated successfully
      }
    }
  } catch (e) {
    // Silently fail - activity updates are not critical
  }
}

