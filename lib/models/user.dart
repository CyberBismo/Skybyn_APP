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
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? json['userID']?.toString() ?? '',
      username: json['username'] ?? '',
      secQOne: json['sec_q_one'] ?? '',
      secAOne: json['sec_a_one'] ?? '',
      secQTwo: json['sec_q_two'] ?? '',
      secATwo: json['sec_a_two'] ?? '',
      pinV: json['pin_v'] ?? '',
      pin: json['pin'] ?? '',
      email: json['email'] ?? '',
      fname: json['fname'] ?? '',
      mname: json['mname'] ?? '',
      lname: json['lname'] ?? '',
      title: json['title'] ?? '',
      nickname: json['nickname'] ?? '',
      avatar: json['avatar'] ?? '',
      bio: json['bio'] ?? '',
      color: json['color'] ?? '',
      rank: json['rank'] ?? '',
      deactivated: json['deactivated'] ?? '',
      deactivatedReason: json['deactivated_reason'] ?? '',
      banned: json['banned'] ?? '',
      bannedReason: json['banned_reason'] ?? '',
      visible: json['visible'] ?? '',
      registered: json['registered'] ?? '',
      token: json['token'] ?? '',
      reset: json['reset'] ?? '',
      online: json['online'] ?? '',
      relationship: json['relationship'] ?? '',
      wallpaper: json['wallpaper'] ?? '',
      wallpaperMargin: json['wallpaper_margin'] ?? '',
      avatarMargin: json['avatar_margin'] ?? '',
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
    };
  }
} 