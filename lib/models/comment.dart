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
        print('🔍 [Comment] Avatar path is null or empty');
        return null;
      }
      if (path.startsWith('http')) {
        print('🔍 [Comment] Avatar path is already a full URL: $path');
        return path;
      }
      
      // Handle relative paths like "../" or "..\/"
      String cleanPath = path;
      print('🔍 [Comment] Original avatar path: $path');
      
      // Replace escaped slashes with regular slashes
      cleanPath = cleanPath.replaceAll('\\/', '/');
      print('🔍 [Comment] After replacing escaped slashes: $cleanPath');
      
      // Remove any leading dots or slashes to prevent URL malformation
      cleanPath = cleanPath.replaceFirst(RegExp(r'^[\.\/]+'), '');
      print('🔍 [Comment] After removing leading dots/slashes: $cleanPath');
      
      // If the path is empty after cleaning, return null
      if (cleanPath.isEmpty) {
        print('🔍 [Comment] Avatar path is empty after cleaning, returning null');
        return null;
      }
      
      // If the path doesn't start with uploads/, add it
      if (!cleanPath.startsWith('uploads/')) {
        cleanPath = 'uploads/$cleanPath';
        print('🔍 [Comment] Added uploads/ prefix: $cleanPath');
      }
      
      final finalUrl = 'https://skybyn.com/$cleanPath';
      print('🔍 [Comment] Final avatar URL: $finalUrl');
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
} 