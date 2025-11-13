import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform, WebSocket, SecurityContext, HttpClient;
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'notification_service.dart';

/// Unified WebSocket service that handles both real-time updates and background notifications
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  String? _sessionId;
  String? _userId;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 10;
  final int _reconnectDelay = 1000; // Start with 1 second
  final int _maxReconnectDelay = 30000; // Max 30 seconds
  Timer? _reconnectTimer;
  bool _isInitialized = false;
  int? _lastPingReceivedTime; // Track when we last received a ping from server
  Timer? _connectionHealthTimer; // Monitor connection health

  // Message queuing and acknowledgment
  final List<Map<String, dynamic>> _messageQueue = [];
  final Map<String, Map<String, dynamic>> _pendingMessages = {};
  int _lastMessageId = 0;

  // Connection quality metrics
  final Map<String, dynamic> _connectionMetrics = {
    'totalConnections': 0,
    'successfulConnections': 0,
    'failedConnections': 0,
    'totalReconnects': 0,
    'averageLatency': 0,
    'lastLatency': 0,
    'connectionStartTime': 0,
    'totalUptime': 0,
    'messagesSent': 0,
    'messagesReceived': 0,
    'errors': 0,
  };

  // Callbacks for real-time updates
  Function(Post)? _onNewPost;
  Function(String, String)? _onNewComment; // postId, commentId
  Function(String)? _onDeletePost;
  Function(String, String)? _onDeleteComment; // postId, commentId
  Function(String)? _onBroadcast; // broadcast message
  Function()? _onAppUpdate; // app update notification
  Function(String, String, String, String)? _onChatMessage; // messageId, fromUserId, toUserId, message
  Function(String, bool)? _onTypingStatus; // userId, isTyping
  final List<Function(String, bool)> _onOnlineStatusCallbacks = []; // Multiple listeners for online status

  // Callbacks for WebRTC signaling
  Function(String, String, String, String)? _onCallOffer; // callId, fromUserId, offer, callType
  Function(String, String)? _onCallAnswer; // callId, answer
  Function(String, String, String, int)? _onIceCandidate; // callId, candidate, sdpMid, sdpMLineIndex
  Function(String, String, String)? _onCallEnd; // callId, fromUserId, targetUserId
  Function(String, String, String, String)? _onCallInitiate; // callId, fromUserId, callType, fromUsername

  // Services
  final NotificationService _notificationService = NotificationService();

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

  /// Get connection quality metrics
  Map<String, dynamic> getConnectionMetrics() {
    return Map<String, dynamic>.from(_connectionMetrics);
  }

  // Enhanced connection management
  int _getReconnectDelay() {
    return (_reconnectDelay * (1 << _reconnectAttempts)).clamp(_reconnectDelay, _maxReconnectDelay);
  }

  void _updateConnectionMetrics(String event) {
    final now = DateTime.now().millisecondsSinceEpoch;

    switch (event) {
      case 'connecting':
        _connectionMetrics['totalConnections']++;
        _connectionMetrics['connectionStartTime'] = now;
        break;
      case 'connected':
        _connectionMetrics['successfulConnections']++;
        if (_reconnectAttempts > 0) {
          _connectionMetrics['totalReconnects']++;
        }
        _reconnectAttempts = 0;
        print('✅ [WebSocket] Connected to WebSocket server');
        break;
      case 'failed':
        _connectionMetrics['failedConnections']++;
        print('❌ [WebSocket] Failed to connect to WebSocket server');
        break;
      case 'message_sent':
        _connectionMetrics['messagesSent']++;
        break;
      case 'message_received':
        _connectionMetrics['messagesReceived']++;
        break;
      case 'error':
        _connectionMetrics['errors']++;
        print('❌ [WebSocket] Error');
        break;
    }

    // Update uptime
    if (_isConnected && _connectionMetrics['connectionStartTime'] > 0) {
      _connectionMetrics['totalUptime'] = now - _connectionMetrics['connectionStartTime'];
    }
  }

  void _logConnectionQuality() {
    final successRate = _connectionMetrics['totalConnections'] > 0 ? (_connectionMetrics['successfulConnections'] / _connectionMetrics['totalConnections'] * 100) : 0.0;

    print('📊 [WebSocket] Quality: ${successRate.toStringAsFixed(1)}% success, '
        '${_connectionMetrics['messagesSent']} sent, '
        '${_connectionMetrics['messagesReceived']} received, '
        '${_connectionMetrics['errors']} errors');
  }

  // Message queuing and acknowledgment
  String _generateMessageId() {
    return (++_lastMessageId).toString();
  }

  void _queueMessage(Map<String, dynamic> message) {
    if (_isConnected) {
      return; // Don't queue if connected
    }

    _messageQueue.add({
      ...message,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'id': _generateMessageId(),
    });

    print('📝 [WebSocket] Message queued (${_messageQueue.length} in queue)');
  }

  void _processMessageQueue() {
    if (_messageQueue.isEmpty || !_isConnected) {
      return;
    }

    final messages = List<Map<String, dynamic>>.from(_messageQueue);
    _messageQueue.clear();

    for (final message in messages) {
      _sendMessageInternal(message);
    }

    print('📤 [WebSocket] Processed ${messages.length} queued messages');
  }

  void _sendMessageInternal(Map<String, dynamic> message) {
    if (!_isConnected || _channel == null) {
      _queueMessage(message);
      return;
    }

    try {
      final messageJson = jsonEncode(message);
      _channel!.sink.add(messageJson);
      _updateConnectionMetrics('message_sent');

      // Store for acknowledgment tracking
      if (message['id'] != null) {
        _pendingMessages[message['id']] = {
          'message': message,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'retries': 0,
        };
      }
    } catch (e) {
      print('❌ [WebSocket] Error sending message: $e');
      _updateConnectionMetrics('error');
    }
  }

  void _retryPendingMessages() {
    final now = DateTime.now().millisecondsSinceEpoch;
    const retryTimeout = 5000; // 5 seconds
    const maxRetries = 3;

    _pendingMessages.removeWhere((messageId, pending) {
      if (now - pending['timestamp'] > retryTimeout && pending['retries'] < maxRetries) {
        pending['retries']++;
        print('🔄 [WebSocket] Retrying message $messageId (attempt ${pending['retries']})');

        if (_isConnected && _channel != null) {
          try {
            _channel!.sink.add(jsonEncode(pending['message']));
            _updateConnectionMetrics('message_sent');
          } catch (e) {
            print('❌ [WebSocket] Error retrying message: $e');
            _updateConnectionMetrics('error');
          }
        }
        return false; // Keep in pending
      } else if (pending['retries'] >= maxRetries) {
        print('❌ [WebSocket] Message $messageId failed after $maxRetries retries');
        _updateConnectionMetrics('error');
        return true; // Remove from pending
      }
      return false; // Keep in pending
    });
  }

  /// Initialize the WebSocket service
  Future<void> initialize() async {
    try {
      print('🔄 [WebSocket] Initializing WebSocket service...');
      
      // Generate session ID
      _sessionId = _generateSessionId();

      _isInitialized = true;
      print('✅ [WebSocket] WebSocket service initialized');
    } catch (e) {
      print('❌ [WebSocket] Error initializing WebSocket service: $e');
    }
  }
  
  /// Get WebSocket URL based on build mode
  String _getWebSocketUrl() {
    // Use port 4432 for debug builds, 4433 for release builds
    final port = kDebugMode ? 4432 : 4433;
    // Use server.skybyn.no for development, server.skybyn.no for production
    final host = kDebugMode ? 'server.skybyn.no' : 'server.skybyn.no';
    return 'wss://$host:$port';
  }

  /// Create WebSocket channel with SSL certificate handling
  Future<WebSocketChannel> _createWebSocketChannel(String url) async {
    final uri = Uri.parse(url);
    
    // In debug mode, bypass SSL certificate validation for self-signed certificates
    if (kDebugMode) {
      try {
        // Create an HttpClient with custom certificate handling
        final httpClient = HttpClient();
        httpClient.badCertificateCallback = (cert, host, port) {
          print('⚠️ [WebSocket] Accepting certificate for $host:$port in debug mode');
          return true; // Accept all certificates in debug mode
        };
        
        // Create WebSocket connection using the custom HttpClient
        // WebSocket.connect with customClient parameter (available in Dart 2.17+)
        final webSocket = await WebSocket.connect(
          url,
          customClient: httpClient,
        );
        
        // Wrap the socket in an IOWebSocketChannel (which accepts WebSocket)
        return IOWebSocketChannel(webSocket);
      } catch (e) {
        print('❌ [WebSocket] Error creating custom WebSocket connection: $e');
        print('🔄 [WebSocket] Falling back to standard connection...');
        // Fall back to standard connection
        return IOWebSocketChannel.connect(uri);
      }
    } else {
      // In release mode, try with SSL certificate handling first
      // Some servers may have self-signed certificates even in production
      try {
        // Create an HttpClient with custom certificate handling for release mode too
        final httpClient = HttpClient();
        httpClient.badCertificateCallback = (cert, host, port) {
          print('⚠️ [WebSocket] Accepting certificate for $host:$port in release mode');
          return true; // Accept all certificates (needed for some server configurations)
        };
        
        // Create WebSocket connection using the custom HttpClient
        final webSocket = await WebSocket.connect(
          url,
          customClient: httpClient,
        );
        
        // Wrap the socket in an IOWebSocketChannel
        return IOWebSocketChannel(webSocket);
      } catch (e) {
        print('❌ [WebSocket] Error creating WebSocket connection with custom client: $e');
        print('🔄 [WebSocket] Falling back to standard connection...');
        // Fall back to standard connection
        return IOWebSocketChannel.connect(uri);
      }
    }
  }

  /// Connect to WebSocket with callbacks
  /// Only connects when app is in foreground
  /// Can be called multiple times to update callbacks or reconnect
  Future<void> connect({
    Function(Post)? onNewPost,
    Function(String, String)? onNewComment,
    Function(String)? onDeletePost,
    Function(String, String)? onDeleteComment,
    Function(String)? onBroadcast,
    Function()? onAppUpdate,
    Function(String, String, String, String)? onChatMessage, // messageId, fromUserId, toUserId, message
    Function(String, bool)? onTypingStatus, // userId, isTyping
    Function(String, bool)? onOnlineStatus, // userId, isOnline
  }) async {
    // Store callbacks (merge - only update if non-null, preserve existing if null)
    if (onNewPost != null) _onNewPost = onNewPost;
    if (onNewComment != null) _onNewComment = onNewComment;
    if (onDeletePost != null) _onDeletePost = onDeletePost;
    if (onDeleteComment != null) _onDeleteComment = onDeleteComment;
    if (onBroadcast != null) _onBroadcast = onBroadcast;
    if (onAppUpdate != null) _onAppUpdate = onAppUpdate;
    if (onChatMessage != null) _onChatMessage = onChatMessage;
    if (onTypingStatus != null) _onTypingStatus = onTypingStatus;
    if (onOnlineStatus != null) {
      // Add callback to list (allow multiple listeners for online status)
      // Note: Function equality doesn't work in Dart, so we allow duplicates
      // Widgets should manage their own callback lifecycle
      _onOnlineStatusCallbacks.add(onOnlineStatus);
      if (kDebugMode) {
        print('✅ [WebSocket] onOnlineStatus callback registered (total: ${_onOnlineStatusCallbacks.length})');
      }
    }

    // Ensure service is initialized before connecting
    if (!_isInitialized) {
      print('⚠️ [WebSocket] Service not initialized, initializing now...');
      await initialize();
    }
    
    // Test connection if it appears connected
    if (_isConnected) {
      // Verify the connection is actually alive
      if (_testConnection()) {
        print('ℹ️ [WebSocket] Already connected and healthy, callbacks updated (no reconnection needed)');
        // Callbacks have already been updated above, so we can return
        // This allows screens to register their callbacks after connection is established
        return;
      } else {
        print('⚠️ [WebSocket] Connection appears connected but is actually dead - reconnecting...');
        // Connection is dead, reset state and reconnect
        _isConnected = false;
        _channel = null;
      }
    }
    
    if (_isConnecting) {
      print('ℹ️ [WebSocket] Already connecting, skipping duplicate connection attempt');
      return;
    }

    // Set connecting flag immediately to prevent duplicate connections
    _isConnecting = true;

    try {
      _updateConnectionMetrics('connecting');
      
      // Generate session ID if not exists
      if (_sessionId == null) {
        _sessionId = _generateSessionId();
      }

      final wsUrl = _getWebSocketUrl();
      print('🔄 [WebSocket] Connecting to WebSocket: $wsUrl');

      // Create WebSocket connection with SSL certificate handling
      print('🔄 [WebSocket] Creating WebSocket channel...');
      _channel = await _createWebSocketChannel(wsUrl);
      print('✅ [WebSocket] WebSocket channel created successfully');

      // Listen to messages
      print('🔄 [WebSocket] Setting up message listeners...');
      _channel!.stream.listen(
        (message) {
          _handleMessage(message); // Fire and forget - async method
        },
        onError: (error) {
          print('❌ [WebSocket] Stream error: $error');
          _onConnectionError(error);
        },
        onDone: () {
          print('🔌 [WebSocket] Stream done (connection closed)');
          _onConnectionClosed();
        },
        cancelOnError: false,
      );
      print('✅ [WebSocket] Message listeners set up');

      // Send connect message after a short delay to ensure connection is established
      print('🔄 [WebSocket] Waiting 500ms before sending connect message...');
      await Future.delayed(const Duration(milliseconds: 500));
      print('🔄 [WebSocket] Sending connect message...');
      await _sendConnectMessage();
      print('✅ [WebSocket] Connect message sent');

      // Only update state and print if we're still the one connecting (prevent duplicate messages)
      if (_isConnecting) {
        _isConnected = true;
        _isConnecting = false;
        _reconnectAttempts = 0;
        _lastPingReceivedTime = DateTime.now().millisecondsSinceEpoch;
        _updateConnectionMetrics('connected'); // This already logs the connection message
        
        // Start connection health monitoring
        _startConnectionHealthMonitor();
        
        // Note: Online status is managed by app lifecycle in main.dart
        // to avoid duplicate updates when both WebSocket and lifecycle fire
      }
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _updateConnectionMetrics('failed');
      print('❌ [WebSocket] Error connecting to WebSocket: $e');
      _onConnectionError(e);
    }
  }

  /// Send connection message
  Future<void> _sendConnectMessage() async {
    try {
      if (_channel == null) {
        print('❌ [WebSocket] Cannot send connect message: channel is null');
        return;
      }

      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      _userId = user?.id;
      final userName = user?.username ?? ''; // Use username field as userName
      
      print('🔄 [WebSocket] Preparing connect message: userId=$_userId, userName=$userName, sessionId=$_sessionId');
      
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();

      // Remove the 'device' field from deviceInfo to avoid overwriting our device type
      deviceInfo.remove('device');

      final connectMessage = {
        'type': 'connect',
        'sessionId': _sessionId,
        'userId': _userId,
        'userName': userName,
        'deviceInfo': {
          'device': await _getDeviceType(deviceInfo),
          'browser': 'Skybyn App',
          ...deviceInfo,
        },
      };
      final messageJson = jsonEncode(connectMessage);
      print('📤 [WebSocket] Sending connect message: $messageJson');
      _channel!.sink.add(messageJson);
      print('✅ [WebSocket] Connect message sent successfully');
    } catch (e, stackTrace) {
      print('❌ [WebSocket] Error sending connect message: $e');
      print('❌ [WebSocket] Stack trace: $stackTrace');
    }
  }

  /// Get device type string
  Future<String> _getDeviceType(Map<String, dynamic> deviceInfo) async {
    final platform = deviceInfo['platform'] ?? 'Unknown';

    if (platform == 'Android') {
      final brand = deviceInfo['brand'] ?? 'Unknown';
      final model = deviceInfo['model'] ?? 'Unknown';
      final version = deviceInfo['version'] ?? 'Unknown';
      return '$brand $model (Android $version)';
    } else if (platform == 'iOS') {
      final name = deviceInfo['name'] ?? deviceInfo['localizedModel'] ?? 'Unknown';
      final systemVersion = deviceInfo['systemVersion'] ?? 'Unknown';
      return '$name (iOS $systemVersion)';
    } else {
      return 'Unknown Device';
    }
  }

  /// Handle incoming messages
  Future<void> _handleMessage(dynamic message) async {
    try {
      if (message is String) {
        final data = json.decode(message);

        if (data is Map) {
          _updateConnectionMetrics('message_received');
          final messageType = data['type']?.toString();

          // Log ping messages in debug mode to monitor connection stability
          if (messageType == 'ping') {
            // Update last ping received time to track connection health
            _lastPingReceivedTime = DateTime.now().millisecondsSinceEpoch;
            
            if (kDebugMode) {
              print('📥 [WebSocket] Received PING from server - responding with PONG (sessionId: $_sessionId)');
            }
            // Always respond to ping immediately, even in background
            // Note: Only server sends pings, clients only respond with pongs
            _sendPong();
            return; // Early return to avoid processing in switch statement
          } else if (messageType == 'pong') {
            // Note: Clients should not receive PONG messages - only the server sends PINGs
            // and clients respond with PONGs. This is unexpected.
            if (kDebugMode) {
              print('⚠️ [WebSocket] Received PONG (unexpected - clients should not receive PONGs, only respond with PONGs)');
            }
            return; // Early return to avoid processing in switch statement
          } else {
            print('📨 [WebSocket] Received message: $message');
          }

          switch (messageType) {
            case 'ack':
              _handleAcknowledgment(Map<String, dynamic>.from(data));
              break;
            case 'broadcast':
              final broadcastMessage = data['message']?.toString() ?? 'Broadcast message';
              _onBroadcast?.call(broadcastMessage);

              // Show notification for broadcast
              _notificationService.showNotification(
                title: 'Broadcast',
                body: broadcastMessage,
                payload: message,
              );
              break;
            case 'new_post':
              final postId = data['id']?.toString();
              _handleNewPost(postId ?? '');

              // Show notification for new post
              _notificationService.showNotification(
                title: 'New Post',
                body: 'Someone posted something new',
                payload: message,
              );
              break;
            case 'delete_post':
              final postId = data['id']?.toString();
              _handleDeletePost(postId ?? '');
              break;
            case 'new_comment':
              final postId = data['pid']?.toString();
              final commentId = data['cid']?.toString();
              _handleNewComment(postId ?? '', commentId ?? '');

              // Show notification for new comment
              _notificationService.showNotification(
                title: 'New Comment',
                body: 'Someone commented on a post',
                payload: message,
              );
              break;
            case 'delete_comment':
              final postId = data['pid']?.toString();
              final commentId = data['id']?.toString();
              _handleDeleteComment(postId ?? '', commentId ?? '');
              break;
            case 'notification':
              // Handle notification (e.g., chat message notification)
              final notificationType = data['notificationType']?.toString();
              final fromUserId = data['from']?.toString();
              final fromName = data['fromName']?.toString();
              final message = data['message']?.toString();
              final messageId = data['messageId']?.toString();
              
              if (notificationType == 'chat' && fromUserId != null && message != null) {
                print('💬 [WebSocket] Received chat notification: from=$fromUserId, message=$message');
                
                // Show in-app notification for chat message when app is open
                try {
                  await _notificationService.showNotification(
                    title: fromName ?? 'New Message',
                    body: message,
                    payload: jsonEncode({
                      'type': 'chat',
                      'from': fromUserId,
                      'messageId': messageId,
                      'to': _userId,
                    }),
                  );
                  print('✅ [WebSocket] Chat notification shown successfully');
                } catch (e) {
                  print('❌ [WebSocket] Error showing chat notification: $e');
                }
                
                // Also trigger chat message callback if registered
                if (messageId != null && fromUserId != null) {
                  _onChatMessage?.call(messageId, fromUserId, _userId ?? '', message);
                }
              } else {
                // Generic notification
                _notificationService.showNotification(
                  title: data['title']?.toString() ?? 'Notification',
                  body: data['message']?.toString() ?? data['body']?.toString() ?? '',
                  payload: message,
                );
              }
              break;
            case 'app_update':
              _handleAppUpdate();
              break;
            case 'call_initiate':
              final callId = data['callId']?.toString() ?? '';
              final fromUserId = data['fromUserId']?.toString() ?? '';
              final callType = data['callType']?.toString() ?? 'audio';
              final fromUsername = data['fromUsername']?.toString() ?? '';
              _onCallInitiate?.call(callId, fromUserId, callType, fromUsername);
              break;
            case 'call_offer':
              final callId = data['callId']?.toString() ?? '';
              final fromUserId = data['fromUserId']?.toString() ?? '';
              final offer = data['offer']?.toString() ?? '';
              final callType = data['callType']?.toString() ?? 'audio';
              print('📞 [WebSocket] Received call_offer: callId=$callId, fromUserId=$fromUserId, type=$callType');
              if (_onCallOffer == null) {
                print('⚠️ [WebSocket] call_offer callback is null');
              } else {
                _onCallOffer?.call(callId, fromUserId, offer, callType);
              }
              break;
            case 'call_answer':
              final callId = data['callId']?.toString() ?? '';
              final answer = data['answer']?.toString() ?? '';
              print('📞 [WebSocket] Received call_answer: callId=$callId, answerLength=${answer.length}');
              if (_onCallAnswer == null) {
                print('⚠️ [WebSocket] call_answer callback is null');
              } else {
                _onCallAnswer?.call(callId, answer);
              }
              break;
            case 'ice_candidate':
              final callId = data['callId']?.toString() ?? '';
              final candidate = data['candidate']?.toString() ?? '';
              final sdpMid = data['sdpMid']?.toString() ?? '';
              final sdpMLineIndex = (data['sdpMLineIndex'] as num?)?.toInt() ?? 0;
              _onIceCandidate?.call(callId, candidate, sdpMid, sdpMLineIndex);
              break;
            case 'call_end':
              final callId = data['callId']?.toString() ?? '';
              final fromUserId = data['fromUserId']?.toString() ?? '';
              final targetUserId = data['targetUserId']?.toString() ?? '';
              print('📞 [WebSocket] Received call_end: callId=$callId, fromUserId=$fromUserId, targetUserId=$targetUserId');
              if (_onCallEnd == null) {
                print('⚠️ [WebSocket] call_end callback is null');
              } else {
                _onCallEnd?.call(callId, fromUserId, targetUserId);
              }
              break;
            case 'chat':
              final messageId = data['id']?.toString() ?? '';
              final fromUserId = data['from']?.toString() ?? '';
              final toUserId = data['to']?.toString() ?? '';
              final message = data['message']?.toString() ?? '';
              _onChatMessage?.call(messageId, fromUserId, toUserId, message);
              break;
            case 'typing_start':
              final fromUserId = data['fromUserId']?.toString() ?? '';
              _onTypingStatus?.call(fromUserId, true);
              break;
            case 'typing_stop':
              final fromUserId = data['fromUserId']?.toString() ?? '';
              _onTypingStatus?.call(fromUserId, false);
              break;
            case 'online_status':
              final userId = data['userId']?.toString() ?? 
                            data['user_id']?.toString() ?? 
                            data['userID']?.toString() ?? '';
              // Parse isOnline value - check multiple possible field names and formats
              final isOnlineRaw = data['isOnline'] ?? data['online'];
              final parsedIsOnline = isOnlineRaw == true || 
                              isOnlineRaw == 'true' || 
                              isOnlineRaw == 1 ||
                              isOnlineRaw == '1';
              
              // Invert the value if server is sending reversed status
              // Server might be sending: true = offline, false = online
              final isOnline = !parsedIsOnline;
              
              if (kDebugMode) {
                print('📡 [WebSocket] Received online_status: userId=$userId, isOnlineRaw=$isOnlineRaw, parsed=$parsedIsOnline, inverted=$isOnline');
                print('📡 [WebSocket] Raw data: isOnline=${data['isOnline']}, online=${data['online']}');
              }
              
              if (userId.isEmpty) {
                if (kDebugMode) {
                  print('⚠️ [WebSocket] online_status message missing userId');
                }
              } else if (_onOnlineStatusCallbacks.isEmpty) {
                if (kDebugMode) {
                  print('⚠️ [WebSocket] No online_status callbacks registered');
                }
              } else {
                if (kDebugMode) {
                  print('✅ [WebSocket] Calling ${_onOnlineStatusCallbacks.length} online_status callback(s) for userId=$userId');
                }
                // Call all registered online status callbacks
                for (final callback in _onOnlineStatusCallbacks) {
                  try {
                    callback(userId, isOnline);
                  } catch (e) {
                    print('❌ [WebSocket] Error in online status callback: $e');
                  }
                }
              }
              break;
          }
        }
      }
    } catch (e) {
      print('❌ [WebSocket] Error handling message: $e');
    }
  }

  /// Handle new post
  void _handleNewPost(String postId) {
    print('📝 [WebSocket] Processing new post: $postId');
    // Fetch the post details and call the callback
    // This would typically involve fetching the post from the API
    _onNewPost?.call(Post(
      id: postId,
      userId: '',
      author: '',
      content: '',
      likes: 0,
      comments: 0,
      isLiked: false,
      createdAt: DateTime.now(),
      avatar: null,
    ));
  }

  /// Handle delete post
  void _handleDeletePost(String postId) {
    print('🗑️ [WebSocket] Processing delete post: $postId');
    _onDeletePost?.call(postId);
  }

  /// Handle new comment
  void _handleNewComment(String postId, String commentId) {
    print('💬 [WebSocket] Processing new comment: $commentId on post: $postId');
    _onNewComment?.call(postId, commentId);
  }

  /// Handle delete comment
  void _handleDeleteComment(String postId, String commentId) {
    print('🗑️ [WebSocket] Processing delete comment: $commentId on post: $postId');
    _onDeleteComment?.call(postId, commentId);
  }

  /// Handle app update notification
  void _handleAppUpdate() {
    // Skip app update notifications in debug mode
    if (kDebugMode) {
      print('⚠️ [WebSocket] App update notification ignored in debug mode');
      return;
    }

    print('📱 [WebSocket] Processing app update notification');

    // Show notification for app update
    _notificationService.showNotification(
      title: 'App Update Available',
      body: 'A new version of Skybyn is ready to download',
      payload: 'app_update',
    );

    // Trigger the update check callback to show dialog
    _onAppUpdate?.call();
  }

  /// Handle acknowledgment
  void _handleAcknowledgment(Map<String, dynamic> data) {
    final messageId = data['messageId']?.toString();
    if (messageId != null && _pendingMessages.containsKey(messageId)) {
      final pendingMessage = _pendingMessages[messageId];
      if (pendingMessage != null) {
        final timestamp = pendingMessage['timestamp'] as int?;
        if (timestamp != null) {
          final latency = DateTime.now().millisecondsSinceEpoch - timestamp;

          // Update latency metrics
          _connectionMetrics['lastLatency'] = latency;
          if (_connectionMetrics['averageLatency'] == 0) {
            _connectionMetrics['averageLatency'] = latency;
          } else {
            _connectionMetrics['averageLatency'] = (_connectionMetrics['averageLatency'] + latency) / 2;
          }

          // Remove from pending
          _pendingMessages.remove(messageId);

          print('✅ [WebSocket] Message $messageId acknowledged (${latency}ms)');
        }
      }
    }
  }

  /// Send pong response
  void _sendPong() {
    if (kDebugMode) {
      print('📤 [WebSocket] Sending PONG response (sessionId: $_sessionId)');
    }
    final pongMessage = {
      'type': 'pong',
      'sessionId': _sessionId,
    };
    _sendMessageInternal(pongMessage);
  }

  /// Send delete post message
  void sendDeletePost(String postId) {
    final deleteMessage = {
      'type': 'delete_post',
      'sessionId': _sessionId,
      'id': postId,
    };
    _sendMessageInternal(deleteMessage);
  }

  /// Send delete comment message
  void sendDeleteComment(String postId, String commentId) {
    final deleteMessage = {
      'type': 'delete_comment',
      'sessionId': _sessionId,
      'pid': postId,
      'id': commentId,
    };
    _sendMessageInternal(deleteMessage);
  }

  /// Send new post message
  void sendNewPost(String postId) {
    final newPostMessage = {
      'type': 'new_post',
      'sessionId': _sessionId,
      'id': postId,
    };
    _sendMessageInternal(newPostMessage);
  }

  /// Send new comment message
  void sendNewComment(String postId, String commentId) {
    final newCommentMessage = {
      'type': 'new_comment',
      'sessionId': _sessionId,
      'pid': postId,
      'cid': commentId,
    };
    _sendMessageInternal(newCommentMessage);
  }

  /// Send custom message
  /// Send a raw message string via WebSocket
  /// Returns true if message was sent successfully, false otherwise
  Future<bool> sendMessage(String message) async {
    try {
      if (!_isConnected || _channel == null) {
        if (kDebugMode) {
          print('⚠️ [WebSocket] WebSocket not connected, cannot send message');
        }
        return false;
      }

      // Try to send the message
      // The sink.add() will throw if the channel is closed
      _channel!.sink.add(message);
      _updateConnectionMetrics('message_sent');
      
      if (kDebugMode) {
        print('📤 [WebSocket] Message sent: $message');
      }
      return true;
    } catch (e, stackTrace) {
      // Log error in both debug and release (using debugPrint which works in release)
      debugPrint('❌ [WebSocket] Error sending message: $e');
      if (kDebugMode) {
        debugPrint('Stack trace: $stackTrace');
      }
      _updateConnectionMetrics('error');
      
      // If channel error, mark as disconnected and reconnect
      _isConnected = false;
      _scheduleReconnect();
      
      return false;
    }
  }

  /// Set call-related callbacks
  void setCallCallbacks({
    Function(String, String, String, String)? onCallInitiate,
    Function(String, String, String, String)? onCallOffer,
    Function(String, String)? onCallAnswer,
    Function(String, String, String, int)? onIceCandidate,
    Function(String, String, String)? onCallEnd, // callId, fromUserId, targetUserId
  }) {
    _onCallInitiate = onCallInitiate;
    _onCallOffer = onCallOffer;
    _onCallAnswer = onCallAnswer;
    _onIceCandidate = onIceCandidate;
    _onCallEnd = onCallEnd;
  }

  /// Send call offer
  void sendCallOffer({
    required String callId,
    required String targetUserId,
    required String offer,
    required String callType,
  }) {
    final message = {
      'type': 'call_offer',
      'callId': callId,
      'targetUserId': targetUserId,
      'offer': offer,
      'callType': callType,
      'sessionId': _sessionId,
    };
    print('📞 [WebSocket] Sending call_offer: callId=$callId, targetUserId=$targetUserId, type=$callType, connected=$_isConnected');
    _sendMessageInternal(message);
  }

  /// Send call answer
  void sendCallAnswer({
    required String callId,
    required String targetUserId,
    required String answer,
  }) {
    final message = {
      'type': 'call_answer',
      'callId': callId,
      'targetUserId': targetUserId,
      'answer': answer,
      'sessionId': _sessionId,
    };
    _sendMessageInternal(message);
  }

  /// Send ICE candidate
  void sendIceCandidate({
    required String callId,
    required String targetUserId,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) {
    final message = {
      'type': 'ice_candidate',
      'callId': callId,
      'targetUserId': targetUserId,
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
      'sessionId': _sessionId,
    };
    if (kDebugMode) {
      print('📞 [WebSocket] Sending ice_candidate: callId=$callId, targetUserId=$targetUserId');
    }
    _sendMessageInternal(message);
  }

  /// Send call end
  void sendCallEnd({
    required String callId,
    required String targetUserId,
  }) {
    final message = {
      'type': 'call_end',
      'callId': callId,
      'targetUserId': targetUserId,
      'sessionId': _sessionId,
    };
    print('📞 [WebSocket] Sending call_end: callId=$callId, targetUserId=$targetUserId');
    _sendMessageInternal(message);
  }

  /// Send typing start indicator
  void sendTypingStart(String targetUserId) {
    final message = {
      'type': 'typing_start',
      'targetUserId': targetUserId,
      'sessionId': _sessionId,
    };
    _sendMessageInternal(message);
  }

  /// Send typing stop indicator
  void sendTypingStop(String targetUserId) {
    final message = {
      'type': 'typing_stop',
      'targetUserId': targetUserId,
      'sessionId': _sessionId,
    };
    _sendMessageInternal(message);
  }

  /// Handle connection closed
  void _onConnectionClosed() {
    print('🔌 [WebSocket] WebSocket connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Handle connection error
  void _onConnectionError(error) {
    print('❌ [WebSocket] WebSocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Schedule reconnection with exponential backoff
  /// Reconnects automatically when connection is lost
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('❌ [WebSocket] Max reconnection attempts reached. Resetting and retrying...');
      // Reset attempts after a delay to allow retry
      _reconnectAttempts = 0;
      _updateConnectionMetrics('failed');
      // Schedule a retry after 30 seconds
      _reconnectTimer = Timer(const Duration(seconds: 30), () {
        if (!_isConnected && !_isConnecting) {
          _reconnectAttempts = 0; // Reset attempts
          _scheduleReconnect();
        }
      });
      return;
    }

    final delay = _getReconnectDelay();
    _reconnectAttempts++;

    print('🔄 [WebSocket] Scheduling reconnection in ${delay}ms (attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (!_isConnected && !_isConnecting) {
        print('🔄 [WebSocket] Attempting to reconnect...');
        connect();
      }
    });
  }

  /// Generate session ID
  String _generateSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(32, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  /// Stop the WebSocket service
  Future<void> stop() async {
    try {
      print('🛑 [WebSocket] Stopping WebSocket service...');

      // Close WebSocket connection
      disconnect();

      _isInitialized = false;

      // Log final metrics
      _logConnectionQuality();

      print('✅ [WebSocket] WebSocket service stopped');
    } catch (e) {
      print('❌ [WebSocket] Error stopping WebSocket service: $e');
      _updateConnectionMetrics('error');
    }
  }

  /// Test if the WebSocket connection is actually alive
  /// Returns true if connection is alive, false if dead
  bool _testConnection() {
    if (!_isConnected || _channel == null) {
      return false;
    }
    
    try {
      // Try to check if the channel is still valid by checking if it's closed
      // Note: WebSocketChannel doesn't expose a direct "isClosed" property,
      // but we can try to send a test message or check the sink
      // For now, we'll check if we've received a ping recently
      if (_lastPingReceivedTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final timeSinceLastPing = now - _lastPingReceivedTime!;
        // If we haven't received a ping in 2 minutes, connection is likely dead
        if (timeSinceLastPing > 120000) {
          print('⚠️ [WebSocket] Connection test failed: No ping received in ${timeSinceLastPing ~/ 1000} seconds');
          return false;
        }
      }
      return true;
    } catch (e) {
      print('❌ [WebSocket] Connection test error: $e');
      return false;
    }
  }

  /// Force reconnection even if connection appears to be active
  /// Useful when app resumes from background
  Future<void> forceReconnect() async {
    print('🔄 [WebSocket] Force reconnecting...');
    
    // Disconnect current connection if it exists
    if (_channel != null) {
      try {
        _channel!.sink.close();
      } catch (e) {
        print('⚠️ [WebSocket] Error closing channel during force reconnect: $e');
      }
    }
    
    // Reset connection state
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _lastPingReceivedTime = null;
    _reconnectAttempts = 0;
    
    // Cancel any existing reconnect timers
    _reconnectTimer?.cancel();
    _connectionHealthTimer?.cancel();
    
    // Reconnect immediately
    await connect();
  }

  /// Disconnect from WebSocket
  void disconnect() {
    print('🔌 [WebSocket] Disconnecting from WebSocket...');
    _reconnectTimer?.cancel();
    _connectionHealthTimer?.cancel();
    
    // Close channel gracefully
    try {
      _channel?.sink.close();
    } catch (e) {
      print('⚠️ [WebSocket] Error closing channel: $e');
    }
    
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _lastPingReceivedTime = null;

    // Clear message queues
    _messageQueue.clear();
    _pendingMessages.clear();
    print('✅ [WebSocket] Disconnected from WebSocket');
    
    // Update online status to false when disconnected
    _updateOnlineStatusOnDisconnect();
  }

  /// Start connection health monitoring
  /// Monitors if server is still sending pings (server sends pings every 30 seconds)
  void _startConnectionHealthMonitor() {
    _connectionHealthTimer?.cancel();
    
    if (kDebugMode) {
      print('🔄 [WebSocket] Starting connection health monitor');
      print('ℹ️ [WebSocket] Server will send PINGs - client will only respond with PONGs');
    }
    
    // Check every 20 seconds to detect dead connections faster
    // If we haven't received a ping from server in 60 seconds (2x interval), connection is likely dead
    _connectionHealthTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (!_isConnected || _channel == null) {
        timer.cancel();
        return;
      }
      
      // Test connection health
      if (!_testConnection()) {
        print('⚠️ [WebSocket] Connection health check failed - forcing reconnection');
        _onConnectionClosed();
        return;
      }
      
      if (_lastPingReceivedTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final timeSinceLastPing = now - _lastPingReceivedTime!;
        
        // If we haven't received a ping from server in 60 seconds, connection is likely dead
        if (timeSinceLastPing > 60000) {
          print('⚠️ [WebSocket] No PING from server in ${timeSinceLastPing ~/ 1000} seconds - connection may be dead');
          // Connection appears dead, trigger reconnection
          _onConnectionClosed();
        }
      } else {
        // If we've never received a ping and it's been more than 30 seconds since connection,
        // the connection might be dead
        final connectionStartTime = _connectionMetrics['connectionStartTime'] as int?;
        if (connectionStartTime != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final timeSinceConnection = now - connectionStartTime;
          if (timeSinceConnection > 30000) {
            print('⚠️ [WebSocket] No PING received since connection (${timeSinceConnection ~/ 1000} seconds ago) - connection may be dead');
            _onConnectionClosed();
          }
        }
      }
    });
  }

  /// Update online status when disconnecting
  /// Note: This is handled by app lifecycle in main.dart to avoid duplicate updates
  Future<void> _updateOnlineStatusOnDisconnect() async {
    // Online status is managed by app lifecycle, not WebSocket disconnect
    // This prevents duplicate updates when app goes to background
  }

  /// Remove an online status callback (for cleanup when widgets are disposed)
  void removeOnlineStatusCallback(void Function(String, bool) callback) {
    _onOnlineStatusCallbacks.remove(callback);
  }
}

