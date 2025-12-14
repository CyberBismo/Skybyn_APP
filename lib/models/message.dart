/// Message delivery status (like WhatsApp/Telegram)
enum MessageStatus {
  sending,    // Message is being sent (optimistic UI)
  sent,       // Message sent to server successfully
  delivered,  // Message delivered to recipient's device
  read,       // Message read by recipient
  failed,     // Message failed to send
}

class Message {
  final String id;
  final String from;
  final String to;
  final String content;
  final DateTime date;
  final bool viewed;
  final bool isFromMe;
  final MessageStatus status; // Message delivery status

  Message({
    required this.id,
    required this.from,
    required this.to,
    required this.content,
    required this.date,
    this.viewed = false,
    required this.isFromMe,
    this.status = MessageStatus.sent, // Default to sent for received messages
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
    
    // Parse message status (default to sent for received messages)
    MessageStatus parseStatus(dynamic statusValue, bool isFromMe) {
      if (!isFromMe) {
        // Received messages are always delivered (we received them)
        return MessageStatus.delivered;
      }
      
      if (statusValue == null) return MessageStatus.sent;
      
      final statusStr = statusValue.toString().toLowerCase();
      switch (statusStr) {
        case 'sending':
          return MessageStatus.sending;
        case 'sent':
          return MessageStatus.sent;
        case 'delivered':
          return MessageStatus.delivered;
        case 'read':
          return MessageStatus.read;
        case 'failed':
          return MessageStatus.failed;
        default:
          return MessageStatus.sent;
      }
    }
    
    final isFromMe = json['from']?.toString() == currentUserId;
    
    return Message(
      id: json['id']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      date: parseDate(json['date']),
      viewed: json['viewed'] == 1 || json['viewed'] == true,
      isFromMe: isFromMe,
      status: parseStatus(json['status'], isFromMe),
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
      'status': status.name,
    };
  }
  
  /// Create a copy with updated status
  Message copyWith({
    String? id,
    String? from,
    String? to,
    String? content,
    DateTime? date,
    bool? viewed,
    bool? isFromMe,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      from: from ?? this.from,
      to: to ?? this.to,
      content: content ?? this.content,
      date: date ?? this.date,
      viewed: viewed ?? this.viewed,
      isFromMe: isFromMe ?? this.isFromMe,
      status: status ?? this.status,
    );
  }
}

