import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// Background service to update user activity periodically
/// This keeps users appearing as "online" even when the app is fully closed
/// Similar to how Facebook/Messenger maintain online status
/// 
/// NOTE: Uses Firebase push notifications to update activity when app is closed.
/// When a push notification is received, it automatically updates the user's
/// last_active timestamp, maintaining online status effectively.
/// This approach works without requiring a persistent notification.
class BackgroundActivityService {
  static const String _userIdKey = 'background_user_id';

  /// Initialize background activity updates
  /// Currently uses Firebase push notifications to update activity when app is closed.
  /// When a push notification is received, it updates the user's last_active timestamp,
  /// which keeps them appearing as "online" for up to 5 minutes.
  /// 
  /// This approach:
  /// - Works when app is fully closed/terminated
  /// - No persistent notification required
  /// - Battery efficient (uses system push service)
  /// - Already implemented in firebase_messaging_service.dart
  static Future<void> initialize() async {
    try {
      // Check if user is logged in
      final authService = AuthService();
      final userId = await authService.getStoredUserId();
      
      if (userId == null || userId.isEmpty) {
        return;
      }

      // Store user ID (may be used in future for other background tasks)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);

      // Activity updates are handled by:
      // 1. Firebase push notifications (when app is closed) - already implemented in firebase_messaging_service.dart
      // 2. Periodic timer (when app is in background) - already implemented in main.dart
      // 3. WebSocket connection (when app is open) - already implemented in main.dart
      
      // No additional setup needed - the existing Firebase notification handler
      // already calls updateActivity() when notifications are received
      
    } catch (e) {
      // Don't throw - allow app to continue without background tasks
    }
  }

  /// Cancel background activity updates
  static Future<void> cancel() async {
    try {
      // Clear stored user ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userIdKey);
      // Note: Firebase notifications will still arrive, but updateActivity() will
      // check if user is logged in before updating, so it's safe
    } catch (e) {
      // Silently fail
    }
  }
}

