import 'subprofile.dart';

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
  
  // Relationship Partner
  final String? partnerId;
  final String? partnerName;
  final String? partnerAvatar;
  
  // Sub-profiles (children, pets, vehicles)
  final List<SubProfile> subprofiles;

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
    this.partnerId,
    this.partnerName,
    this.partnerAvatar,
    this.subprofiles = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final partner = json['partner'] as Map<String, dynamic>?;
    final subprofilesList = (json['subprofiles'] as List?)
        ?.map((sp) => SubProfile.fromJson(sp as Map<String, dynamic>))
        .toList() ?? [];

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
      avatar: json['avatar']?.toString() ?? '',
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
      wallpaper: json['wallpaper']?.toString() ?? '',
      wallpaperMargin: json['wallpaper_margin']?.toString() ?? '',
      avatarMargin: json['avatar_margin']?.toString() ?? '',
      language: json['language']?.toString(),
      partnerId: partner?['id']?.toString(),
      partnerName: partner?['username']?.toString(),
      partnerAvatar: partner?['avatar']?.toString(),
      subprofiles: subprofilesList,
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
      'partner': partnerId != null ? {
        'id': partnerId,
        'username': partnerName,
        'avatar': partnerAvatar,
      } : null,
      'subprofiles': subprofiles.map((sp) => sp.toJson()).toList(),
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? secQOne,
    String? secAOne,
    String? secQTwo,
    String? secATwo,
    String? pinV,
    String? pin,
    String? email,
    String? fname,
    String? mname,
    String? lname,
    String? title,
    String? nickname,
    String? avatar,
    String? bio,
    String? color,
    String? rank,
    String? deactivated,
    String? deactivatedReason,
    String? banned,
    String? bannedReason,
    String? visible,
    String? registered,
    String? token,
    String? reset,
    String? online,
    String? relationship,
    String? wallpaper,
    String? wallpaperMargin,
    String? avatarMargin,
    String? language,
    String? partnerId,
    String? partnerName,
    String? partnerAvatar,
    List<SubProfile>? subprofiles,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      secQOne: secQOne ?? this.secQOne,
      secAOne: secAOne ?? this.secAOne,
      secQTwo: secQTwo ?? this.secQTwo,
      secATwo: secATwo ?? this.secATwo,
      pinV: pinV ?? this.pinV,
      pin: pin ?? this.pin,
      email: email ?? this.email,
      fname: fname ?? this.fname,
      mname: mname ?? this.mname,
      lname: lname ?? this.lname,
      title: title ?? this.title,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      color: color ?? this.color,
      rank: rank ?? this.rank,
      deactivated: deactivated ?? this.deactivated,
      deactivatedReason: deactivatedReason ?? this.deactivatedReason,
      banned: banned ?? this.banned,
      bannedReason: bannedReason ?? this.bannedReason,
      visible: visible ?? this.visible,
      registered: registered ?? this.registered,
      token: token ?? this.token,
      reset: reset ?? this.reset,
      online: online ?? this.online,
      relationship: relationship ?? this.relationship,
      wallpaper: wallpaper ?? this.wallpaper,
      wallpaperMargin: wallpaperMargin ?? this.wallpaperMargin,
      avatarMargin: avatarMargin ?? this.avatarMargin,
      language: language ?? this.language,
      partnerId: partnerId ?? this.partnerId,
      partnerName: partnerName ?? this.partnerName,
      partnerAvatar: partnerAvatar ?? this.partnerAvatar,
      subprofiles: subprofiles ?? this.subprofiles,
    );
  }
}
 