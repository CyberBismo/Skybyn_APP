import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/spotlight_video.dart';
import '../config/constants.dart';

class SpotlightService {
  static const String _baseUrl = 'https://www.googleapis.com/youtube/v3';

  String? _nextPageToken;
  bool _isExhausted = false;

  bool get hasMore => !_isExhausted;

  Future<List<SpotlightVideo>> fetchVideos({bool refresh = false}) async {
    if (refresh) {
      _nextPageToken = null;
      _isExhausted = false;
    }

    if (_isExhausted) return [];

    final params = <String, String>{
      'part': 'snippet',
      'type': 'video',
      'videoDimension': 'tall', // portrait videos only
      'q': '%23shorts',
      'maxResults': '15',
      'safeSearch': 'moderate',
      'key': ApiConstants.youtubeApiKey,
    };

    if (_nextPageToken != null && _nextPageToken!.isNotEmpty) {
      params['pageToken'] = _nextPageToken!;
    }

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: params);

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('YouTube API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _nextPageToken = data['nextPageToken'] as String?;
    if (_nextPageToken == null) _isExhausted = true;

    final items = (data['items'] as List<dynamic>)
        .where((item) => item['id']?['videoId'] != null)
        .map((item) => SpotlightVideo.fromYouTube(item as Map<String, dynamic>))
        .toList();

    return items;
  }
}
