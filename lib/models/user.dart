import '../config/constants.dart';
import 'dart:developer' as developer;

class User {
  final String id;
  final String username;
  final String secQOne;
  final String secAOne;
  final String secQTwo;
  final String secATwo;
  final String pinV;
  final String pin;
  final String email;
  final String fname;
  final String mname;
  final String lname;
  final String title;
  final String nickname;
  final String avatar;
  final String bio;
  final String color;
  final String rank;
  final String deactivated;
  final String deactivatedReason;
  final String banned;
  final String bannedReason;
  final String visible;
  final String registered;
  final String token;
  final String reset;
  final String online;
  final String relationship;
  final String wallpaper;
  final String wallpaperMargin;
  final String avatarMargin;
  final String? language;

  User({
    required this.id,
    required this.username,
    required this.secQOne,
    required this.secAOne,
    required this.secQTwo,
    required this.secATwo,
    required this.pinV,
    required this.pin,
    required this.email,
    required this.fname,
    required this.mname,
    required this.lname,
    required this.title,
    required this.nickname,
    required this.avatar,
    required this.bio,
    required this.color,
    required this.rank,
    required this.deactivated,
    required this.deactivatedReason,
    required this.banned,
    required this.bannedReason,
    required this.visible,
    required this.registered,
    required this.token,
    required this.reset,
    required this.online,
    required this.relationship,
    required this.wallpaper,
    required this.wallpaperMargin,
    required this.avatarMargin,
    this.language,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Process avatar URL - ensure it's absolute
    String avatarUrl = (json['avatar'] ?? '').toString().trim();
    
    // Debug: Log raw avatar URL from JSON
    if (avatarUrl.isNotEmpty) {
      developer.log('📸 [User] Raw avatar from JSON: "$avatarUrl"', name: 'User Model');
    }
    
    // API already returns full URLs (https://skybyn.com/...), but handle edge cases:
    // - If avatar is empty, API returns default logo URL
    // - If avatar is a relative path (starts with /), make it absolute
    // - If avatar doesn't start with http, it might be a relative path
    if (avatarUrl.isNotEmpty) {
      if (!avatarUrl.startsWith('http')) {
        // Relative path - make it absolute
        if (avatarUrl.startsWith('/')) {
          avatarUrl = '${ApiConstants.webBase}$avatarUrl';
        } else {
          avatarUrl = '${ApiConstants.webBase}/$avatarUrl';
        }
        developer.log('📸 [User] Converted relative path to: "$avatarUrl"', name: 'User Model');
      } else {
        developer.log('📸 [User] Using absolute URL as-is: "$avatarUrl"', name: 'User Model');
      }
      // If avatar URL is already full (starts with http), use it as-is
    } else {
      developer.log('📸 [User] Avatar URL is empty', name: 'User Model');
    }
    // If avatar is empty, API should have returned default, but if not, leave empty
    // (UI will handle showing default icon)
    
    // Process wallpaper URL - ensure it's absolute
    String wallpaperUrl = (json['wallpaper'] ?? '').toString().trim();
    if (wallpaperUrl.isNotEmpty && !wallpaperUrl.startsWith('http')) {
      if (wallpaperUrl.startsWith('/')) {
        wallpaperUrl = '${ApiConstants.webBase}$wallpaperUrl';
      } else {
        wallpaperUrl = '${ApiConstants.webBase}/$wallpaperUrl';
      }
    }
    
    return User(
      id: json['id']?.toString() ?? json['userID']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      secQOne: json['sec_q_one']?.toString() ?? '',
      secAOne: json['sec_a_one']?.toString() ?? '',
      secQTwo: json['sec_q_two']?.toString() ?? '',
      secATwo: json['sec_a_two']?.toString() ?? '',
      pinV: json['pin_v']?.toString() ?? '',
      pin: json['pin']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fname: json['fname']?.toString() ?? '',
      mname: json['mname']?.toString() ?? '',
      lname: json['lname']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatar: avatarUrl,
      bio: json['bio']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      rank: json['rank']?.toString() ?? '',
      deactivated: json['deactivated']?.toString() ?? '',
      deactivatedReason: json['deactivated_reason']?.toString() ?? '',
      banned: json['banned']?.toString() ?? '',
      bannedReason: json['banned_reason']?.toString() ?? '',
      visible: json['visible']?.toString() ?? '',
      registered: json['registered']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      reset: json['reset']?.toString() ?? '',
      online: json['online']?.toString() ?? '',
      relationship: json['relationship']?.toString() ?? '',
      wallpaper: wallpaperUrl,
      wallpaperMargin: json['wallpaper_margin']?.toString() ?? '',
      avatarMargin: json['avatar_margin']?.toString() ?? '',
      language: json['language']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'sec_q_one': secQOne,
      'sec_a_one': secAOne,
      'sec_q_two': secQTwo,
      'sec_a_two': secATwo,
      'pin_v': pinV,
      'pin': pin,
      'email': email,
      'fname': fname,
      'mname': mname,
      'lname': lname,
      'title': title,
      'nickname': nickname,
      'avatar': avatar,
      'bio': bio,
      'color': color,
      'rank': rank,
      'deactivated': deactivated,
      'deactivated_reason': deactivatedReason,
      'banned': banned,
      'banned_reason': bannedReason,
      'visible': visible,
      'registered': registered,
      'token': token,
      'reset': reset,
      'online': online,
      'relationship': relationship,
      'wallpaper': wallpaper,
      'wallpaper_margin': wallpaperMargin,
      'avatar_margin': avatarMargin,
      'language': language,
    };
  }
} 