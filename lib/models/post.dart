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
      if (value == null) return [];
      
      // If it's already a List, parse it
      if (value is List) {
        try {
          final comments = value
              .whereType<Map<String, dynamic>>() // Filter out non-map items
              .map((commentJson) => Comment.fromJson(commentJson))
              .toList();
          
          // Reverse the order so newest comments appear first
          return comments.reversed.toList();
        } catch (e) {
          print('⚠️ [Post] Error parsing comments list: $e');
          print('⚠️ [Post] Comments data: $value');
          return [];
        }
      }
      
      // If it's a Map, it might be a single comment or a wrapper
      if (value is Map) {
        try {
          // Check if it's a single comment
          if (value.containsKey('id') || value.containsKey('content')) {
            return [Comment.fromJson(value as Map<String, dynamic>)];
          }
          // Check if it's a wrapper with a 'data' or 'list' field
          if (value.containsKey('data') && value['data'] is List) {
            return parseComments(value['data']);
          }
          if (value.containsKey('list') && value['list'] is List) {
            return parseComments(value['list']);
          }
        } catch (e) {
          print('⚠️ [Post] Error parsing comment map: $e');
        }
      }
      
      // If it's a number or string (count), return empty list
      return [];
    }

    final userJson = json['user'];
    Map<String, dynamic>? userMap;
    if (userJson is List && userJson.isNotEmpty) {
      userMap = userJson.first as Map<String, dynamic>?;
    } else if (userJson is Map) {
      userMap = userJson as Map<String, dynamic>?;
    }
    
    // Debug: Log user parsing
    if (userMap == null && userJson != null) {
      print('⚠️ [Post] User field is not in expected format. Type: ${userJson.runtimeType}, Value: $userJson');
    }
    
    // Try alternative field names for username
    String? username;
    if (userMap != null) {
      username = userMap['username']?.toString() ?? 
                 userMap['name']?.toString() ?? 
                 userMap['user']?.toString();
    }
    
    // If still no username, try direct fields in json
    if (username == null || username.isEmpty) {
      username = json['username']?.toString() ?? 
                 json['author']?.toString() ??
                 json['user_name']?.toString();
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

    // Handle comments - check if it's a list or a count
    final commentsData = json['comments'];
    final commentsList = parseComments(commentsData);
    final commentsCount = parseCount(commentsData);
    
    // Debug: Log comments parsing
    if (commentsData != null) {
      print('🔍 [Post] Comments field type: ${commentsData.runtimeType}');
      if (commentsList.isEmpty && commentsCount > 0) {
        print('⚠️ [Post] Comments is a count ($commentsCount) but not a list. Checking for comments_list field...');
        // Try alternative field name for comments list
        final commentsListAlt = json['comments_list'] ?? json['commentsList'];
        if (commentsListAlt != null) {
          print('✅ [Post] Found comments_list field');
        }
      }
    }
    
    // Try alternative field names for comments list
    List<Comment> finalCommentsList = commentsList;
    if (finalCommentsList.isEmpty && commentsCount > 0) {
      final altCommentsList = json['comments_list'] ?? json['commentsList'] ?? json['comment_list'];
      if (altCommentsList != null) {
        finalCommentsList = parseComments(altCommentsList);
      }
    }
    
    // Also check if userId is in the main json
    final userId = userMap?['id']?.toString() ?? 
                   userMap?['user_id']?.toString() ?? 
                   userMap?['userId']?.toString() ??
                   json['user_id']?.toString() ??
                   json['userId']?.toString();
    
    // Also check avatar in main json
    final avatarPath = userMap?['avatar']?.toString() ?? 
                       userMap?['profile_image']?.toString() ??
                       json['avatar']?.toString() ??
                       json['profile_image']?.toString();
    
    return Post(
      id: json['id']?.toString() ?? '',
      author: username ?? 'Unknown User',
      userId: userId,
      avatar: buildAvatarUrl(avatarPath),
      content: json['content'] ?? '',
      image: image,
      likes: parseCount(json['likes']), // 'likes' is missing in PHP, defaults to 0
      comments: commentsCount,
      commentsList: finalCommentsList,
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