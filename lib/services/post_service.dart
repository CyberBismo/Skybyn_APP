import '../models/post.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PostService {
  Future<List<Post>> fetchPostsForUser({String? userId}) async {
    // Use a default user ID for testing if none provided
    final userID = userId;
    
    try {
      final response = await http.post(
        Uri.parse('https://api.skybyn.no/post/timeline.php'),
        body: {'userID': userID}, 
      ).timeout(const Duration(seconds: 10));
    
    print('Fetching posts for user: $userID');
    print('API Response status: ${response.statusCode}');
    print('API Response body: ${response.body}');
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      print('Parsed ${data.length} posts from API');
      
      final List<Post> posts = [];
      for (final item in data) {
        final postMap = item as Map<String, dynamic>;
        posts.add(Post.fromJson(postMap));
      }
      
      return posts;
    } else {
      print('API Error: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to load posts: ${response.statusCode}');
    }
    } catch (e) {
      print('❌ Network error or timeout while fetching posts: $e');
      // Return empty list instead of throwing to prevent app from hanging
      return [];
    }
  }

  Future<List<Post>> fetchUserTimeline({required String userId, String? currentUserId}) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.skybyn.no/post/user-timeline.php'),
        body: {
          'userID': userId,
          if (currentUserId != null) 'currentUserID': currentUserId,
        },
      ).timeout(const Duration(seconds: 10));
    
    print('Fetching user timeline for user: $userId');
    print('API Response status: ${response.statusCode}');
    print('API Response body: ${response.body}');
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      print('Parsed ${data.length} posts from user timeline API');
      
      final List<Post> posts = [];
      for (final item in data) {
        final postMap = item as Map<String, dynamic>;
        posts.add(Post.fromJson(postMap));
      }
      
      return posts;
    } else {
      print('API Error: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to load user timeline: ${response.statusCode}');
    }
    } catch (e) {
      print('❌ Network error or timeout while fetching user timeline: $e');
      // Return empty list instead of throwing to prevent app from hanging
      return [];
    }
  }

  Future<Post> fetchPost({required String postId, String? userId}) async {
    // Use a default user ID for testing if none provided
    final userID = userId;
    
    try {
      final response = await http.post(
        Uri.parse('https://api.skybyn.no/post/get_post.php'),
        body: {'postID': postId, 'userID': userID},
      ).timeout(const Duration(seconds: 10));
    
    print('📡 Fetching post $postId for user $userID');
    print('📡 API Response status: ${response.statusCode}');
    print('📡 API Response body: ${response.body}');
    
    if (response.statusCode == 200) {
      // Check if response contains HTML warnings mixed with JSON
      String responseBody = response.body;
      
      // If response starts with HTML, try to extract JSON from the end
      if (responseBody.trim().startsWith('<')) {
        print('⚠️ API returned HTML warnings mixed with JSON, attempting to extract JSON...');
        
        // Look for JSON array at the end of the response
        final jsonMatch = RegExp(r'\[.*\]$', dotAll: true).firstMatch(responseBody);
        if (jsonMatch != null) {
          responseBody = jsonMatch.group(0)!;
          print('✅ Extracted JSON from mixed response: ${responseBody.length > 100 ? '${responseBody.substring(0, 100)}...' : responseBody}');
        } else {
          print('❌ Could not extract JSON from mixed response');
          throw Exception('API returned invalid response format (HTML without JSON)');
        }
      }
      
      try {
        final List<dynamic> data = json.decode(responseBody);
        if (data.isNotEmpty && data.first['responseCode'] == '1') {
          final postMap = data.first as Map<String, dynamic>;
          return Post.fromJson(postMap);
        } else {
          final message = data.isNotEmpty ? data.first['message'] : 'Post not found';
          print('❌ API returned error: $message');
          throw Exception('Failed to load post: $message');
        }
      } catch (e) {
        print('❌ Error parsing JSON response: $e');
        print('❌ Response body: ${response.body}');
        throw Exception('Failed to parse API response: $e');
      }
    } else {
      print('❌ API request failed with status: ${response.statusCode}');
      throw Exception('Failed to load post with status ${response.statusCode}');
    }
    } catch (e) {
      print('❌ Network error or timeout while fetching post: $e');
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
    print('🗑️ Attempting to delete post: postID=$postId, userID=$userId');
    
    final response = await http.post(
      Uri.parse('https://api.skybyn.no/post/delete.php'),
      body: {'postID': postId, 'userID': userId},
    );

    print('📡 Delete API Response status: ${response.statusCode}');
    print('📡 Delete API Response body: ${response.body}');

    if (response.statusCode != 200) {
      print('❌ Delete failed with HTTP status: ${response.statusCode}');
      throw Exception('Failed to delete post');
    }
    
    // Parse response to check for success
    final data = json.decode(response.body);
    print('📋 Parsed response data: $data');
    
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to delete post';
      print('❌ Delete failed with response code: ${data['responseCode']}, message: $message');
      throw Exception(message);
    }
    
    print('✅ Post deleted successfully: postID=$postId, userID=$userId');
  }

  Future<Map<String, dynamic>> createPost({
    required String userId,
    required String content,
  }) async {
    // Send plain text content to server (server will handle encryption)
    print('📤 Sending plain text post content to server: "${content.length > 50 ? '${content.substring(0, 50)}...' : content}"');

    final response = await http.post(
      Uri.parse('https://api.skybyn.no/post/add.php'),
      body: {
        'userID': userId,
        'content': content,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create post');
    }
    
    final data = json.decode(response.body);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to create post';
      throw Exception(message);
    }
    
    print('Post created successfully: userID=$userId');
    return data;
  }

  Future<void> updatePost({
    required String postId,
    required String userId,
    required String content,
  }) async {
    // Send plain text content to server (server will handle encryption)
    print('📤 Sending plain text post update to server: "${content.length > 50 ? '${content.substring(0, 50)}...' : content}"');

    final response = await http.post(
      Uri.parse('https://api.skybyn.no/post/update.php'),
      body: {
        'postID': postId,
        'userID': userId,
        'content': content,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update post');
    }
    
    final data = json.decode(response.body);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to update post';
      throw Exception(message);
    }
    
    print('Post updated successfully: postID=$postId, userID=$userId');
  }
} 