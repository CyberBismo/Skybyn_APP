class Message {
  final String id;
  final String from;
  final String to;
  final String content;
  final DateTime date;
  final bool viewed;
  final bool isFromMe;

  Message({
    required this.id,
    required this.from,
    required this.to,
    required this.content,
    required this.date,
    this.viewed = false,
    required this.isFromMe,
  });

  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    DateTime parseDate(dynamic dateValue) {
      if (dateValue == null) return DateTime.now();
      
      final dateInt = int.tryParse(dateValue.toString()) ?? 0;
      if (dateInt == 0) return DateTime.now();
      
      // Check if timestamp is in seconds (Unix timestamp) or milliseconds
      // Unix timestamps in seconds are typically < 2^31 (year 2038), but > 1e12 (year 2001)
      // Millisecond timestamps are > 1e12
      // If timestamp is < 1e12, it's likely in seconds, so multiply by 1000
      if (dateInt < 1000000000000) {
        // Timestamp is in seconds, convert to milliseconds
        return DateTime.fromMillisecondsSinceEpoch(dateInt * 1000, isUtc: true).toLocal();
      } else {
        // Timestamp is already in milliseconds
        return DateTime.fromMillisecondsSinceEpoch(dateInt, isUtc: true).toLocal();
      }
    }
    
    return Message(
      id: json['id']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      date: parseDate(json['date']),
      viewed: json['viewed'] == 1 || json['viewed'] == true,
      isFromMe: json['from']?.toString() == currentUserId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from': from,
      'to': to,
      'content': content,
      'date': date.millisecondsSinceEpoch,
      'viewed': viewed ? 1 : 0,
    };
  }
}

