import 'package:flutter/foundation.dart';
import '../models/post.dart';
import 'dart:convert';
import '../utils/api_utils.dart';
import '../utils/image_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../utils/http_client.dart';
import 'user_cache_service.dart';

class PostService {
  static const String _cacheKey = 'cached_timeline_posts';
  static const String _cacheTimestampKey = 'cached_timeline_posts_timestamp';
  static const Duration _cacheExpiry =
      Duration(minutes: 30); // Cache for 30 minutes

  PostService() {
    _checkAndClearLegacyCache();
  }

  /// Checks if we need to clear legacy corrupted cache for the encoding fix
  Future<void> _checkAndClearLegacyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool alreadyFixed =
          prefs.getBool('encoding_fix_posts_v1_applied') ?? false;

      if (!alreadyFixed) {
        // Clear timeline keys
        await prefs.remove(_cacheKey);
        await prefs.remove(_cacheTimestampKey);
        await prefs.setBool('encoding_fix_posts_v1_applied', true);
      }
    } catch (e) {
      // Ignore errors
    }
  }

  Future<List<Post>> fetchPostsForUser({String? userId}) async {
    if (kDebugMode) debugPrint('PostService: fetchPostsForUser called');
    final userID = userId;

    try {
      debugPrint('PostService: fetchPostsForUser: Checking cache...');
      // Try to load from cache first
      final cachedPosts = await loadTimelineFromCache();
      if (cachedPosts.isNotEmpty) {
        debugPrint(
            'PostService: fetchPostsForUser: Cache HIT (${cachedPosts.length} posts)');
        // Return cached posts immediately, but refresh in background
        _refreshTimelineInBackground(userID);
        return cachedPosts;
      }
      debugPrint('PostService: fetchPostsForUser: Cache MISS');

      // If no cache, fetch from API
      debugPrint('PostService: fetchPostsForUser: Calling _fetchTimelineFromAPI...');
      final posts = await _fetchTimelineFromAPI(userID);
      debugPrint(
          'PostService: fetchPostsForUser: _fetchTimelineFromAPI returned ${posts.length} posts');

      // Cache the posts
      if (posts.isNotEmpty) {
        await _saveTimelineToCache(posts);
      }

      return posts;
    } catch (e) {
      debugPrint('PostService: fetchPostsForUser: ERROR: $e');
      // If API fails, try to return cached data as fallback
      final cachedPosts = await loadTimelineFromCache();
      debugPrint(
          'PostService: fetchPostsForUser: Returning ${cachedPosts.length} fallback cached posts');
      return cachedPosts;
    }
  }

  /// Check if an exception is a transient network error that should be retried
  bool _isTransientError(dynamic error) {
    if (error is SocketException) return true;
    if (error is HandshakeException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) {
      final message = error.message.toLowerCase();
      return message.contains('connection') ||
          message.contains('timeout') ||
          message.contains('reset');
    }
    return false;
  }

  /// Retry an HTTP request with exponential backoff
  Future<http.Response> _retryHttpRequest(
    Future<http.Response> Function() request, {
    int maxRetries = 2,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        debugPrint('PostService: Sending API request (Attempt ${attempt + 1})...');
        final response = await request();
        debugPrint(
            'PostService: Received response with status: ${response.statusCode}');
        if (response.statusCode >= 400) {
          if (kDebugMode) debugPrint('PostService: Error Response Body: ${response.body}');
        }
        if (response.statusCode < 500) {
          return response;
        }
        if (response.statusCode >= 500) {
          throw HttpException('Server error: ${response.statusCode}');
        }
        return response;
      } catch (e) {
        debugPrint('PostService: Request attempt ${attempt + 1} failed: $e');
        attempt++;
        if (!_isTransientError(e) || attempt >= maxRetries) {
          debugPrint(
              'PostService: Non-transient or final attempt reached. Rethrowing.');
          rethrow;
        }
        debugPrint(
            'PostService: Transient error, retrying in ${delay.inMilliseconds}ms...');
        await Future.delayed(delay);
        delay =
            Duration(milliseconds: (delay.inMilliseconds * 2).clamp(500, 4000));
      }
    }
    throw Exception('Retry logic error');
  }

  Future<List<Post>> _fetchTimelineFromAPI(String? userID) async {
    debugPrint('PostService: Fetching timeline (userID: $userID)');
    if (userID == null || userID.isEmpty) {
      debugPrint('PostService: userID is null/empty, skipping API call');
      return [];
    }
    try {
      final response = await _retryHttpRequest(
        () => globalAuthClient.post(
          Uri.parse(ApiConstants.timeline),
          body: {'userID': userID},
        ).timeout(const Duration(seconds: 10)),
        maxRetries: 2,
      );

      debugPrint(
          '@@@ PostService: Timeline API Response Status: ${response.statusCode}');
      if (kDebugMode) {
        String bodySnippet = response.body.length > 500
            ? '${response.body.substring(0, 500)}...'
            : response.body;
        debugPrint(
            '@@@ PostService: Timeline API Response Body Snippet: $bodySnippet');
      }

      if (response.statusCode == 200) {
        final decoded = safeJsonDecode(response);

        // Handle API response format: feed API now returns direct array
        // But handle both formats for backward compatibility
        List<dynamic> data = [];
        if (decoded is List) {
          // Direct array format (expected format)
          data = decoded;
        } else if (decoded is Map) {
          // Wrapped format (backward compatibility): {"responseCode": "1", "data": [...]}
          if (decoded['responseCode'] == '1' || decoded['responseCode'] == 1) {
            if (decoded.containsKey('data') && decoded['data'] is List) {
              data = decoded['data'];
            } else {
              // No data field or empty response - new user with no posts
              data = [];
            }
          } else {
            // Error response
            throw Exception(decoded['message'] ?? 'Failed to load posts');
          }
        }

        debugPrint('PostService: Decoded timeline data length: ${data.length}');

        // Detailed log of first post structure if available
        if (data.isNotEmpty) {
          final firstPost = data.first;
          debugPrint('PostService: First post structure: $firstPost');
        }

        final List<Post> posts = [];
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            // Debug: Log post data before parsing
            final userData = item['user'];
            final username = userData is Map
                ? userData['username']?.toString()
                : (item['username']?.toString());
            final content = item['content']?.toString() ?? '';
            // Filter out posts with empty username or empty content
            if (username == null ||
                username.isEmpty ||
                username.trim().isEmpty) {
              continue;
            }

            if (content.isEmpty || content.trim().isEmpty) {
              continue;
            }

            try {
              final post = Post.fromJson(item);
              // Double-check after parsing
              if (post.author == 'Unknown User' || post.author.isEmpty) {
                continue;
              }
              if (post.content.isEmpty || post.content.trim().isEmpty) {
                continue;
              }
              // Populate user cache from post data
              if (post.userId != null) {
                final userMap = item['user'];
                UserCacheService().store(
                  post.userId!,
                  username: userMap is Map ? userMap['username']?.toString() : null,
                  displayname: userMap is Map ? userMap['displayname']?.toString() : null,
                  avatar: post.avatar,
                );
              }
              posts.add(post);
            } catch (e) {}
          }
        }

        debugPrint(
            'PostService: Successfully parsed ${posts.length} timeline posts');
        return posts;
      } else {
        debugPrint(
            'PostService: Error fetching timeline: Status ${response.statusCode}');
        throw Exception('Failed to load posts: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('PostService: Exception caught in _fetchTimelineFromAPI: $e');
      rethrow;
    }
  }

  Future<void> _refreshTimelineInBackground(String? userID) async {
    // Refresh in background without blocking
    Future.delayed(const Duration(milliseconds: 100), () async {
      try {
        final posts = await _fetchTimelineFromAPI(userID);
        if (posts.isNotEmpty) {
          await _saveTimelineToCache(posts);
        }
      } catch (e) {
        // Silently fail - we already have cached data
      }
    });
  }

  Future<void> _saveTimelineToCache(List<Post> posts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final postsJson = posts.map((p) => p.toJson()).toList();
      await prefs.setString(_cacheKey, jsonEncode(postsJson));
      await prefs.setInt(
          _cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Silently fail if caching fails
    }
  }

  Future<List<Post>> loadTimelineFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);

      // Check if cache is expired
      if (timestamp == null ||
          DateTime.now().millisecondsSinceEpoch - timestamp >
              _cacheExpiry.inMilliseconds) {
        return [];
      }

      final postsJson = prefs.getString(_cacheKey);
      if (postsJson == null) return [];

      final List<dynamic> decoded = jsonDecode(postsJson);
      final List<Post> posts = [];

      // Filter out posts with empty usernames or content when loading from cache
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            final post = Post.fromJson(item);
            // Skip posts with "Unknown User" or empty content
            if (post.author == 'Unknown User' || post.author.isEmpty) {
              continue;
            }
            if (post.content.isEmpty || post.content.trim().isEmpty) {
              continue;
            }
            posts.add(post);
          } catch (e) {
            debugPrint('PostService: Failed to parse post item: $e');
          }
        }
      }

      return posts;
    } catch (e) {
      debugPrint('PostService: fetchUserTimeline error: $e');
      return [];
    }
  }

  Future<void> clearTimelineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
    } catch (e) {
      // Silently fail if clearing fails
    }
  }

  Future<List<Post>> fetchUserTimeline(
      {required String userId, String? currentUserId}) async {
    try {
      debugPrint(
          'PostService: Fetching user timeline for user: $userId, currentUserID: $currentUserId');
      final requestBody = {
        'profileID': userId,
        if (currentUserId != null) 'currentUserID': currentUserId,
      };
      debugPrint(
          'PostService: User Timeline API Request URL: ${ApiConstants.timeline}');
      debugPrint('PostService: User Timeline API Request Body: $requestBody');

      final response = await globalAuthClient
          .post(
            Uri.parse(ApiConstants.timeline),
            body: requestBody,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint(
          'PostService: User Timeline API Response Status: ${response.statusCode}');
      debugPrint(
          'PostService: User Timeline API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        // Handle empty response
        if (response.body.isEmpty || response.body.trim().isEmpty) {
          debugPrint('PostService: User Timeline API returned empty body.');
          return [];
        }

        final decoded = safeJsonDecode(response);

        // Handle different response formats
        List<dynamic> data = [];
        if (decoded is List) {
          // Direct array format
          data = decoded;
        } else if (decoded is Map) {
          // Wrapped format: {"responseCode": "1", "data": [...]}
          if (decoded['responseCode'] == '1' || decoded['responseCode'] == 1) {
            if (decoded.containsKey('data') && decoded['data'] is List) {
              data = decoded['data'];
            } else {
              // No data field or empty response
              data = [];
            }
          } else {
            // Error response
            final message =
                decoded['message'] ?? 'Failed to load user timeline';
            throw Exception(message);
          }
        }
        final List<Post> posts = [];
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            try {
              final post = Post.fromJson(item);
              // Log post details for debugging
              posts.add(post);
            } catch (e) {}
          }
        }
        return posts;
      } else {
        throw Exception('Failed to load user timeline: ${response.statusCode}');
      }
    } catch (e) {
      return [];
    }
  }

  Future<Post> fetchPost({required String postId, String? userId}) async {
    // Use a default user ID for testing if none provided
    final userID = userId;

    try {
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.timeline),
        body: {'action': 'get', 'postID': postId, 'userID': userID},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        try {
          final data = safeJsonDecode(response);
          if (data is List &&
              data.isNotEmpty &&
              data.first['responseCode'] == '1') {
            final postMap = data.first as Map<String, dynamic>;
            return Post.fromJson(postMap);
          } else if (data is Map && data['responseCode'] == '1') {
            return Post.fromJson(data as Map<String, dynamic>);
          } else {
            final message = (data is List && data.isNotEmpty)
                ? data.first['message']
                : (data is Map ? data['message'] : 'Post not found');
            throw Exception('Failed to load post: $message');
          }
        } catch (e) {
          throw Exception('Failed to parse API response: $e');
        }
      } else {
        throw Exception(
            'Failed to load post with status ${response.statusCode}');
      }
    } catch (e) {
      // Return a default post instead of throwing to prevent app from hanging
      return Post(
        id: postId,
        author: 'Unknown User',
        userId: userID ?? 'unknown',
        content: 'Post unavailable due to network error',
        likes: 0,
        comments: 0,
        commentsList: [],
        createdAt: DateTime.now(),
        isLiked: false,
      );
    }
  }

  Future<void> deletePost({
    required String postId,
    required String userId,
  }) async {
    debugPrint('[PostService] deletePost: postId=$postId userId=$userId');
    final response = await globalAuthClient.post(
      Uri.parse(ApiConstants.timeline),
      body: {'action': 'delete', 'postID': postId, 'userID': userId},
    );
    debugPrint('[PostService] deletePost: status=${response.statusCode} body=${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Failed to delete post');
    }

    // Parse response to check for success
    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to delete post';
      throw Exception(message);
    }
    debugPrint('[PostService] deletePost: success');

    // Remove deleted post from cache immediately
    final cached = await loadTimelineFromCache();
    if (cached.isNotEmpty) {
      cached.removeWhere((p) => p.id == postId);
      await _saveTimelineToCache(cached);
    }
  }

  Future<Map<String, dynamic>> createPost({
    required String userId,
    required String content,
    File? mediaFile,
    bool isVideo = false,
    String? mediaUrl,
  }) async {
    debugPrint('[PostService] createPost: userId=$userId hasFile=${mediaFile != null} isVideo=$isVideo mediaUrl=$mediaUrl');
    if (mediaFile == null) {
      final body = <String, String>{
        'action': 'add',
        'userID': userId,
        'content': content,
      };
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        body['media_url'] = mediaUrl;
      }
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.timeline),
        body: body,
      );

      debugPrint('[PostService] createPost: status=${response.statusCode} body=${response.body}');
      if (response.statusCode != 200) {
        throw Exception('Failed to create post');
      }

      final data = safeJsonDecode(response);
      if (data['responseCode'] != '1') {
        final message = data['message'] ?? 'Failed to create post';
        throw Exception(message);
      }
      debugPrint('[PostService] createPost: success postId=${data['postID']}');
      return data;
    } else {
      // Compress images only — skip compression for videos
      final File processedFile =
          isVideo ? mediaFile : await ImageUtils.compressImage(mediaFile);

      final request =
          http.MultipartRequest('POST', Uri.parse(ApiConstants.timeline));
      request.fields['action'] = 'add';
      request.fields['userID'] = userId;
      request.fields['content'] = content;
      if (isVideo) request.fields['media_type'] = 'video';

      final length = await processedFile.length();
      final stream = http.ByteStream(processedFile.openRead());
      final filename = processedFile.path.split(RegExp(r'[/\\]')).last;

      request.files.add(http.MultipartFile(
        'file',
        stream,
        length,
        filename: filename,
      ));

      // Send through globalAuthClient so auth headers are included
      final streamedResponse = await globalAuthClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('[PostService] createPost (file): status=${response.statusCode} body=${response.body}');
      if (response.statusCode != 200) {
        throw Exception('Failed to create post');
      }

      final data = safeJsonDecode(response);
      if (data['responseCode'] != '1') {
        final message = data['message'] ?? 'Failed to create post';
        throw Exception(message);
      }
      debugPrint('[PostService] createPost (file): success postId=${data['postID']}');
      return data;
    }
  }

  Future<void> updatePost({
    required String postId,
    required String userId,
    required String content,
  }) async {
    debugPrint('[PostService] updatePost: postId=$postId userId=$userId');
    // Send plain text content to server (server will handle encryption)

    final response = await globalAuthClient.post(
      Uri.parse(ApiConstants.timeline),
      body: {
        'action': 'edit',
        'postID': postId,
        'userID': userId,
        'content': content,
      },
    );

    debugPrint('[PostService] updatePost: status=${response.statusCode} body=${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Failed to update post');
    }

    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to update post';
      throw Exception(message);
    }
    debugPrint('[PostService] updatePost: success');
  }

  /// Returns a map with 'liked' (bool) and 'likeCount' (int) from the server.
  Future<Map<String, dynamic>> toggleLike({required String postId}) async {
    debugPrint('[PostService] toggleLike: postId=$postId');
    final response = await globalAuthClient.post(
      Uri.parse(ApiConstants.timeline),
      body: {'action': 'like', 'postID': postId},
    );

    debugPrint('[PostService] toggleLike: status=${response.statusCode} body=${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Failed to toggle like');
    }

    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to toggle like';
      throw Exception(message);
    }

    final liked = data['liked'] == true || data['liked'] == 1 || data['liked'] == '1';
    final likeCount = int.tryParse(data['likeCount']?.toString() ?? '') ?? -1;
    debugPrint('[PostService] toggleLike: success liked=$liked likeCount=$likeCount');
    return {'liked': liked, 'likeCount': likeCount};
  }

  Future<void> hidePost({
    required String postId,
    required String userId,
  }) async {
    debugPrint('[PostService] hidePost: postId=$postId userId=$userId');
    final response = await globalAuthClient.post(
      Uri.parse(ApiConstants.timeline),
      body: {'action': 'hide', 'postID': postId, 'userID': userId},
    );

    debugPrint('[PostService] hidePost: status=${response.statusCode} body=${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Failed to hide post');
    }

    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to hide post';
      throw Exception(message);
    }
    debugPrint('[PostService] hidePost: success');
  }

  Future<void> reportPost({
    required String postId,
    required String userId,
    required String reason,
  }) async {
    debugPrint('[PostService] reportPost: postId=$postId userId=$userId reason=$reason');
    final response = await globalAuthClient.post(
      Uri.parse(ApiConstants.report),
      body: {
        'postID': postId,
        'userID': userId,
        'reason': reason,
        'type': 'post'
      },
    );

    debugPrint('[PostService] reportPost: status=${response.statusCode} body=${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Failed to report post');
    }

    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to report post';
      throw Exception(message);
    }
    debugPrint('[PostService] reportPost: success');
  }
}
