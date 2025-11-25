import '../config/constants.dart';

class Friend {
  final String id;
  final String username;
  final String nickname;
  final String avatar;
  final bool online;
  final int? lastActive; // Unix timestamp in seconds
  final double? latitude;
  final double? longitude;
  final String? locationShareMode; // 'off', 'last_active', 'live'
  final bool? isLive;
  final bool? locationPrivateMode;

  Friend({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.online,
    this.lastActive,
    this.latitude,
    this.longitude,
    this.locationShareMode,
    this.isLive,
    this.locationPrivateMode,
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
    
    // Parse last_active timestamp (can be in seconds or milliseconds)
    // Also check for last_seen (human-readable) from new API
    int? lastActive;
    if (json['last_active'] != null) {
      final lastActiveValue = json['last_active'];
      if (lastActiveValue is int) {
        // If it's a large number (milliseconds), convert to seconds
        lastActive = lastActiveValue > 10000000000 
            ? lastActiveValue ~/ 1000 
            : lastActiveValue;
      } else if (lastActiveValue is String) {
        final parsed = int.tryParse(lastActiveValue);
        if (parsed != null) {
          lastActive = parsed > 10000000000 ? parsed ~/ 1000 : parsed;
        }
      }
    }
    
    // Use calculated online status from API if available (Facebook/Messenger style)
    // Otherwise fall back to online field
    final calculatedOnline = json['online_status'] != null 
        ? json['online_status'] == 'online'
        : _parseOnline(json['online']);
    
    // Parse location data
    double? latitude;
    double? longitude;
    if (json['latitude'] != null && json['longitude'] != null) {
      latitude = json['latitude'] is double 
          ? json['latitude'] 
          : double.tryParse(json['latitude'].toString());
      longitude = json['longitude'] is double 
          ? json['longitude'] 
          : double.tryParse(json['longitude'].toString());
    }
    
    // Parse location sharing settings
    String? locationShareMode;
    if (json['location_share_mode'] != null) {
      locationShareMode = json['location_share_mode'].toString();
    }
    
    bool? isLive;
    if (json['is_live'] != null) {
      isLive = json['is_live'] is bool 
          ? json['is_live'] 
          : json['is_live'].toString().toLowerCase() == 'true';
    }
    
    bool? locationPrivateMode;
    if (json['location_private_mode'] != null) {
      final value = json['location_private_mode'];
      locationPrivateMode = value is bool 
          ? value 
          : value.toString() == '1' || value.toString().toLowerCase() == 'true';
    }
    
    return Friend(
      id: (json['friend_id'] ?? json['userID'] ?? json['id'] ?? '').toString(),
      username: (json['username'] ?? json['name'] ?? 'Unknown').toString(),
      nickname: (json['nickname'] ?? '').toString(),
      avatar: avatarUrl,
      online: calculatedOnline,
      lastActive: lastActive,
      latitude: latitude,
      longitude: longitude,
      locationShareMode: locationShareMode,
      isLive: isLive,
      locationPrivateMode: locationPrivateMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      'avatar': avatar,
      'online': online,
      'last_active': lastActive,
      'latitude': latitude,
      'longitude': longitude,
      'location_share_mode': locationShareMode,
      'is_live': isLive,
      'location_private_mode': locationPrivateMode,
    };
  }

  /// Create a copy of this friend with updated online status
  Friend copyWith({
    bool? online, 
    int? lastActive,
    double? latitude,
    double? longitude,
    String? locationShareMode,
    bool? isLive,
    bool? locationPrivateMode,
  }) {
    return Friend(
      id: id,
      username: username,
      nickname: nickname,
      avatar: avatar,
      online: online ?? this.online,
      lastActive: lastActive ?? this.lastActive,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationShareMode: locationShareMode ?? this.locationShareMode,
      isLive: isLive ?? this.isLive,
      locationPrivateMode: locationPrivateMode ?? this.locationPrivateMode,
    );
  }
  
  /// Get formatted last active status string
  /// Returns "Online" if active within 2 minutes, otherwise "Last active X ago"
  String getLastActiveStatus() {
    if (lastActive == null) {
      return online ? 'Online' : 'Offline';
    }
    
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final twoMinutesAgo = now - 120; // 2 minutes = 120 seconds
    
    if (lastActive! >= twoMinutesAgo) {
      return 'Online';
    }
    
    final secondsAgo = now - lastActive!;
    
    if (secondsAgo < 60) {
      return 'Last active ${secondsAgo}s ago';
    } else if (secondsAgo < 3600) {
      final minutes = secondsAgo ~/ 60;
      return 'Last active ${minutes}m ago';
    } else if (secondsAgo < 86400) {
      final hours = secondsAgo ~/ 3600;
      return 'Last active ${hours}h ago';
    } else {
      final days = secondsAgo ~/ 86400;
      return 'Last active ${days}d ago';
    }
  }
}


