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
      throw Exception('Failed to add comment: HTTP ${response.statusCode}');
    }

    // Handle HTML warnings mixed with JSON response
    String responseBody = response.body;
    if (responseBody.contains('<br />') || responseBody.contains('<b>Warning</b>')) {
      // Find the JSON part after the HTML warnings
      final jsonStart = responseBody.indexOf('{');
      if (jsonStart != -1) {
        responseBody = responseBody.substring(jsonStart);
      } else {
        throw Exception('Invalid response format');
      }
    }

    try {
      final data = json.decode(responseBody);
      if (data['responseCode'] != '1') {
        final message = data['message'] ?? 'Failed to add comment';
        throw Exception('Failed to add comment: $message');
      }
      
      final commentId = data['commentID']?.toString();
      // Call the success callback with the comment ID
      if (commentId != null && commentId.isNotEmpty && onSuccess != null) {
        onSuccess(commentId);
      } else {
        // Still call the callback to clear the UI, but with null to indicate no immediate fetch
        if (onSuccess != null) {
          onSuccess('');
        }
      }
      
    } catch (e) {
      throw Exception('Failed to parse comment add response: $e');
    }
  }

  Future<Comment> getComment({
    required String commentId,
    String? userId,
  }) async {
    try {
      final url = ApiConstants.getComment;
      final body = {
        'commentID': commentId,
        if (userId != null) 'userID': userId,
      };
      final response = await http.post(
        Uri.parse(url),
        body: body,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Flutter Mobile App',
        },
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to get comment: HTTP ${response.statusCode}');
      }

      // Handle HTML warnings mixed with JSON response
      String responseBody = response.body;
      if (responseBody.contains('<br />') || responseBody.contains('<b>Warning</b>')) {
        // Find the JSON part after the HTML warnings
        int jsonStart = responseBody.indexOf('[');
        if (jsonStart == -1) {
          jsonStart = responseBody.indexOf('{');
        }
        if (jsonStart != -1) {
          responseBody = responseBody.substring(jsonStart);
        } else {
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
        throw Exception('Failed to get comment: $message');
      }



      return Comment.fromJson(commentData);
    } catch (e) {
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
        throw Exception('Failed to delete comment: HTTP ${response.statusCode}');
      }
      
      try {
        final data = json.decode(response.body);
        if (data['responseCode'] != '1') {
          final message = data['message'] ?? 'Failed to delete comment';
          throw Exception(message);
        }
      } catch (e) {
        // If we can't parse the response but got 200, assume success
      }
    } catch (e) {
      rethrow;
    }
  }
} 