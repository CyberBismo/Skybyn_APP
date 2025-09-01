import '../config/constants.dart';

class Friend {
  final String id;
  final String username;
  final String nickname;
  final String avatar;
  final bool online;

  Friend({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.online,
  });

  static bool _parseOnline(dynamic value) {
    if (value is bool) return value;
    final s = value?.toString().toLowerCase();
    return s == '1' || s == 'true' || s == 'online' || s == 'yes';
  }

  factory Friend.fromJson(Map<String, dynamic> json) {
    String avatarUrl = (json['avatar'] ?? json['profileImage'] ?? '').toString();
    
    // If avatar is a relative path, make it absolute using the web base
    if (avatarUrl.isNotEmpty && !avatarUrl.startsWith('http')) {
      if (avatarUrl.startsWith('/')) {
        avatarUrl = '${ApiConstants.webBase}$avatarUrl';
      } else {
        avatarUrl = '${ApiConstants.webBase}/$avatarUrl';
      }
    }
    
    return Friend(
      id: (json['friend_id'] ?? json['userID'] ?? json['id'] ?? '').toString(),
      username: (json['username'] ?? json['name'] ?? 'Unknown').toString(),
      nickname: (json['nickname'] ?? '').toString(),
      avatar: avatarUrl,
      online: _parseOnline(json['online']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      'avatar': avatar,
      'online': online,
    };
  }
}


