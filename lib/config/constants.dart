import 'package:flutter/foundation.dart';

class ApiConstants {
  // Production URLs
  static const String _prodAppBase = 'https://app.skybyn.no';
  static const String _prodApiBase = 'https://api.skybyn.no';
  static const String _prodWebBase = 'https://skybyn.no';

  // Development URLs
  static const String _devBase = 'https://server.skybyn.no';
  static const String _devApiBase = 'https://server.skybyn.no/api';
  static const String _devAppBase = 'https://server.skybyn.no/app';

  // Static flags to ensure logging only happens once
  static bool _hasLoggedAppBase = false;
  static bool _hasLoggedApiBase = false;
  static bool _hasLoggedWebBase = false;

  /// Returns development URLs in debug mode, production URLs in release mode
  /// 
  /// Debug mode (kDebugMode = true): Uses _dev URLs
  /// Release mode (kDebugMode = false): Uses _prod URLs
  static String get appBase {
    final url = kDebugMode ? _devAppBase : _prodAppBase;
    assert(() {
      if (!_hasLoggedAppBase) {
        print('🔧 [ApiConstants] Using ${kDebugMode ? "DEV" : "PROD"} appBase: $url');
        _hasLoggedAppBase = true;
      }
      return true;
    }());
    return url;
  }

  static String get apiBase {
    final url = kDebugMode ? _devApiBase : _prodApiBase;
    // Log in both debug and release (using debugPrint which works in release)
    if (!_hasLoggedApiBase) {
      debugPrint('🔧 [ApiConstants] Using ${kDebugMode ? "DEV" : "PROD"} apiBase: $url');
      _hasLoggedApiBase = true;
    }
    return url;
  }

  static String get webBase {
    final url = kDebugMode ? _devBase : _prodWebBase;
    assert(() {
      if (!_hasLoggedWebBase) {
        print('🔧 [ApiConstants] Using ${kDebugMode ? "DEV" : "PROD"} webBase: $url');
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
}

class StorageKeys {
  static const String userId = 'user_id';
  static const String userProfile = 'user_profile';
  static const String username = 'username';
}

/// Utility class for URL conversion between dev and prod environments
class UrlHelper {
  /// Convert a URL to use the appropriate base URL based on build mode
  /// This is useful for images and other resources that may have hardcoded production URLs
  static String convertUrl(String url) {
    if (url.isEmpty) {
      return url;
    }
    
    if (!kDebugMode) {
      // In release mode, return URL as-is
      return url;
    }
    
    // In debug mode, replace production domains with dev domain
    final devBase = ApiConstants.webBase;
    String convertedUrl = url;
    
    // Replace https://skybyn.com with dev base
    if (url.contains('https://skybyn.com')) {
      convertedUrl = url.replaceAll('https://skybyn.com', devBase);
      assert(() {
        print('🔧 [UrlHelper] Converted skybyn.com URL: $url -> $convertedUrl');
        return true;
      }());
      return convertedUrl;
    }
    
    // Replace https://skybyn.no with dev base
    if (url.contains('https://skybyn.no')) {
      convertedUrl = url.replaceAll('https://skybyn.no', devBase);
      assert(() {
        print('🔧 [UrlHelper] Converted skybyn.no URL: $url -> $convertedUrl');
        return true;
      }());
      return convertedUrl;
    }
    
    // Replace https://app.skybyn.no with dev app base
    if (url.contains('https://app.skybyn.no')) {
      convertedUrl = url.replaceAll('https://app.skybyn.no', ApiConstants.appBase);
      assert(() {
        print('🔧 [UrlHelper] Converted app.skybyn.no URL: $url -> $convertedUrl');
        return true;
      }());
      return convertedUrl;
    }
    
    // Replace https://api.skybyn.no with dev api base
    if (url.contains('https://api.skybyn.no')) {
      convertedUrl = url.replaceAll('https://api.skybyn.no', ApiConstants.apiBase);
      assert(() {
        print('🔧 [UrlHelper] Converted api.skybyn.no URL: $url -> $convertedUrl');
        return true;
      }());
      return convertedUrl;
    }
    
    // If URL doesn't contain a domain, assume it's a relative path and prepend dev base
    if (url.startsWith('/')) {
      convertedUrl = '$devBase$url';
      assert(() {
        print('🔧 [UrlHelper] Converted relative URL: $url -> $convertedUrl');
        return true;
      }());
      return convertedUrl;
    }
    
    // Return as-is if no conversion needed
    return url;
  }
}
