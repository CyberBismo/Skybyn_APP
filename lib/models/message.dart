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
    return Message(
      id: json['id']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      date: json['date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(json['date'].toString()) ?? 0)
          : DateTime.now(),
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

