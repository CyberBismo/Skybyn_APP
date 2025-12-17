
class ApiConstants {
  // Production URLs
  static const String _prodAppBase = 'https://app.skybyn.no';
  static const String _prodApiBase = 'https://api.skybyn.no';
  static const String _prodWebBase = 'https://skybyn.no';

  /// Returns production URLs
  static String get appBase => _prodAppBase;

  static String get apiBase => _prodApiBase;

  static String get webBase => _prodWebBase;

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
  static String get chatSend => '$apiBase/chat/add.php';
  static String get chatGet => '$apiBase/chat/get.php';

  // Call Queue
  static String get queueCallOffer => '$apiBase/call/queue_offer.php';
  static String get updateCallStatus => '$apiBase/call/update_status.php';
  static String get getPendingCalls => '$apiBase/call/get_pending.php';
  static String get callHistory => '$apiBase/call/history.php';

  // Firebase/Notifications
  static String get firebase => '$apiBase/firebase.php';

  // Activity
  static String get updateActivity => '$apiBase/update_activity.php';

  // Location
  static String get friendsLocations => '$apiBase/location/friends_locations.php';
  static String get updateLocationSettings => '$apiBase/location/update_settings.php';

  // Video Feed
  static String get videoFeed => '$apiBase/video/feed.php';

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

<<<<<<< HEAD
/// Shared cache manager for avatars - ensures all widgets use the same cache
class AvatarCacheManager {
  static CacheManager? _instance;

  static CacheManager get instance {
    _instance ??= CacheManager(
      Config(
        'avatarCache',
        stalePeriod: const Duration(days: 30), // Keep avatars cached for 30 days
        maxNrOfCacheObjects: 1000, // Cache up to 1000 avatars
        repo: JsonCacheInfoRepository(databaseName: 'avatarCache.db'),
        fileService: HttpFileService(),
      ),
    );
    return _instance!;
  }

  /// Clear the avatar cache (call when user logs out or avatars are updated)
  static Future<void> clearCache() async {
    await _instance?.emptyCache();
  }
}

/// Utility class for URL conversion
class UrlHelper {
  // Store login timestamp for cache-busting (changes on every login)
  static int? _loginTimestamp;

  // Headers for image requests (prevents 403 errors from server security)
  static const Map<String, String> imageHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36 Skybyn-App/1.0',
    'Referer': 'https://skybyn.com/',
    'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Set the login timestamp for cache-busting
  static void setLoginTimestamp(int timestamp) {
    _loginTimestamp = timestamp;
  }

=======
/// Utility class for URL conversion
class UrlHelper {
>>>>>>> parent of 6049610 (Fix FCM token registration, device ID generation, and background notifications)
  /// Convert a URL to use the appropriate base URL
  /// This is useful for images and other resources that may have hardcoded production URLs
  static String convertUrl(String url) {
    if (url.isEmpty) {
      return url;
    }
<<<<<<< HEAD

    try {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        return url;
      }

      // Add cache-busting if needed
      // Only use login timestamp - never use current time to ensure stable caching
      if (addCacheBust && (url.contains('avatar') || url.contains('logo_faded_clean.png') || url.contains('logo.png'))) {
        // Only add cache-busting if we have a login timestamp
        // This ensures the URL is stable across rebuilds (same login = same URL = same cache)
        if (_loginTimestamp != null) {
          final queryParams = Map<String, String>.from(uri.queryParameters);
          queryParams['v'] = _loginTimestamp.toString();
          final finalUrl = uri.replace(queryParameters: queryParams).toString();
          return finalUrl;
        }
        // If no login timestamp, return URL without cache-busting to ensure stability
        return url;
      }
    } catch (e) {
      print('[SKYBYN] ⚠️ [UrlHelper] Failed to parse URL: "$url" - $e');
      // If URL parsing fails, return original URL
      return url;
    }

    // Return URL as-is if no changes needed
=======
    
    // Return URL as-is (production URLs)
>>>>>>> parent of 6049610 (Fix FCM token registration, device ID generation, and background notifications)
    return url;
  }
}
