class Report {
  final int id;
  final int reportedBy;
  final String reporterUsername;
  final String reporterNickname;
  final int userReported;
  final String reportedUsername;
  final String reportedNickname;
  final String content;
  final int date;
  final int resolved;

  Report({
    required this.id,
    required this.reportedBy,
    required this.reporterUsername,
    required this.reporterNickname,
    required this.userReported,
    required this.reportedUsername,
    required this.reportedNickname,
    required this.content,
    required this.date,
    required this.resolved,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: int.parse(json['id'].toString()),
      reportedBy: int.parse(json['reported_by'].toString()),
      reporterUsername: json['reporter_username'] ?? 'Unknown',
      reporterNickname: json['reporter_nickname'] ?? '',
      userReported: int.parse(json['user_reported'].toString()),
      reportedUsername: json['reported_username'] ?? 'Unknown',
      reportedNickname: json['reported_nickname'] ?? '',
      content: json['content'] ?? '',
      date: int.parse(json['date'].toString()),
      resolved: int.parse(json['resolved'].toString()),
    );
  }

  bool get isResolved => resolved == 1;
  
  String get reporterDisplayName {
    return reporterNickname.isNotEmpty ? reporterNickname : reporterUsername;
  }
  
  String get reportedDisplayName {
    return reportedNickname.isNotEmpty ? reportedNickname : reportedUsername;
  }
}

