import '../models/post.dart';
import 'dart:convert';
import '../utils/api_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class PostService {
  static const String _cacheKey = 'cached_timeline_posts';
  static const String _cacheTimestampKey = 'cached_timeline_posts_timestamp';
  static const Duration _cacheExpiry = Duration(minutes: 5); // Cache for 5 minutes

  PostService() {
    _checkAndClearLegacyCache();
  }

  /// Checks if we need to clear legacy corrupted cache for the encoding fix
  Future<void> _checkAndClearLegacyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool alreadyFixed = prefs.getBool('encoding_fix_posts_v1_applied') ?? false;
      
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
    final userID = userId;
    
    try {
      // Try to load from cache first
      final cachedPosts = await loadTimelineFromCache();
      if (cachedPosts.isNotEmpty) {
        // Return cached posts immediately, but refresh in background
        _refreshTimelineInBackground(userID);
        return cachedPosts;
      }

      // If no cache, fetch from API
      final posts = await _fetchTimelineFromAPI(userID);
      
      // Cache the posts
      if (posts.isNotEmpty) {
        await _saveTimelineToCache(posts);
      }
      
      return posts;
    } catch (e) {
      // If API fails, try to return cached data as fallback
      final cachedPosts = await loadTimelineFromCache();
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
        final response = await request();
        if (response.statusCode < 500) {
          return response;
        }
        if (response.statusCode >= 500) {
          throw HttpException('Server error: ${response.statusCode}');
        }
        return response;
      } catch (e) {
        attempt++;
        if (!_isTransientError(e) || attempt >= maxRetries) {
          rethrow;
        }
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * 2).clamp(500, 4000));
      }
    }
    throw Exception('Retry logic error');
  }

  Future<List<Post>> _fetchTimelineFromAPI(String? userID) async {
    final response = await _retryHttpRequest(
      () => http.post(
        Uri.parse(ApiConstants.timeline),
        body: {'userID': userID}, 
      ).timeout(const Duration(seconds: 10)),
      maxRetries: 2,
    );
  
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
      
      // Debug: Log first post structure to understand API response
      if (data.isNotEmpty) {
        final firstPost = data.first;
        if (firstPost is Map) {
          if (firstPost.containsKey('user')) {
          }
          if (firstPost.containsKey('comments')) {
          }
        }
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
          if (username == null || username.isEmpty || username.trim().isEmpty) {
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
            posts.add(post);
          } catch (e) {
          }
        }
      }
      
      return posts;
    } else {
      throw Exception('Failed to load posts: ${response.statusCode}');
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
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
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
          DateTime.now().millisecondsSinceEpoch - timestamp > _cacheExpiry.inMilliseconds) {
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
          }
        }
      }
      
      return posts;
    } catch (e) {
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

  Future<List<Post>> fetchUserTimeline({required String userId, String? currentUserId}) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.userTimeline),
        body: {
          'userID': userId,
          if (currentUserId != null) 'currentUserID': currentUserId,
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        // Handle empty response
        if (response.body.isEmpty || response.body.trim().isEmpty) {
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
            final message = decoded['message'] ?? 'Failed to load user timeline';
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
            } catch (e) {
            }
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
      final response = await http.post(
        Uri.parse(ApiConstants.getPost),
        body: {'postID': postId, 'userID': userID},
      ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      try {
        final data = safeJsonDecode(response);
        if (data is List && data.isNotEmpty && data.first['responseCode'] == '1') {
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
    }
 else {
      throw Exception('Failed to load post with status ${response.statusCode}');
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
    final response = await http.post(
      Uri.parse(ApiConstants.deletePost),
      body: {'postID': postId, 'userID': userId},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete post');
    }
    
    // Parse response to check for success
    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to delete post';
      throw Exception(message);
    }
  }

  Future<Map<String, dynamic>> createPost({
    required String userId,
    required String content,
    File? mediaFile,
  }) async {
    // Send plain text content to server (server will handle encryption)

    if (mediaFile == null) {
      final response = await http.post(
        Uri.parse(ApiConstants.addPost),
        body: {
          'userID': userId,
          'content': content,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create post');
      }
      
      final data = safeJsonDecode(response);
      if (data['responseCode'] != '1') {
        final message = data['message'] ?? 'Failed to create post';
        throw Exception(message);
      }
      return data;
    } else {
      // Use MultipartRequest for file upload
      final request = http.MultipartRequest('POST', Uri.parse(ApiConstants.addPost));
      request.fields['userID'] = userId;
      request.fields['content'] = content;
      
      final stream = http.ByteStream(mediaFile.openRead());
      final length = await mediaFile.length();
      
      final multipartFile = http.MultipartFile(
        'file',
        stream,
        length,
        filename: mediaFile.path.split('/').last,
      );
      
      request.files.add(multipartFile);
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to create post');
      }
      
      final data = safeJsonDecode(response);
      if (data['responseCode'] != '1') {
        final message = data['message'] ?? 'Failed to create post';
        throw Exception(message);
      }
      return data;
    }
  }

  Future<void> updatePost({
    required String postId,
    required String userId,
    required String content,
  }) async {
    // Send plain text content to server (server will handle encryption)

    final response = await http.post(
      Uri.parse(ApiConstants.updatePost),
      body: {
        'postID': postId,
        'userID': userId,
        'content': content,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update post');
    }
    
    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to update post';
      throw Exception(message);
    }
  }

} 