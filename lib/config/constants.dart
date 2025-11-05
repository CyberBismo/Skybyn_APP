class ApiConstants {
  static const String appBase = 'https://app.skybyn.no';
  static const String apiBase = 'https://api.skybyn.no';
  static const String webBase = 'https://skybyn.no';

  // Auth
  static const String login = '$apiBase/login.php';
  static const String profile = '$apiBase/profile.php';
  static const String sendEmailVerification = '$apiBase/sendEmailVerification.php';
  static const String verifyEmail = '$apiBase/verify_email.php';
  static const String register = '$apiBase/register.php';
  static const String resetPassword = '$apiBase/reset.php';
  static const String token = '$apiBase/token.php';

  // Posts
  static const String timeline = '$apiBase/post/timeline.php';
  static const String userTimeline = '$apiBase/post/user-timeline.php';
  static const String getPost = '$apiBase/post/get_post.php';
  static const String deletePost = '$apiBase/post/delete.php';
  static const String addPost = '$apiBase/post/add.php';
  static const String updatePost = '$apiBase/post/update.php';

  // Comments
  static const String addComment = '$apiBase/comment/add.php';
  static const String getComment = '$apiBase/comment/get_comment.php';
  static const String deleteComment = '$apiBase/comment/delete.php';

  // Misc
  static const String language = '$apiBase/translations.php';
  static const String qrCheck = '$apiBase/qr_check.php';
  static const String friend = '$apiBase/friend/friend.php';
  static const String friends = '$apiBase/friend/friends.php';
  static const String notifications = '$apiBase/notification/list.php';
  static const String createNotification = '$apiBase/notification/create.php';
  static const String deleteNotification = '$apiBase/notification/delete.php';
  static const String readNotification = '$apiBase/notification/read.php';
  static const String notificationCount = '$apiBase/notification/count.php';
  static const String readAllNotifications = '$apiBase/notification/read_all.php';
  static const String deleteAllNotifications = '$apiBase/notification/delete_all.php';

  // Updates
  static const String appUpdate = '$apiBase/app_update.php';
}

class StorageKeys {
  static const String userId = 'user_id';
  static const String userProfile = 'user_profile';
  static const String username = 'username';
}
