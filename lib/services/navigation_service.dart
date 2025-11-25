import 'package:shared_preferences/shared_preferences.dart';

class NavigationService {
  static const String _lastRouteKey = 'last_route';
  
  /// Save the current route name
  static Future<void> saveLastRoute(String routeName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRouteKey, routeName);
    } catch (e) {
      // Silently fail - navigation state is not critical
    }
  }
  
  /// Get the last saved route name
  static Future<String?> getLastRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastRouteKey);
    } catch (e) {
      return null;
    }
  }
  
  /// Clear the saved route (e.g., on logout)
  static Future<void> clearLastRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastRouteKey);
    } catch (e) {
      // Silently fail
    }
  }
  
  /// Get route name from screen class name
  static String getRouteName(String screenClassName) {
    // Convert class name to route name
    // e.g., "HomeScreen" -> "home", "ProfileScreen" -> "profile"
    return screenClassName
        .replaceAll('Screen', '')
        .replaceAll(RegExp(r'([A-Z])'), r'_\1')
        .toLowerCase()
        .replaceFirst('_', '');
  }
}

