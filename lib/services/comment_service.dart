import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/comment.dart';
// import 'dart:io' show Platform;
// import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/constants.dart';

class CommentService {
  Future<void> postComment({
    required String postId,
    required String userId,
    required String content,
    Function(String commentId)? onSuccess,
  }) async {
    // Send plain text content to server (server will handle encryption)
    print('📤 Sending plain text comment to server: "$content"');

    // Make API call to add comment
    final response = await http.post(
      Uri.parse(ApiConstants.addComment),
      body: {
        'postID': postId,
        'userID': userId,
        'content': content,
      },
    );

    if (response.statusCode != 200) {
      print('❌ Comment add API failed with status: ${response.statusCode}');
      print('❌ Response body: ${response.body}');
      throw Exception('Failed to add comment: HTTP ${response.statusCode}');
    }

    // Handle HTML warnings mixed with JSON response
    String responseBody = response.body;
    print('📥 Raw response body: ${response.body}');
    
    if (responseBody.contains('<br />') || responseBody.contains('<b>Warning</b>')) {
      print('⚠️ Response contains HTML warnings, extracting JSON...');
      // Find the JSON part after the HTML warnings
      final jsonStart = responseBody.indexOf('{');
      if (jsonStart != -1) {
        responseBody = responseBody.substring(jsonStart);
        print('✅ Extracted JSON: $responseBody');
      } else {
        print('❌ Could not find JSON in response');
        throw Exception('Invalid response format');
      }
    }

    try {
      final data = json.decode(responseBody);
      if (data['responseCode'] != '1') {
        final message = data['message'] ?? 'Failed to add comment';
        print('❌ Comment add API returned error: $message');
        throw Exception('Failed to add comment: $message');
      }
      
      final commentId = data['commentID']?.toString();
      print('✅ Comment added successfully');
      print('✅ Comment ID: $commentId');
      print('✅ Post ID: ${data['postID']}');
      
      // Call the success callback with the comment ID
      if (commentId != null && commentId.isNotEmpty && onSuccess != null) {
        print('🔄 Calling success callback with comment ID: $commentId');
        onSuccess(commentId);
      } else {
        print('⚠️ No valid comment ID available, skipping immediate fetch');
        // Still call the callback to clear the UI, but with null to indicate no immediate fetch
        if (onSuccess != null) {
          onSuccess('');
        }
      }
      
    } catch (e) {
      print('❌ Error parsing comment add response: $e');
      print('❌ Response body: ${response.body}');
      throw Exception('Failed to parse comment add response: $e');
    }
  }

  Future<Comment> getComment({
    required String commentId,
    String? userId,
  }) async {
    try {
      const url = ApiConstants.getComment;
      final body = {
        'commentID': commentId,
        if (userId != null) 'userID': userId,
      };
      
      print('🔄 [CommentService] Making request to: $url');
      print('🔄 [CommentService] Request body: $body');
      
      final response = await http.post(
        Uri.parse(url),
        body: body,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Flutter Mobile App',
        },
      );

      print('🔄 [CommentService] Response status: ${response.statusCode}');
      print('🔄 [CommentService] Response headers: ${response.headers}');
      print('🔄 [CommentService] Response body: ${response.body}');

      if (response.statusCode != 200) {
        print('❌ Comment get API failed with status: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        throw Exception('Failed to get comment: HTTP ${response.statusCode}');
      }

      // Handle HTML warnings mixed with JSON response
      String responseBody = response.body;
      if (responseBody.contains('<br />') || responseBody.contains('<b>Warning</b>')) {
        print('⚠️ [CommentService] Response contains HTML warnings, extracting JSON...');
        // Find the JSON part after the HTML warnings
        int jsonStart = responseBody.indexOf('[');
        if (jsonStart == -1) {
          jsonStart = responseBody.indexOf('{');
        }
        if (jsonStart != -1) {
          responseBody = responseBody.substring(jsonStart);
          print('✅ [CommentService] Extracted JSON: $responseBody');
        } else {
          print('❌ [CommentService] Could not find JSON in response');
          throw Exception('Invalid response format');
        }
      }

      final data = json.decode(responseBody);
      
      // Handle both array and object responses
      Map<String, dynamic> commentData;
      if (data is List && data.isNotEmpty) {
        commentData = data.first as Map<String, dynamic>;
      } else if (data is Map) {
        commentData = data as Map<String, dynamic>;
      } else {
        throw Exception('Invalid response format: expected array or object');
      }

      if (commentData['responseCode'] != '1') {
        final message = commentData['message'] ?? 'Failed to get comment';
        print('❌ [CommentService] API returned error: $message');
        throw Exception('Failed to get comment: $message');
      }



      return Comment.fromJson(commentData);
    } catch (e) {
      print('❌ [CommentService] Error getting comment: $e');
      throw Exception('Failed to get comment: $e');
    }
  }

  Future<void> deleteComment({
    required String commentId,
    required String userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.deleteComment),
        body: {'commentID': commentId, 'userID': userId},
      );

      if (response.statusCode != 200) {
        print('❌ Comment delete API failed with status: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        throw Exception('Failed to delete comment: HTTP ${response.statusCode}');
      }
      
      try {
        final data = json.decode(response.body);
        if (data['responseCode'] != '1') {
          final message = data['message'] ?? 'Failed to delete comment';
          print('❌ Comment delete API returned error: $message');
          throw Exception(message);
        }
        print('✅ Comment deleted successfully: commentID=$commentId, userID=$userId');
      } catch (e) {
        print('❌ Error parsing comment delete response: $e');
        print('❌ Response body: ${response.body}');
        // If we can't parse the response but got 200, assume success
        print('⚠️ Assuming comment deletion succeeded despite parsing error');
      }
    } catch (e) {
      print('❌ Error in deleteComment for comment $commentId: $e');
      rethrow;
    }
  }
} 