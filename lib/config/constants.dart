import 'package:flutter/foundation.dart';

class ApiConstants {
  // Production URLs
  static const String _prodAppBase = 'https://app.skybyn.no';
  static const String _prodApiBase = 'https://api.skybyn.no';
  static const String _prodWebBase = 'https://skybyn.no';

  // Static flags to ensure logging only happens once
  static bool _hasLoggedAppBase = false;
  static bool _hasLoggedApiBase = false;
  static bool _hasLoggedWebBase = false;

  /// Returns production URLs
  static String get appBase {
    const url = _prodAppBase;
    assert(() {
      if (!_hasLoggedAppBase) {
        print('🔧 [ApiConstants] Using PROD appBase: $url');
        _hasLoggedAppBase = true;
      }
      return true;
    }());
    return url;
  }

  static String get apiBase {
    const url = _prodApiBase;
    // Log in both debug and release (using debugPrint which works in release)
    if (!_hasLoggedApiBase) {
      debugPrint('🔧 [ApiConstants] Using PROD apiBase: $url');
      _hasLoggedApiBase = true;
    }
    return url;
  }

  static String get webBase {
    const url = _prodWebBase;
    assert(() {
      if (!_hasLoggedWebBase) {
        print('🔧 [ApiConstants] Using PROD webBase: $url');
        _hasLoggedWebBase = true;
      }
      return true;
    }());
    return url;
  }

  // Auth
  static String get login => '$apiBase/login.php';
  static String get profile => '$apiBase/profile.php';
  static String get sendEmailVerification => '$apiBase/sendEmailVerification.php';
  static String get verifyEmail => '$apiBase/verify_email.php';
  static String get register => '$apiBase/register.php';
  static String get resetPassword => '$apiBase/reset.php';
  static String get token => '$apiBase/token.php';

  // Posts
  static String get timeline => '$apiBase/post/timeline.php';
  static String get userTimeline => '$apiBase/post/user-timeline.php';
  static String get getPost => '$apiBase/post/get_post.php';
  static String get deletePost => '$apiBase/post/delete.php';
  static String get addPost => '$apiBase/post/add.php';
  static String get updatePost => '$apiBase/post/update.php';

  // Comments
  static String get addComment => '$apiBase/comment/add.php';
  static String get getComment => '$apiBase/comment/get_comment.php';
  static String get deleteComment => '$apiBase/comment/delete.php';

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
  static String get readAllNotifications => '$apiBase/notification/read_all.php';
  static String get deleteAllNotifications => '$apiBase/notification/delete_all.php';

  // Updates
  static String get appUpdate => '$apiBase/app_update.php';

  // Chat
  static String get chatSend => '$apiBase/chat/send.php';
  static String get chatGet => '$apiBase/chat/get.php';

  // Activity
  static String get updateActivity => '$apiBase/update_activity.php';
  
  // Admin
  static String get adminUsers => '$apiBase/admin/users.php';
  static String get adminReports => '$apiBase/admin/reports.php';
  
  // API Key for unrestricted access (bypasses bot protection)
  static const String apiKey = 'DP4HOA9PYSUAPFP1SHEMHNPJ0S6QZF3X';
}

class StorageKeys {
  static const String userId = 'user_id';
  static const String userProfile = 'user_profile';
  static const String username = 'username';
}

/// Utility class for URL conversion
class UrlHelper {
  /// Convert a URL to use the appropriate base URL
  /// This is useful for images and other resources that may have hardcoded production URLs
  static String convertUrl(String url) {
    if (url.isEmpty) {
      return url;
    }
    
    // Return URL as-is (production URLs)
    return url;
  }
}
