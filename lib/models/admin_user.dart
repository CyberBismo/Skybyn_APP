class AdminUser {
  final int id;
  final String username;
  final String nickname;
  final String email;
  final int rank;
  final int banned;
  final int deactivated;
  final int registrationDate;
  final int lastActive;
  final int online;

  AdminUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.email,
    required this.rank,
    required this.banned,
    required this.deactivated,
    required this.registrationDate,
    required this.lastActive,
    required this.online,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: int.parse(json['id'].toString()),
      username: json['username'] ?? '',
      nickname: json['nickname'] ?? '',
      email: json['email'] ?? '',
      rank: int.parse(json['rank'].toString()),
      banned: int.parse(json['banned'].toString()),
      deactivated: int.parse(json['deactivated'].toString()),
      registrationDate: int.parse(json['registration_date'].toString()),
      lastActive: int.parse(json['last_active'].toString()),
      online: int.parse(json['online'].toString()),
    );
  }

  bool get isBanned => banned == 1;
  bool get isDeactivated => deactivated == 1;
  bool get isOnline => online == 1;
  bool get isAdmin => rank > 5;
  bool get isModerator => rank > 3;
}

