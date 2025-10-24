class ApiConstants {
  static const String apiBase = 'https://api.skybyn.no';
  static const String webBase = 'https://skybyn.no';

  // Auth
  static const String login = '$apiBase/login.php';
  static const String profile = '$apiBase/profile.php';
  static const String sendEmailVerification = '$apiBase/sendEmailVerification.php';
  static const String verifyEmail = '$apiBase/verify_email.php';
  static const String register = '$apiBase/register.php';
  static const String resetPassword = '$apiBase/reset.php';

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

  // Updates
  static const String checkUpdate = '$apiBase/appUpdates/check.php';
  static const String downloadUpdate = '$apiBase/appUpdates/download.php';
}

class StorageKeys {
  static const String userId = 'user_id';
  static const String userProfile = 'user_profile';
  static const String username = 'username';
}
