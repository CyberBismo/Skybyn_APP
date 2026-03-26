class ApiConstants {
  // Production URLs
  static const String _prodAppBase = 'https://app.skybyn.no';
  static const String _prodApiBase = 'https://api.skybyn.no';
  static const String _prodWebBase = 'https://skybyn.no';

  /// Returns production URLs
  static String get appBase => _prodAppBase;

  static String get apiBase => _prodApiBase;

  static String get webBase => _prodWebBase;

  // System data
  static String get systemData => '$apiBase/system_data.php';

  // Auth
  static String get login => '$apiBase/login.php';
  static String get profile => '$apiBase/profile.php';
  static String get sendEmailVerification =>
      '$apiBase/sendEmailVerification.php';
  static String get verifyEmail => '$apiBase/verify_email.php';
  static String get register => '$apiBase/register.php';
  static String get token => '$apiBase/firebase/registerFirebaseToken.php';
  static String get checkDevice => '$apiBase/firebase/checkDevice.php';
  static String get authFirebase => '$apiBase/firebase/getFirebaseToken.php';
  static String get forgotPassword => '$apiBase/forgot.php';

  // Posts
  static String get timeline => '$apiBase/timeline.php';

  // Comments
  static String get comment => '$apiBase/comment.php';

  // Pages
  static String get page => '$apiBase/page.php';

  // Languages
  static String get language => '$apiBase/translations.php';

  // QR Check
  static String get qrCheck => '$apiBase/qr_check.php';

  // Friends
  static String get friend => '$apiBase/friend/friend.php';
  static String get friends => '$apiBase/friend/friends.php';

  // Reports
  static String get report => '$apiBase/report.php';

  // Notifications
  static String get notifications => '$apiBase/notification/list.php';
  static String get createNotification => '$apiBase/notification/create.php';
  static String get deleteNotification => '$apiBase/notification/delete.php';
  static String get readNotification => '$apiBase/notification/read.php';
  static String get notificationCount => '$apiBase/notification/count.php';
  static String get readAllNotifications =>
      '$apiBase/notification/read_all.php';
  static String get deleteAllNotifications =>
      '$apiBase/notification/delete_all.php';

  // Updates
  static String get appUpdate => '$apiBase/app_update.php';

  // Error Reporting
  static String get reportError => '$apiBase/report_error.php';

  // Chat
  static String get chatSend => '$apiBase/chat/send.php';
  static String get chatGet => '$apiBase/chat/get.php';
  static String get chatRead => '$apiBase/chat/read.php';
  static String get chatClear => '$apiBase/chat/clear.php';
  static String get chatDelete => '$apiBase/chat/delete.php';

  // Activity
  static String get updateActivity => '$apiBase/update_activity.php';

  // Location
  static String get friendsLocations =>
      '$apiBase/location/friends_locations.php';
  static String get updateLocationSettings =>
      '$apiBase/location/update_settings.php';
  static String get updateLocation => '$apiBase/location/update_location.php';
  static String get findNearbyUsers =>
      '$apiBase/location/find_nearby_users.php';

  // Video Feed
  static String get videoFeed => '$apiBase/video/feed.php';

  // Admin
  static String get adminUsers => '$apiBase/admin/users.php';
  static String get adminReports => '$apiBase/admin/reports.php';

  // NOTE: Static API key removed for security. The server should authenticate
  // app requests via session tokens instead of a shared static key.
  // Until server-side changes are made, pass the key via X-API-Key header
  // only for requests that require it, loaded from secure storage at runtime.
}

class StorageKeys {
  static const String userId = 'user_id';
  static const String userProfile = 'user_profile';
  static const String username = 'username';
  static const String sessionToken = 'session_token';
}

/// Utility class for URL conversion
class UrlHelper {
  /// Convert a URL to use the appropriate base URL
  /// This is useful for images and other resources that may have hardcoded production URLs
  static String convertUrl(String url) {
    if (url.isEmpty) {
      return url;
    }

    // If URL starts with "/uploads/", prepend the web base URL
    if (url.startsWith('/uploads/')) {
      return '${ApiConstants.webBase}$url';
    }

    // Return URL as-is (already has full URL or other format)
    return url;
  }
}
