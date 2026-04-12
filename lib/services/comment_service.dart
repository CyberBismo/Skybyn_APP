import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/api_utils.dart';
import '../utils/http_client.dart';
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
    debugPrint('[CommentService] postComment: postId=$postId userId=$userId');
    // Send plain text content to server (server will handle encryption)
    // Make API call to add comment
    final response = await globalAuthClient.post(
      Uri.parse(ApiConstants.comment),
      body: {
        'action': 'add',
        'postID': postId,
        'userID': userId,
        'content': content,
      },
    );

    debugPrint('[CommentService] postComment: status=${response.statusCode} body=${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Failed to add comment: HTTP ${response.statusCode}');
    }

    try {
      final data = safeJsonDecode(response);
      if (data['responseCode'] != '1') {
        final message = data['message'] ?? 'Failed to add comment';
        throw Exception('Failed to add comment: $message');
      }

      final commentId = data['commentID']?.toString();
      debugPrint('[CommentService] postComment: success commentId=$commentId');
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
      final url = ApiConstants.comment;
      final body = {
        'action': 'get',
        'commentID': commentId,
        if (userId != null) 'userID': userId,
      };
      final response = await globalAuthClient.post(
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

      final data = safeJsonDecode(response);

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
    debugPrint('[CommentService] deleteComment: commentId=$commentId userId=$userId');
    try {
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.comment),
        body: {
          'action': 'delete',
          'commentID': commentId,
          'userID': userId
        },
      );

      debugPrint('[CommentService] deleteComment: status=${response.statusCode} body=${response.body}');
      if (response.statusCode != 200) {
        throw Exception(
            'Failed to delete comment: HTTP ${response.statusCode}');
      }

      try {
        final data = safeJsonDecode(response);
        if (data['responseCode'] != '1') {
          final message = data['message'] ?? 'Failed to delete comment';
          throw Exception(message);
        }
        debugPrint('[CommentService] deleteComment: success');
      } catch (e) {
        // If we can't parse the response but got 200, assume success
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateComment({
    required String commentId,
    required String userId,
    required String content,
  }) async {
    debugPrint('[CommentService] updateComment: commentId=$commentId userId=$userId');
    final response = await globalAuthClient.post(
      Uri.parse(ApiConstants.comment),
      body: {
        'action': 'edit',
        'commentID': commentId,
        'userID': userId,
        'content': content,
      },
    );

    debugPrint('[CommentService] updateComment: status=${response.statusCode} body=${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Failed to update comment');
    }

    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to update comment';
      throw Exception(message);
    }
    debugPrint('[CommentService] updateComment: success');
  }

  Future<void> reportComment({
    required String commentId,
    required String userId,
    required String reason,
  }) async {
    debugPrint('[CommentService] reportComment: commentId=$commentId userId=$userId reason=$reason');
    final response = await globalAuthClient.post(
      Uri.parse(ApiConstants.report),
      body: {
        'commentID': commentId,
        'userID': userId,
        'reason': reason,
        'type': 'comment'
      },
    );

    debugPrint('[CommentService] reportComment: status=${response.statusCode} body=${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Failed to report comment');
    }

    final data = safeJsonDecode(response);
    if (data['responseCode'] != '1') {
      final message = data['message'] ?? 'Failed to report comment';
      throw Exception(message);
    }
    debugPrint('[CommentService] reportComment: success');
  }
}
