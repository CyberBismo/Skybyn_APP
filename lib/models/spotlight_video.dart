class SpotlightVideo {
  final String id;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;

  const SpotlightVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
  });

  factory SpotlightVideo.fromYouTube(Map<String, dynamic> json) {
    final snippet = json['snippet'] as Map<String, dynamic>;
    final thumbnails = snippet['thumbnails'] as Map<String, dynamic>;
    final thumbUrl = (thumbnails['high']?['url'] ??
        thumbnails['medium']?['url'] ??
        thumbnails['default']?['url'] ??
        '') as String;

    return SpotlightVideo(
      id: json['id']['videoId'] as String,
      title: snippet['title'] as String? ?? '',
      channelTitle: snippet['channelTitle'] as String? ?? '',
      thumbnailUrl: thumbUrl,
    );
  }
}
