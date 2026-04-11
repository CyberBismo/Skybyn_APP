/// In-memory cache for user profile data (username, displayname, avatar).
/// Populated whenever posts/comments are loaded, cleared on logout.
/// Avoids redundant API calls when the same user appears multiple times in the feed.
class UserCacheService {
  static final UserCacheService _instance = UserCacheService._();
  factory UserCacheService() => _instance;
  UserCacheService._();

  final Map<String, _CachedUser> _cache = {};

  void store(String userId, {String? username, String? displayname, String? avatar}) {
    if (userId.isEmpty || userId == '0') return;
    _cache[userId] = _CachedUser(
      username: username ?? _cache[userId]?.username,
      displayname: displayname ?? _cache[userId]?.displayname,
      avatar: avatar ?? _cache[userId]?.avatar,
    );
  }

  String? getUsername(String userId) => _cache[userId]?.displayname ?? _cache[userId]?.username;
  String? getAvatar(String userId) => _cache[userId]?.avatar;

  bool has(String userId) => _cache.containsKey(userId);

  void clear() => _cache.clear();
}

class _CachedUser {
  final String? username;
  final String? displayname;
  final String? avatar;
  const _CachedUser({this.username, this.displayname, this.avatar});
}
