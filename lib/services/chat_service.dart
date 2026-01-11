import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/message.dart';
import '../config/constants.dart';
import 'auth_service.dart';
import 'websocket_service.dart';
import 'local_message_database.dart';
import 'package:crypto/crypto.dart';
import 'dart:developer' as developer;

class ChatService {
  final AuthService _authService = AuthService();
  final WebSocketService _webSocketService = WebSocketService();
  final LocalMessageDatabase _localDb = LocalMessageDatabase();
  final Connectivity _connectivity = Connectivity();
  
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
    // Log raw response for debugging
    print('[SKYBYN] 📥 [Chat Service] API Response received');
    print('[SKYBYN]    Status Code: ${response.statusCode}');
    print('[SKYBYN]    Response Body Length: ${response.body.length}');
    if (response.body.length < 500) {
      print('[SKYBYN]    Response Body: ${response.body}');
    } else {
      print('[SKYBYN]    Response Body (first 500 chars): ${response.body.substring(0, 500)}...');
    }
    
    // Try to parse response body regardless of status code
    Map<String, dynamic>? responseData;
    try {
      responseData = json.decode(response.body) as Map<String, dynamic>?;
      if (responseData != null) {
        print('[SKYBYN]    Parsed JSON: responseCode=${responseData['responseCode']}, messageId=${responseData['messageId']}, message=${responseData['message']}');
      }
    } catch (e) {
      print('[SKYBYN]    ❌ JSON Parse Error: $e');
      // If we can't parse JSON and it's not HTML, it might be an error
      if (response.statusCode != 200) {
        throw Exception('Invalid response from server. Please try again.');
      }
    }

    if (response.statusCode == 200) {
      if (responseData != null) {
        final responseCode = responseData['responseCode'];
        if ((responseCode == 1 || responseCode == '1') && responseData['messageId'] != null) {
          final messageId = responseData['messageId'].toString();
          print('[SKYBYN]    ✅ Message stored successfully in database');
          print('[SKYBYN]    ✅ Message ID: $messageId');
          // Create message object
          return Message(
            id: messageId,
            from: userId,
            to: toUserId,
            content: content,
            date: DateTime.now(),
            viewed: false,
            isFromMe: true,
          );
        }
        // Server returned 200 but with error in response body
        print('[SKYBYN]    ❌ Server returned 200 but responseCode is not 1 or messageId is missing');
        throw Exception(responseData['message'] ?? 'Failed to send message');
      }
      print('[SKYBYN]    ❌ Response data is null');
      throw Exception('Invalid response format from server');
    }
    
    // Handle non-200 status codes
    print('[SKYBYN]    ❌ HTTP Error ${response.statusCode}');
    // Check if response body contains error message
    if (responseData != null && responseData.containsKey('message')) {
      final errorMessage = responseData['message'] as String?;
      print('[SKYBYN]    Error Message: $errorMessage');
      // Handle 409 Conflict specifically (duplicate message)
      if (response.statusCode == 409) {
        // For 409, the message might have been sent already (duplicate)
        // Check if response contains messageId (message was sent)
        if (responseData.containsKey('messageId') && responseData['messageId'] != null) {
          final messageId = responseData['messageId'].toString();
          print('[SKYBYN]    ⚠️ Conflict (409) but messageId found: $messageId - treating as success');
          // Message was sent, return it as success
          return Message(
            id: messageId,
            from: userId,
            to: toUserId,
            content: content,
            date: DateTime.now(),
            viewed: false,
            isFromMe: true,
          );
        }
        // No messageId - message may have been sent but we can't confirm
        print('[SKYBYN]    ⚠️ Conflict (409) but no messageId - message may have been sent already');
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
    print('[SKYBYN]    ❌ Throwing exception: $statusMessage');
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

  /// Send a message (offline-first approach)
  /// Step 1: Save to local database immediately (optimistic UI)
  /// Step 2: Try to send via API
  /// Step 3: If offline/fails, add to offline queue for retry
  Future<Message?> sendMessage({
    required String toUserId,
    required String content,
    String? attachmentType,
    String? attachmentPath,
    String? attachmentName,
    int? attachmentSize,
  }) async {
    // Declare variables outside try block for use in catch block
    String? tempId;
    Message? optimisticMessage;
    
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Validate that all required parameters are present
      if (userId.isEmpty || toUserId.isEmpty || content.isEmpty) {
        throw Exception('Missing required parameters: userId=${userId.isEmpty ? "empty" : "ok"}, toUserId=${toUserId.isEmpty ? "empty" : "ok"}, message=${content.isEmpty ? "empty" : "ok"}');
      }

      // Generate temporary ID for optimistic UI
      tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_${toUserId}';
      
      // Create optimistic message (will be updated with real ID when synced)
      optimisticMessage = Message(
        id: tempId,
        from: userId,
        to: toUserId,
        content: content,
        date: DateTime.now(),
        viewed: false,
        isFromMe: true,
        attachmentType: attachmentType,
        attachmentUrl: attachmentPath,
        attachmentName: attachmentName,
        attachmentSize: attachmentSize,
      );

      // Step 1: Save to local database immediately (offline-first)
      await _localDb.saveMessage(optimisticMessage, synced: false);
      developer.log('Message saved locally: $tempId', name: 'ChatService');

      // Step 2: Check connectivity and try to send
      final connectivityResult = await _connectivity.checkConnectivity();
      final isOnline = connectivityResult != ConnectivityResult.none;

      if (!isOnline) {
        // Offline - add to queue for later sync
        await _localDb.addToOfflineQueue(
          toUserId: toUserId,
          content: content,
          attachmentType: attachmentType,
          attachmentPath: attachmentPath,
          attachmentName: attachmentName,
          attachmentSize: attachmentSize,
        );
        developer.log('Device offline - message queued: $tempId', name: 'ChatService');
        return optimisticMessage; // Return optimistic message
      }

      // Online - try to send via API
      // Encrypt the message for API
      final encryptedContent = await _encryptMessage(content);

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
      final sentMessage = await _processSendMessageResponse(response, userId, toUserId, content);
      
      if (sentMessage != null) {
        // Step 3: Update local database with real message ID and mark as synced
        await _localDb.saveMessage(sentMessage, synced: true);
        
        // Remove old optimistic message if it exists
        try {
          await _localDb.removeFromOfflineQueue(tempId);
        } catch (e) {
          // Ignore if not in queue
        }
        
        developer.log('Message synced successfully: ${sentMessage.id}', name: 'ChatService');
        return sentMessage;
      }
      
      // If send failed, message is already in local DB and queue
      return optimisticMessage;
    } catch (e) {
      // Send failed - ensure message is in offline queue
      if (tempId != null) {
        try {
          await _localDb.addToOfflineQueue(
            toUserId: toUserId,
            content: content,
            attachmentType: attachmentType,
            attachmentPath: attachmentPath,
            attachmentName: attachmentName,
            attachmentSize: attachmentSize,
          );
          developer.log('Send failed - message queued for retry: $tempId', name: 'ChatService');
        } catch (queueError) {
          developer.log('Error adding to offline queue: $queueError', name: 'ChatService');
        }
      }
      
      // Return optimistic message even on error (offline-first)
      // If optimistic message wasn't created, return null
      return optimisticMessage;
    }
  }

  /// Get messages between current user and another user (offline-first)
  /// Returns messages ordered oldest to newest (for UI display)
  /// Uses local database first, then syncs with server in background
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

      // Step 1: Load from local database immediately (offline-first)
      final localMessages = await _localDb.getMessages(
        friendId,
        userId,
        limit: limit ?? 100,
        offset: offset ?? 0,
      );

      // Step 2: Sync with server in background (incremental sync)
      syncMessages(friendId, userId);

      // Return local messages immediately (even if empty)
      return localMessages;
    } catch (e) {
      developer.log('Error getting messages: $e', name: 'ChatService');
      // Return empty list on error (better than crashing)
      return [];
    }
  }

  /// Get the most recent message for each friend from local DB
  /// Returns a map of friendId -> Message
  Future<Map<String, Message>> getLatestMessages() async {
    final userId = await _authService.getStoredUserId();
    if (userId == null) return {};
    return await _localDb.getLatestMessages(userId);
  }

  /// Get the last message for a specific friend
  Future<Message?> getLastMessage(String friendId) async {
    final userId = await _authService.getStoredUserId();
    if (userId == null) return null;
    return await _localDb.getLastMessage(friendId, userId);
  }

  /// Force fetch the latest message from API (bypass local DB check)
  Future<Message?> fetchLatestMessage(String friendId) async {
    final userId = await _authService.getStoredUserId();
    if (userId == null) return null;
    try {
      // Limit 1, Offset 0 should get the absolute latest message
      final messages = await _fetchMessagesFromAPI(friendId, userId, 1, 0);
      if (messages.isNotEmpty) {
        final message = messages.first;
        await _localDb.saveMessage(message, synced: true);
        return message;
      }
    } catch (e) {
      developer.log('Error fetching latest message: $e', name: 'ChatService');
    }
    return null;
  }

  /// Sync messages with server (incremental sync)
  /// Returns list of new messages fetched and saved
  Future<List<Message>> syncMessages(String friendId, String userId) async {
    try {
      // Get last sync timestamp for incremental sync
      final lastSyncTimestamp = await _localDb.getLastSyncTimestamp(friendId);
      
      // Fetch only new messages from API (incremental sync)
      final newMessages = await _fetchMessagesFromAPI(
        friendId,
        userId,
        100, // limit
        null, // offset
        lastSyncTimestamp, // sinceTimestamp (positional parameter)
      );

      if (newMessages.isNotEmpty) {
        // Save new messages to local database with conflict resolution
        // Server wins - if message exists locally, update with server data
        int latestTimestamp = 0;
        String? latestMessageId;
        
        for (final message in newMessages) {
          // Save message (will replace if exists - server wins)
          await _localDb.saveMessage(message, synced: true);
          final messageTimestamp = message.date.millisecondsSinceEpoch;
          if (messageTimestamp > latestTimestamp) {
            latestTimestamp = messageTimestamp;
            latestMessageId = message.id;
          }
        }

        // Update last sync timestamp
        await _localDb.updateLastSyncTimestamp(friendId, latestTimestamp, latestMessageId);
        
        developer.log('Synced ${newMessages.length} new messages for $friendId', name: 'ChatService');
        return newMessages;
      } else {
        // No new messages - update sync timestamp to current time to prevent unnecessary API calls
        await _localDb.updateLastSyncTimestamp(friendId, DateTime.now().millisecondsSinceEpoch, null);
        return [];
      }
    } catch (e) {
      developer.log('Error syncing messages in background: $e', name: 'ChatService');
      // Don't throw - sync failures shouldn't block UI
      return [];
    }
  }

  /// Load older messages (for pagination when scrolling up)
  /// Returns messages ordered oldest to newest
  /// Uses local database first, then fetches from API if needed
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

      // Try to load from local database first
      final localMessages = await _localDb.getMessages(
        friendId,
        userId,
        limit: limit,
        offset: currentMessageCount,
      );

      // If we have enough local messages, return them
      if (localMessages.length >= limit) {
        return localMessages;
      }

      // Fetch older messages from API
      final messages = await _fetchMessagesFromAPI(friendId, userId, limit, currentMessageCount);

      // Save fetched messages to local database
      for (final message in messages) {
        await _localDb.saveMessage(message, synced: true);
      }

      // API returns newest first (DESC), reverse to oldest first for UI
      // Also sort by date to ensure correct order
      final reversedMessages = messages.reversed.toList();
      reversedMessages.sort((a, b) => a.date.compareTo(b.date));
      return reversedMessages;
    } catch (e) {
      developer.log('Error loading older messages: $e', name: 'ChatService');
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

  /// Fetch messages from API (supports incremental sync)
  Future<List<Message>> _fetchMessagesFromAPI(
    String friendId,
    String userId,
    int? limit,
    int? offset, [
    int? sinceTimestamp,
  ]) async {
    final url = ApiConstants.chatGet;
    
    try {
      final bodyMap = <String, String>{
        'userID': userId,
        'friendID': friendId,
        'limit': limit?.toString() ?? '50',
        'offset': offset?.toString() ?? '0',
      };
      
      // Add sinceTimestamp for incremental sync if provided
      if (sinceTimestamp != null) {
        bodyMap['since'] = sinceTimestamp.toString();
      }
      
      final response = await _retryHttpRequest(
        () => _client.post(
          Uri.parse(url),
          body: bodyMap,
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

  /// Refresh messages in background (now uses local database)
  void _refreshMessagesInBackground(String friendId, String userId) {
    // This is now handled by syncMessages which uses local database
    syncMessages(friendId, userId);
  }

  /// Process offline queue - send queued messages when online
  Future<void> processOfflineQueue() async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return;

      final connectivityResult = await _connectivity.checkConnectivity();
      final isOnline = connectivityResult != ConnectivityResult.none;
      if (!isOnline) return;

      final queue = await _localDb.getOfflineQueue();
      if (queue.isEmpty) return;

      developer.log('Processing ${queue.length} messages from offline queue', name: 'ChatService');

      for (final item in queue) {
        try {
          final tempId = item['temp_id'] as String;
          final toUserId = item['to_user_id'] as String;
          final content = item['content'] as String;
          final retryCount = item['retry_count'] as int? ?? 0;

          // Skip if retried too many times
          if (retryCount >= 5) {
            await _localDb.removeFromOfflineQueue(tempId);
            continue;
          }

          // Try to send the message
          final encryptedContent = await _encryptMessage(content);
          final url = ApiConstants.chatSend;
          final headers = <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-API-Key': ApiConstants.apiKey,
          };

          final bodyMap = <String, String>{
            'userID': userId.toString(),
            'from': userId.toString(),
            'to': toUserId.toString(),
            'message': encryptedContent,
            'api_key': ApiConstants.apiKey,
          };

          final response = await _client.post(
            Uri.parse(url),
            body: bodyMap,
            headers: headers,
            encoding: utf8,
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final responseData = json.decode(response.body) as Map<String, dynamic>?;
            final responseCode = responseData?['responseCode'];
            if (responseData != null && (responseCode == 1 || responseCode == '1') && responseData['messageId'] != null) {
              final messageId = responseData['messageId'].toString();
              
              // Update local database with real message ID
              final message = Message(
                id: messageId,
                from: userId,
                to: toUserId,
                content: content,
                date: DateTime.fromMillisecondsSinceEpoch(item['created_at'] as int),
                viewed: false,
                isFromMe: true,
                attachmentType: item['attachment_type'] as String?,
                attachmentUrl: item['attachment_path'] as String?,
                attachmentName: item['attachment_name'] as String?,
                attachmentSize: item['attachment_size'] as int?,
              );
              
              await _localDb.saveMessage(message, synced: true);
              await _localDb.removeFromOfflineQueue(tempId);
              
              developer.log('Queued message sent successfully: $messageId', name: 'ChatService');
            } else {
              // Update retry count
              await _localDb.updateOfflineQueueRetry(tempId, retryCount + 1);
            }
          } else {
            // Update retry count
            await _localDb.updateOfflineQueueRetry(tempId, retryCount + 1);
          }
        } catch (e) {
          developer.log('Error processing queued message: $e', name: 'ChatService');
          // Continue with next message
        }
      }
    } catch (e) {
      developer.log('Error processing offline queue: $e', name: 'ChatService');
    }
  }

  /// Mark messages as read
  /// Can mark all messages from a friend, or specific message IDs
  Future<bool> markMessagesAsRead({
    String? friendId,
    List<String>? messageIDs,
  }) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      if (friendId == null && (messageIDs == null || messageIDs.isEmpty)) {
        throw Exception('Either friendId or messageIDs must be provided');
      }

      final url = ApiConstants.chatRead;
      final headers = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-API-Key': ApiConstants.apiKey,
      };

      final bodyMap = <String, String>{
        'userID': userId.toString(),
        'api_key': ApiConstants.apiKey,
      };

      if (messageIDs != null && messageIDs.isNotEmpty) {
        bodyMap['messageIDs'] = messageIDs.join(',');
      } else if (friendId != null) {
        bodyMap['friendID'] = friendId;
      }

      final response = await _retryHttpRequest(
        () async {
          return await _client.post(
            Uri.parse(url),
            body: bodyMap,
            headers: headers,
            encoding: utf8,
          );
        },
        maxRetries: 1, // Only retry once for read operations
      );

      print('[SKYBYN] 📥 [Chat Service] Mark Read API Response received');
      print('[SKYBYN]    Status Code: ${response.statusCode}');
      developer.log('📥 [Chat Service] Mark Read API Response received', name: 'Chat API');
      developer.log('   Status Code: ${response.statusCode}', name: 'Chat API');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body) as Map<String, dynamic>?;
        if (responseData != null) {
          print('[SKYBYN]    Response: ${responseData['responseCode'] == 1 ? 'Success' : 'Failed'}');
          developer.log('   Response: ${responseData['responseCode'] == 1 ? 'Success' : 'Failed'}', name: 'Chat API');
          
          if (responseData['responseCode'] == 1) {
            final affectedRows = responseData['affectedRows'] ?? 0;
            print('[SKYBYN]    ✅ Marked $affectedRows message(s) as read in database');
            developer.log('   ✅ Marked $affectedRows message(s) as read in database', name: 'Chat API');
            
            // Update local database
            if (messageIDs != null && messageIDs.isNotEmpty) {
              for (final messageId in messageIDs) {
                await _localDb.markMessageAsViewed(messageId);
              }
            } else if (friendId != null) {
              // Mark all messages from this friend as viewed in local DB
              final messages = await _localDb.getMessages(friendId, userId ?? '');
              for (final message in messages) {
                if (!message.isFromMe && !message.viewed) {
                  await _localDb.markMessageAsViewed(message.id);
                }
              }
            }
            
            return true;
          }
          throw Exception(responseData['message'] ?? 'Failed to mark messages as read');
        }
        throw Exception('Invalid response format');
      }

      print('[SKYBYN]    ❌ HTTP Error ${response.statusCode}');
      developer.log('   ❌ HTTP Error ${response.statusCode}', name: 'Chat API');
      throw Exception('Failed to mark messages as read: ${response.statusCode}');
    } catch (e) {
      print('[SKYBYN] ❌ [Chat Service] Error marking messages as read: $e');
      developer.log('❌ [Chat Service] Error marking messages as read: $e', name: 'Chat API');
      return false; // Don't throw, just return false - read status is not critical
    }
  }

  /// Clear cache for a specific friend
  Future<void> clearCache(String friendId) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId != null) {
        await _localDb.deleteConversation(friendId, userId);
      }
    } catch (e) {
      developer.log('Error clearing cache: $e', name: 'ChatService');
    }
  }

  /// Clear all local data (for logout)
  Future<void> clearAll() async {
    try {
      await _localDb.clearAll();
    } catch (e) {
      developer.log('Error clearing all data: $e', name: 'ChatService');
    }
  }
}

