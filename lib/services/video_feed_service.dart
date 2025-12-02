import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/video_item.dart';
import '../config/constants.dart';

class VideoFeedService {
  static String get baseUrl => ApiConstants.apiBase;
  
  // HTTP client with standard SSL validation
  static http.Client? _httpClient;
  static http.Client get _client {
    _httpClient ??= _createHttpClient();
    return _httpClient!;
  }
  
  static http.Client _createHttpClient() {
    HttpClient httpClient;
    
    if (HttpOverrides.current != null) {
      httpClient = HttpOverrides.current!.createHttpClient(null);
    } else {
      httpClient = HttpClient();
    }
    
    httpClient.userAgent = 'Skybyn-App/1.0';
    httpClient.connectionTimeout = const Duration(seconds: 30);
    httpClient.idleTimeout = const Duration(seconds: 30);
    httpClient.autoUncompress = true;
    final ioClient = IOClient(httpClient);
    return ioClient;
  }

  /// Fetch videos from the API
  /// 
  /// [page] - Page number for pagination
  /// [limit] - Number of videos to fetch (default: 20)
  /// [userId] - Optional user ID for authenticated requests
  Future<VideoFeedResponse> fetchVideos({
    int page = 1,
    int limit = 20,
    String? userId,
  }) async {
    try {
      final url = Uri.parse(ApiConstants.videoFeed);
      
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'page': page.toString(),
          'limit': limit.toString(),
          if (userId != null) 'userID': userId,
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        
        if (data['responseCode'] == 1) {
          final videosList = data['videos'] as List<dynamic>? ?? [];
          final videos = videosList
              .map((v) => VideoItem.fromJson(v as Map<String, dynamic>))
              .toList();
          
          return VideoFeedResponse(
            videos: videos,
            page: data['page'] as int? ?? page,
            hasMore: data['has_more'] as bool? ?? false,
            totalVideos: data['total_videos'] as int? ?? videos.length,
          );
        } else {
          throw Exception('API returned error: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      return VideoFeedResponse(
        videos: [],
        page: page,
        hasMore: false,
        totalVideos: 0,
        error: e.toString(),
      );
    }
  }

  /// Extract YouTube video ID from URL
  static String? extractYouTubeVideoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    
    if (uri.host.contains('youtube.com') || uri.host.contains('youtu.be')) {
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      } else {
        return uri.queryParameters['v'];
      }
    }
    return null;
  }

  /// Get YouTube embed URL for video player
  static String getYouTubeEmbedUrl(String videoId) {
    return 'https://www.youtube.com/embed/$videoId?autoplay=1&mute=0&controls=0&showinfo=0&rel=0&modestbranding=1&playsinline=1';
  }

  /// Get YouTube direct video URL (for video_player package)
  /// Note: YouTube doesn't provide direct video URLs easily, so we'll use youtube_player_flutter
  static String getYouTubeDirectUrl(String videoId) {
    // This would require using youtube_player_flutter or extracting from YouTube
    // For now, return the watch URL
    return 'https://www.youtube.com/watch?v=$videoId';
  }
}

class VideoFeedResponse {
  final List<VideoItem> videos;
  final int page;
  final bool hasMore;
  final int totalVideos;
  final String? error;

  VideoFeedResponse({
    required this.videos,
    required this.page,
    required this.hasMore,
    required this.totalVideos,
    this.error,
  });

  bool get isSuccess => error == null;
}

