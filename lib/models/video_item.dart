class VideoItem {
  final String id;
  final String userId;
  final String username;
  final String nickname;
  final String? avatar;
  final String videoUrl;
  final String videoType; // 'youtube', 'tiktok', etc.
  final String content;
  final DateTime createdAt;
  final int likes;
  final int comments;
  final String source; // 'youtube', 'tiktok', etc.

  VideoItem({
    required this.id,
    required this.userId,
    required this.username,
    required this.nickname,
    this.avatar,
    required this.videoUrl,
    required this.videoType,
    required this.content,
    required this.createdAt,
    this.likes = 0,
    this.comments = 0,
    required this.source,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? json['username']?.toString() ?? '',
      avatar: json['avatar']?.toString(),
      videoUrl: json['video_url']?.toString() ?? json['videoUrl']?.toString() ?? '',
      videoType: json['video_type']?.toString() ?? json['videoType']?.toString() ?? 'youtube',
      content: json['content']?.toString() ?? '',
      createdAt: json['created'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['created'] is int ? json['created'] : int.tryParse(json['created'].toString()) ?? 0) * 1000)
          : DateTime.now(),
      likes: json['likes'] is int ? json['likes'] : (int.tryParse(json['likes']?.toString() ?? '0') ?? 0),
      comments: json['comments'] is int ? json['comments'] : (int.tryParse(json['comments']?.toString() ?? '0') ?? 0),
      source: json['source']?.toString() ?? json['video_type']?.toString() ?? 'youtube',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'nickname': nickname,
      'avatar': avatar,
      'video_url': videoUrl,
      'video_type': videoType,
      'content': content,
      'created': createdAt.millisecondsSinceEpoch ~/ 1000,
      'likes': likes,
      'comments': comments,
      'source': source,
    };
  }
}

