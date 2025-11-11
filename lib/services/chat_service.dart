import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../config/constants.dart';
import 'auth_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

class ChatService {
  static const String _cacheKeyPrefix = 'cached_messages_';
  static const String _cacheTimestampPrefix = 'cached_messages_timestamp_';
  static const Duration _cacheExpiry = Duration(minutes: 2);

  final AuthService _authService = AuthService();
  
  // Use the same HTTP client pattern as AuthService to ensure consistent SSL handling
  static http.Client? _httpClient;
  static http.Client get _client {
    if (_httpClient == null) {
      _httpClient = _createHttpClient();
    }
    return _httpClient!;
  }
  
  static http.Client _createHttpClient() {
    HttpClient httpClient;
    
    // In release mode, use standard HttpClient with proper SSL validation
    // In debug mode, use HttpOverrides if available (which should have SSL bypass)
    if (HttpOverrides.current != null) {
      httpClient = HttpOverrides.current!.createHttpClient(null);
    } else {
      httpClient = HttpClient();
    }
    
    // Set timeouts and user agent
    httpClient.userAgent = 'Skybyn-App/1.0';
    httpClient.connectionTimeout = const Duration(seconds: 30);
    httpClient.idleTimeout = const Duration(seconds: 30);
    httpClient.autoUncompress = true;
    
    return IOClient(httpClient);
  }

  /// Get encryption key from stored user token
  Future<String> _getEncryptionKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userProfileJson = prefs.getString(StorageKeys.userProfile);
      if (userProfileJson != null) {
        final userProfile = jsonDecode(userProfileJson);
        final token = userProfile['token'] as String?;
        if (token != null && token.isNotEmpty) {
          // Use first 32 characters of token hash as encryption key
          final bytes = utf8.encode(token);
          final hash = sha256.convert(bytes);
          return hash.toString().substring(0, 32);
        }
      }
    } catch (e) {
      print('❌ [ChatService] Error getting encryption key: $e');
    }
    // Fallback key (should not happen in production)
    return 'defaultkey123456789012345678901234';
  }

  /// Encrypt message content (server will encrypt, but we send plain text)
  /// The server's encrypt() function handles encryption
  Future<String> _encryptMessage(String message) async {
    // Server handles encryption, so we just return the message
    return message;
  }

  /// Decrypt message content (server already decrypts in API response)
  Future<String> _decryptMessage(String message) async {
    // Server already returns decrypted content
    return message;
  }

  /// Send a message
  Future<Message?> sendMessage({
    required String toUserId,
    required String content,
  }) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Encrypt the message
      final encryptedContent = await _encryptMessage(content);

      final url = ApiConstants.chatSend;
      if (kDebugMode) {
        print('🔧 [ChatService] Sending message to: $url');
      }
      
      final response = await _retryHttpRequest(
        () => _client.post(
          Uri.parse(url),
          body: {
            'userID': userId,
            'from': userId,
            'to': toUserId,
            'message': encryptedContent,
          },
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ).timeout(const Duration(seconds: 10)),
        maxRetries: 2,
      );

      if (kDebugMode) {
        print('📥 [ChatService] Response status: ${response.statusCode}');
        print('📥 [ChatService] Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == 1 && data['messageId'] != null) {
          // Create message object
          return Message(
            id: data['messageId'].toString(),
            from: userId,
            to: toUserId,
            content: content,
            date: DateTime.now(),
            viewed: false,
            isFromMe: true,
          );
        }
        throw Exception(data['message'] ?? 'Failed to send message');
      }
      throw Exception('Failed to send message: ${response.statusCode}');
    } catch (e) {
      print('❌ [ChatService] Error sending message: $e');
      rethrow;
    }
  }

  /// Get messages between current user and another user
  /// Returns messages ordered oldest to newest (for UI display)
  Future<List<Message>> getMessages({
    required String friendId,
    int? limit,
    int? offset,
  }) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Try to load from cache first (only for initial load, offset 0)
      if (offset == null || offset == 0) {
        final cachedMessages = await _loadMessagesFromCache(friendId, userId);
        if (cachedMessages.isNotEmpty) {
          // Refresh in background
          _refreshMessagesInBackground(friendId, userId);
          return cachedMessages;
        }
      }

      // If no cache, fetch from API
      final messages = await _fetchMessagesFromAPI(friendId, userId, limit, offset);

      // API returns newest first (DESC), reverse to oldest first for UI
      // Also sort by date to ensure correct order (in case dates are not sequential)
      final reversedMessages = messages.reversed.toList();
      reversedMessages.sort((a, b) => a.date.compareTo(b.date));

      // Cache the messages (only for initial load)
      if ((offset == null || offset == 0) && reversedMessages.isNotEmpty) {
        await _saveMessagesToCache(friendId, reversedMessages);
      }

      return reversedMessages;
    } catch (e, stackTrace) {
      debugPrint('❌ [ChatService] Error getting messages: $e');
      if (kDebugMode) {
        debugPrint('❌ [ChatService] Stack trace: $stackTrace');
        debugPrint('❌ [ChatService] URL attempted: ${ApiConstants.chatGet}');
        debugPrint('❌ [ChatService] API Base: ${ApiConstants.apiBase}');
      }
      // If API fails, try to return cached data as fallback (only for initial load)
      if (offset == null || offset == 0) {
        final userId = await _authService.getStoredUserId();
        if (userId != null) {
          final cachedMessages = await _loadMessagesFromCache(friendId, userId);
          if (cachedMessages.isNotEmpty) {
            debugPrint('✅ [ChatService] Using cached messages as fallback');
          }
          return cachedMessages;
        }
      }
      return [];
    }
  }

  /// Load older messages (for pagination when scrolling up)
  /// Returns messages ordered oldest to newest
  Future<List<Message>> loadOlderMessages({
    required String friendId,
    required int currentMessageCount,
    int limit = 50,
  }) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Calculate offset based on current message count
      final offset = currentMessageCount;

      // Fetch older messages from API
      final messages = await _fetchMessagesFromAPI(friendId, userId, limit, offset);

      // API returns newest first (DESC), reverse to oldest first for UI
      // Also sort by date to ensure correct order
      final reversedMessages = messages.reversed.toList();
      reversedMessages.sort((a, b) => a.date.compareTo(b.date));
      return reversedMessages;
    } catch (e) {
      print('❌ [ChatService] Error loading older messages: $e');
      return [];
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
    // Check for ClientException with SocketException
    if (error.toString().contains('SocketException') || 
        error.toString().contains('Connection reset')) {
      return true;
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

  /// Fetch messages from API
  Future<List<Message>> _fetchMessagesFromAPI(
    String friendId,
    String userId,
    int? limit,
    int? offset,
  ) async {
    final url = ApiConstants.chatGet;
    if (kDebugMode) {
      debugPrint('🔧 [ChatService] Fetching messages from: $url');
    }
    
    try {
      final response = await _retryHttpRequest(
        () => _client.post(
          Uri.parse(url),
          body: {
            'userID': userId,
            'friend': friendId,
            'limit': limit?.toString() ?? '50',
            'offset': offset?.toString() ?? '0',
          },
        ).timeout(const Duration(seconds: 10)),
        maxRetries: 2,
      );
    
      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        
        // Check if response is an error object (Map) or messages array (List)
        if (decoded is Map<String, dynamic>) {
          // This is an error response
          final responseCode = decoded['responseCode'];
          final message = decoded['message'] ?? 'Unknown error';
          throw Exception('API error: $message (code: $responseCode)');
        } else if (decoded is List) {
          // This is the messages array
          final List<dynamic> data = decoded;
          final List<Message> messages = [];

          for (final item in data) {
            final messageMap = item as Map<String, dynamic>;
            // Content is already decrypted from server
            messages.add(Message.fromJson(messageMap, userId));
          }

          return messages;
        } else {
          throw Exception('Unexpected response format from API');
        }
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [ChatService] Error in _fetchMessagesFromAPI: $e');
      if (kDebugMode) {
        debugPrint('❌ [ChatService] Stack trace: $stackTrace');
        debugPrint('❌ [ChatService] URL: $url');
      }
      rethrow;
    }
  }

  /// Refresh messages in background
  void _refreshMessagesInBackground(String friendId, String userId) {
    Future.delayed(const Duration(milliseconds: 100), () async {
      try {
        final messages = await _fetchMessagesFromAPI(friendId, userId, null, null);
        if (messages.isNotEmpty) {
          await _saveMessagesToCache(friendId, messages);
        }
      } catch (e) {
        print('⚠️ [ChatService] Background refresh failed: $e');
      }
    });
  }

  /// Save messages to cache
  Future<void> _saveMessagesToCache(String friendId, List<Message> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = messages.map((m) => m.toJson()).toList();
      await prefs.setString(
        '$_cacheKeyPrefix$friendId',
        jsonEncode(messagesJson),
      );
      await prefs.setInt(
        '$_cacheTimestampPrefix$friendId',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print('❌ [ChatService] Error saving to cache: $e');
    }
  }

  /// Load messages from cache
  Future<List<Message>> _loadMessagesFromCache(String friendId, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cacheKeyPrefix$friendId';
      final timestampKey = '$_cacheTimestampPrefix$friendId';

      final messagesJson = prefs.getString(cacheKey);
      final timestamp = prefs.getInt(timestampKey);

      if (messagesJson != null && timestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (cacheAge < _cacheExpiry.inMilliseconds) {
          final List<dynamic> data = json.decode(messagesJson);
          final List<Message> messages = [];
          for (final item in data) {
            final messageMap = item as Map<String, dynamic>;
            // Cached content is already decrypted
            messages.add(Message.fromJson(messageMap, userId));
          }
          return messages;
        }
      }
      return [];
    } catch (e) {
      print('❌ [ChatService] Error loading from cache: $e');
      return [];
    }
  }

  /// Clear cache for a specific friend
  Future<void> clearCache(String friendId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cacheKeyPrefix$friendId');
      await prefs.remove('$_cacheTimestampPrefix$friendId');
    } catch (e) {
      print('❌ [ChatService] Error clearing cache: $e');
    }
  }
}

