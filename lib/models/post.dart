import 'package:intl/intl.dart';
import './comment.dart';

class Post {
  final String id;
  final String author;
  final String? userId;
  final String? avatar;
  final String content;
  final String? image;
  final int likes;
  final int comments;
  final List<Comment> commentsList;
  final DateTime createdAt;
  final bool isLiked;

  Post({
    required this.id,
    required this.author,
    this.userId,
    this.avatar,
    required this.content,
    this.image,
    required this.likes,
    required this.comments,
    this.commentsList = const [],
    required this.createdAt,
    required this.isLiked,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    int parseCount(dynamic value) {
      if (value is int) return value;
      if (value is List) return value.length;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    String? buildAvatarUrl(String? path) {
      if (path == null || path.isEmpty) {
        return null;
      }
      if (path.startsWith('http')) {
        return path;
      }
      
      // Handle relative paths like "../" or "..\/"
      String cleanPath = path;
      
      // Replace escaped slashes with regular slashes
      cleanPath = cleanPath.replaceAll('\\/', '/');
      
      // Remove any leading dots or slashes to prevent URL malformation
      cleanPath = cleanPath.replaceFirst(RegExp(r'^[\.\/]+'), '');
      
      // If the path is empty after cleaning, return null
      if (cleanPath.isEmpty) {
        return null;
      }
      
      // If the path doesn't start with uploads/, add it
      if (!cleanPath.startsWith('uploads/')) {
        cleanPath = 'uploads/$cleanPath';
      }
      
      final finalUrl = 'https://skybyn.com/$cleanPath';
      return finalUrl;
    }

    DateTime parseCreatedAt(dynamic value) {
      if (value == null) return DateTime.now();

      // Priority 1: Handle Unix timestamp (integer or string)
      if (value is int) {
        // Assumes timestamp is in seconds, converts to milliseconds for Dart
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true).toLocal();
      }
      if (value is String) {
        final intValue = int.tryParse(value);
        if (intValue != null) {
          return DateTime.fromMillisecondsSinceEpoch(intValue * 1000, isUtc: true).toLocal();
        }

        // Priority 2: Handle ISO 8601 string format (e.g., from gmdate('c'))
        try {
          return DateTime.parse(value).toLocal();
        } catch (e) {
          // Priority 3: Handle old custom format "d M. y H:i:s"
          try {
            final format = DateFormat('d MMM. yy HH:mm:ss', 'en_US');
            return format.parse(value, true).toLocal();
          } catch (e2) {
            // If all parsing fails, return current time
            return DateTime.now();
          }
        }
      }
      
      // Fallback for any other type
      return DateTime.now();
    }

    List<Comment> parseComments(dynamic value) {
      if (value is! List) return [];
      try {
        final comments = value
            .map((commentJson) =>
                Comment.fromJson(commentJson as Map<String, dynamic>))
            .toList();
        
        // Reverse the order so newest comments appear first
        return comments.reversed.toList();
      } catch (e) {
        print('Error parsing comments: $e');
        return [];
      }
    }

    final userJson = json['user'];
    Map<String, dynamic>? userMap;
    if (userJson is List && userJson.isNotEmpty) {
      userMap = userJson.first as Map<String, dynamic>?;
    } else if (userJson is Map) {
      userMap = userJson as Map<String, dynamic>?;
    }

    String? image;
    final videoJson = json['video'];
    if (videoJson is Map) {
      image = videoJson['thumbnail']?.toString();
    } else if (videoJson is List && videoJson.isNotEmpty) {
      final firstVideo = videoJson.first;
      if (firstVideo is Map) {
        image = firstVideo['thumbnail']?.toString();
      }
    }

    return Post(
      id: json['id']?.toString() ?? '',
      author: userMap?['username']?.toString() ?? 'Unknown User',
      userId: userMap?['id']?.toString(),
      avatar: buildAvatarUrl(userMap?['avatar']?.toString()),
      content: json['content'] ?? '',
      image: image,
      likes: parseCount(json['likes']), // 'likes' is missing in PHP, defaults to 0
      comments: parseCount(json['comments']),
      commentsList: parseComments(json['comments']),
      createdAt: parseCreatedAt(json['created']),
      isLiked: json['ilike'] == '1' || json['ilike'] == 1 || json['ilike'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author': author,
      'userId': userId,
      'avatar': avatar,
      'content': content,
      'image': image,
      'likes': likes,
      'comments': comments,
      'commentsList': commentsList.map((c) => c.toJson()).toList(),
      'created': createdAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(), // Keep both for compatibility
      'ilike': isLiked ? '1' : '0',
    };
  }

  Post copyWith({
    String? id,
    String? author,
    String? userId,
    String? avatar,
    String? content,
    String? image,
    int? likes,
    int? comments,
    List<Comment>? commentsList,
    DateTime? createdAt,
    bool? isLiked,
  }) {
    return Post(
      id: id ?? this.id,
      author: author ?? this.author,
      userId: userId ?? this.userId,
      avatar: avatar ?? this.avatar,
      content: content ?? this.content,
      image: image ?? this.image,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      commentsList: commentsList ?? this.commentsList,
      createdAt: createdAt ?? this.createdAt,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

extension CommentToJson on Comment {
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user': userId,
      'username': username,
      'avatar': avatar,
      'content': content,
    };
  }
} 