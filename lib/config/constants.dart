import 'package:flutter/foundation.dart';

class ApiConstants {
  // Production URLs
  static const String _prodAppBase = 'https://app.skybyn.no';
  static const String _prodApiBase = 'https://api.skybyn.no';
  static const String _prodWebBase = 'https://skybyn.no';

  // Development URLs
  static const String _devBase = 'https://skybyn.ddns.net';
  static const String _devApiBase = 'https://skybyn.ddns.net/api';
  static const String _devAppBase = 'https://skybyn.ddns.net/app';

  // Use dev URLs in debug mode, production URLs in release mode
  static String get appBase => kDebugMode ? _devAppBase : _prodAppBase;
  static String get apiBase => kDebugMode ? _devApiBase : _prodApiBase;
  static String get webBase => kDebugMode ? _devBase : _prodWebBase;

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
