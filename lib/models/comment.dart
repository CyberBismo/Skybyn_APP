class Comment {
  final String id;
  final String userId;
  final String username;
  final String? avatar;
  final String content;

  Comment({
    required this.id,
    required this.userId,
    required this.username,
    this.avatar,
    required this.content,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
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

    return Comment(
      id: json['id']?.toString() ?? '',
      userId: json['user']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Unknown User',
      avatar: buildAvatarUrl(json['avatar']?.toString()),
      content: json['content'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user': userId, // Keep 'user' for API compatibility
      'userId': userId, // Add 'userId' for clarity
      'username': username,
      'avatar': avatar,
      'content': content,
    };
  }
} 