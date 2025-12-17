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
import 'websocket_service.dart';
import 'package:crypto/crypto.dart';

class ChatService {
  static const String _cacheKeyPrefix = 'cached_messages_';
  static const String _cacheTimestampPrefix = 'cached_messages_timestamp_';
  static const Duration _cacheExpiry = Duration(minutes: 2);

  final AuthService _authService = AuthService();
  final WebSocketService _webSocketService = WebSocketService();
  
  // Track if chat_offline callback is registered
  bool _chatOfflineCallbackRegistered = false;
  
  // Store protection cookie to bypass bot challenges
  static String? _protectionCookie;
  
  // Use the same HTTP client pattern as AuthService to ensure consistent SSL handling
  static http.Client? _httpClient;
  static http.Client get _client {
    _httpClient ??= _createHttpClient();
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
    // Use a more browser-like user agent to avoid bot protection
    httpClient.userAgent = 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36 Skybyn-App/1.0';
    httpClient.connectionTimeout = const Duration(seconds: 30);
    httpClient.idleTimeout = const Duration(seconds: 30);
    httpClient.autoUncompress = true;
    
    return IOClient(httpClient);
  }

  /// Process send message response (extracted to handle retries)
  Future<Message?> _processSendMessageResponse(
    http.Response response,
    String userId,
    String toUserId,
    String content,
  ) async {
    // Try to parse response body regardless of status code
    Map<String, dynamic>? responseData;
    try {
      responseData = json.decode(response.body) as Map<String, dynamic>?;
    } catch (e) {
      // If we can't parse JSON and it's not HTML, it might be an error
      if (response.statusCode != 200) {
        throw Exception('Invalid response from server. Please try again.');
      }
    }

    if (response.statusCode == 200) {
      if (responseData != null) {
        if (responseData['responseCode'] == 1 && responseData['messageId'] != null) {
          // Create message object
          return Message(
            id: responseData['messageId'].toString(),
            from: userId,
            to: toUserId,
            content: content,
            date: DateTime.now(),
            viewed: false,
            isFromMe: true,
          );
        }
        // Server returned 200 but with error in response body
        throw Exception(responseData['message'] ?? 'Failed to send message');
      }
      throw Exception('Invalid response format from server');
    }
    
    // Handle non-200 status codes
    // Check if response body contains error message
    if (responseData != null && responseData.containsKey('message')) {
      final errorMessage = responseData['message'] as String?;
      // Handle 409 Conflict specifically (duplicate message)
      if (response.statusCode == 409) {
        // For 409, the message might have been sent already (duplicate)
        // Check if response contains messageId (message was sent)
        if (responseData.containsKey('messageId') && responseData['messageId'] != null) {
          // Message was sent, return it as success
          return Message(
            id: responseData['messageId'].toString(),
            from: userId,
            to: toUserId,
            content: content,
            date: DateTime.now(),
            viewed: false,
            isFromMe: true,
          );
        }
        // No messageId - message may have been sent but we can't confirm
        throw Exception(errorMessage ?? 'Message may have been sent already');
      }
      
      throw Exception(errorMessage ?? 'Failed to send message');
    }
    
    // No error message in response body, use status code
    String statusMessage = 'Failed to send message';
    if (response.statusCode == 409) {
      statusMessage = 'Message may have been sent already (conflict)';
    } else if (response.statusCode == 429) {
      statusMessage = 'Too many requests. Please wait a moment.';
    } else if (response.statusCode >= 500) {
      statusMessage = 'Server error. Please try again later.';
    }
    throw Exception(statusMessage);
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
  /// Step 1: Send via WebSocket for real-time delivery
  /// Step 2: Store in database via API (runs in parallel)
  Future<Message?> sendMessage({
    required String toUserId,
    required String content,
  }) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Validate that all required parameters are present
      if (userId.isEmpty || toUserId.isEmpty || content.isEmpty) {
        throw Exception('Missing required parameters: userId=${userId.isEmpty ? "empty" : "ok"}, toUserId=${toUserId.isEmpty ? "empty" : "ok"}, message=${content.isEmpty ? "empty" : "ok"}');
      }

      // Store message in database via API
      // Encrypt the message for API
      final encryptedContent = await _encryptMessage(content);

<<<<<<< HEAD
      // Register chat_offline callback to send Firebase notification when recipient is offline
      // Only register once to avoid overwriting
      if (!_chatOfflineCallbackRegistered) {
        await _webSocketService.connect(
          onChatOffline: (String fromUserId, String toUserId, String messageContent) async {
            // Get current user ID to check if this is our message
            final currentUserId = await _authService.getStoredUserId();
            if (currentUserId != null && fromUserId == currentUserId) {
              // This is a message we sent, and recipient is offline - send Firebase notification
              await _sendFirebaseNotificationForOfflineUser(
                fromUserId: fromUserId,
                toUserId: toUserId,
                messageContent: messageContent,
              );
            }
          },
        );
        _chatOfflineCallbackRegistered = true;
      }

      try {
        final sent = await _webSocketService.sendChatMessage(
          targetUserId: toUserId,
          content: trimmedContent,
        );
        
        if (!sent) {
          throw Exception('Failed to send message via WebSocket');
        }
        
        // Create optimistic message - will be updated when we get confirmation or store in database
        final optimisticMessage = Message(
          id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          from: userId,
          to: toUserId,
          content: trimmedContent,
          date: DateTime.now(),
          viewed: false,
          isFromMe: true,
          status: MessageStatus.sending,
        );
        
        // Store message in database (do this asynchronously, don't wait)
        // The message will be stored regardless of whether recipient is online or offline
        _storeMessageInDatabase(userId, toUserId, trimmedContent).then((_) {
          print('[SKYBYN] ✅ [Chat] Message stored in database successfully');
        }).catchError((e) {
          print('[SKYBYN] ⚠️ [Chat] Failed to store message in database: $e');
        });
        
        // Invalidate cache for this conversation
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('$_cacheKeyPrefix$toUserId');
          await prefs.remove('$_cacheTimestampPrefix$toUserId');
        } catch (e) {
          // Ignore cache errors
        }
        
        return optimisticMessage;
      } catch (e) {
        rethrow;
=======
      final url = ApiConstants.chatSend;
      // Build headers with optional protection cookie and API key
      final headers = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest', // Helps bypass some bot protection
        'X-API-Key': ApiConstants.apiKey, // API key for unrestricted access
      };
      
      // Add protection cookie if we have one
      if (_protectionCookie != null) {
        headers['Cookie'] = _protectionCookie!;
>>>>>>> parent of 0b04990 (Fixed real-time chatting)
      }
      
      // Build body map to ensure all parameters are strings
      final bodyMap = <String, String>{
        'userID': userId.toString(),
        'from': userId.toString(),
        'to': toUserId.toString(),
        'message': encryptedContent,
        'api_key': ApiConstants.apiKey, // Also send in POST body for compatibility
      };
      
      // Use Map format - http package will automatically encode it as form-urlencoded
      // when Content-Type is set to application/x-www-form-urlencoded
      final response = await _retryHttpRequest(
        () async {
          final resp = await _client.post(
            Uri.parse(url),
            body: bodyMap,
            headers: headers,
            encoding: utf8, // Explicitly set encoding
          );
          return resp;
        },
        maxRetries: 2,
      );

      // Log response in both debug and release (using debugPrint)
      // Check if response is HTML/JavaScript (bot protection, Cloudflare, etc.)
      final responseBody = response.body.trim();
      final isHtmlResponse = responseBody.startsWith('<') || 
                             responseBody.contains('<script>') ||
                             responseBody.contains('<!DOCTYPE') ||
                             responseBody.contains('<html') ||
                             responseBody.startsWith('<br') ||
                             (responseBody.length < 50 && responseBody.contains('<'));
      
      if (isHtmlResponse) {
        
        // Try to extract protection cookie from response
        final cookieMatch = RegExp(r'humans_\d+=\d+').firstMatch(responseBody);
        if (cookieMatch != null) {
          _protectionCookie = cookieMatch.group(0);
          // Wait a moment before retrying (bot protection may need time to process)
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Retry the request with the cookie and API key
          // Validate parameters before retry
          if (userId.isEmpty || toUserId.isEmpty || encryptedContent.isEmpty) {
            throw Exception('Missing required parameters for retry');
          }
          
          try {
            // Build the body map to ensure all parameters are present and are strings
            final retryBody = <String, String>{
              'userID': userId.toString(),
              'from': userId.toString(),
              'to': toUserId.toString(),
              'message': encryptedContent,
              'api_key': ApiConstants.apiKey, // Also send in POST body for compatibility
            };
            
            // Make a direct request without retry wrapper to avoid nested retries
            // Use Map format - http package will automatically encode it correctly
            final retryResponse = await _client.post(
              Uri.parse(url),
              body: retryBody,
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
                'X-Requested-With': 'XMLHttpRequest',
                'X-API-Key': ApiConstants.apiKey, // API key for unrestricted access
                'Cookie': _protectionCookie!,
              },
              encoding: utf8, // Explicitly set encoding
            ).timeout(const Duration(seconds: 15));
            // Check if retry also got HTML
            final retryResponseBody = retryResponse.body.trim();
            final retryIsHtml = retryResponseBody.startsWith('<') || 
                               retryResponseBody.contains('<script>') ||
                               retryResponseBody.contains('<!DOCTYPE') ||
                               retryResponseBody.contains('<html') ||
                               retryResponseBody.startsWith('<br');
            
            if (retryIsHtml) {
              throw Exception('Server protection is still active. The API key may need to be configured on the server.');
            }
            
            // Process the retry response
            return await _processSendMessageResponse(retryResponse, userId, toUserId, content);
          } catch (retryError) {
            // Fall through to throw error
          }
        }
        
        // This is likely bot protection (Cloudflare, etc.) - treat as temporary error
        if (response.statusCode == 409 || response.statusCode == 403) {
          throw Exception('Server protection triggered. The API key may need to be configured in your hosting control panel (cPanel/Cloudflare).');
        }
        throw Exception('Server temporarily unavailable. Please try again in a moment.');
      }
      
      // Process normal response
      // The API call stores the message in the database
      return await _processSendMessageResponse(response, userId, toUserId, content);
    } catch (e) {
      rethrow;
    }
  }
<<<<<<< HEAD
  
  /// Send Firebase notification when recipient is offline
  Future<void> _sendFirebaseNotificationForOfflineUser({
    required String fromUserId,
    required String toUserId,
    required String messageContent,
  }) async {
    try {
      // Get sender's profile info (username, nickname, avatar)
      final userProfile = await _authService.getStoredUserProfile();
      String senderName = 'Someone';
      String? senderAvatar;
      
      if (userProfile != null) {
        final nickname = userProfile.nickname.trim();
        final username = userProfile.username.trim();
        senderName = nickname.isNotEmpty ? nickname : (username.isNotEmpty ? username : 'Someone');
        senderAvatar = userProfile.avatar.trim();
        if (senderAvatar.isEmpty) {
          senderAvatar = null;
        }
      }
      
      // Get session token for authentication
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('sessionToken');
      
      if (sessionToken == null || sessionToken.isEmpty) {
        print('[SKYBYN] ⚠️ [Chat] No session token available, cannot send Firebase notification');
        return;
      }
      
      // Truncate message for notification (max 100 chars)
      String notificationBody = messageContent;
      if (notificationBody.length > 100) {
        notificationBody = notificationBody.substring(0, 97) + '...';
      }
      
      // Build Firebase notification payload
      final firebaseData = <String, String>{
        'userID': fromUserId, // Required for authentication
        'sessionToken': sessionToken, // Required for authentication
        'user': toUserId, // Recipient user ID
        'title': senderName,
        'body': notificationBody,
        'type': 'chat',
        'from': fromUserId,
        'priority': 'high',
        'channel': 'chat_messages',
        'payload': jsonEncode({
          'from': fromUserId,
          'to': toUserId,
          'message': messageContent,
          'date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }),
      };
      
      // Add avatar if available
      if (senderAvatar != null && senderAvatar.isNotEmpty) {
        firebaseData['image'] = senderAvatar;
      }
      
      // Send Firebase notification via API (async - don't wait for response)
      final url = ApiConstants.firebase;
      try {
        await _client.post(
          Uri.parse(url),
          body: firebaseData,
        ).timeout(const Duration(seconds: 3));
        print('[SKYBYN] ✅ [Chat] Firebase notification sent to offline user $toUserId');
      } catch (e) {
        // Silently fail - notification failure shouldn't break message sending
        print('[SKYBYN] ⚠️ [Chat] Failed to send Firebase notification: $e');
      }
    } catch (e) {
      // Silently fail - notification failure shouldn't break message sending
      print('[SKYBYN] ⚠️ [Chat] Error sending Firebase notification: $e');
    }
  }
  
  /// Store message in database (called asynchronously after WebSocket send)
  Future<void> _storeMessageInDatabase(String userId, String toUserId, String message) async {
    try {
      final url = ApiConstants.chatSend;
      // Use simple http.post() like token.php does (no custom client, minimal headers)
      final response = await http.post(
        Uri.parse(url),
        body: {
          'userID': userId,
          'to': toUserId,
          'message': message,
        },
      ).timeout(const Duration(seconds: 10));
      
      // Check for bot protection
      if (response.statusCode == 409 || response.body.contains('<script>') || response.body.contains('humans_')) {
        return; // Don't throw - message is already delivered
      }
      
      // Process response to get message ID (for future use if needed)
      await _processSendMessageResponse(
        response,
        userId,
        toUserId,
        message,
      );
    } catch (e) {
      // Silently fail - message delivery via WebSocket is more important
    }
  }
=======
>>>>>>> parent of 0b04990 (Fixed real-time chatting)

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
    } catch (e) {
      // If API fails, try to return cached data as fallback (only for initial load)
      if (offset == null || offset == 0) {
        final userId = await _authService.getStoredUserId();
        if (userId != null) {
          final cachedMessages = await _loadMessagesFromCache(friendId, userId);
          if (cachedMessages.isNotEmpty) {
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
        // Log response details for debugging
        if (response.statusCode < 500) {
          return response;
        }
        // For 500 errors, log the response body before throwing
        if (response.statusCode >= 500) {
          // Try to extract error message from response
          try {
            final errorData = json.decode(response.body) as Map<String, dynamic>?;
            if (errorData != null && errorData.containsKey('message')) {
              final errorMsg = errorData['message'] as String?;
              throw HttpException('Server error: ${response.statusCode} - ${errorMsg ?? "Unknown error"}');
            }
          } catch (e) {
            // If we can't parse the error, just use the status code
          }
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
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-API-Key': ApiConstants.apiKey, // API key for unrestricted access
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
    } catch (e) {
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
    }
  }
}

