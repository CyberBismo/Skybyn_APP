import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
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

  // Callbacks for WebRTC signaling
  Function(String, String, String, String)? _onCallOffer; // callId, fromUserId, offer, callType
  Function(String, String)? _onCallAnswer; // callId, answer
  Function(String, String, String, int)? _onIceCandidate; // callId, candidate, sdpMid, sdpMLineIndex
  Function(String)? _onCallEnd; // callId
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
    return 'wss://server.skybyn.no:$port';
  }

  /// Connect to WebSocket with callbacks
  /// Only connects when app is in foreground
  Future<void> connect({
    Function(Post)? onNewPost,
    Function(String, String)? onNewComment,
    Function(String)? onDeletePost,
    Function(String, String)? onDeleteComment,
    Function(String)? onBroadcast,
    Function()? onAppUpdate,
    Function(String, String, String, String)? onChatMessage, // messageId, fromUserId, toUserId, message
  }) async {
    // Store callbacks (merge - only update if non-null, preserve existing if null)
    if (onNewPost != null) _onNewPost = onNewPost;
    if (onNewComment != null) _onNewComment = onNewComment;
    if (onDeletePost != null) _onDeletePost = onDeletePost;
    if (onDeleteComment != null) _onDeleteComment = onDeleteComment;
    if (onBroadcast != null) _onBroadcast = onBroadcast;
    if (onAppUpdate != null) _onAppUpdate = onAppUpdate;
    if (onChatMessage != null) _onChatMessage = onChatMessage;

    // Don't connect if already connected or connecting
    // Check and set _isConnecting atomically to prevent race conditions
    if (_isConnected) {
      print('ℹ️ [WebSocket] Already connected, skipping connection (callbacks updated)');
      return;
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

      // Create WebSocket connection
      _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));

      // Listen to messages
      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          _onConnectionError(error);
        },
        onDone: () {
          _onConnectionClosed();
        },
        cancelOnError: false,
      );

      // Send connect message after a short delay to ensure connection is established
      await Future.delayed(const Duration(milliseconds: 500));
      await _sendConnectMessage();

      // Only update state and print if we're still the one connecting (prevent duplicate messages)
      if (_isConnecting) {
        _isConnected = true;
        _isConnecting = false;
        _reconnectAttempts = 0;
        _updateConnectionMetrics('connected');
        
        print('✅ [WebSocket] Connected to WebSocket server');
        
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
    final authService = AuthService();
    final user = await authService.getStoredUserProfile();
    _userId = user?.id;
    final userName = user?.username ?? ''; // Use username field as userName
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
    _channel?.sink.add(messageJson);
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
  void _handleMessage(dynamic message) {
    try {
      if (message is String) {
        final data = json.decode(message);

        if (data is Map) {
          _updateConnectionMetrics('message_received');
          final messageType = data['type']?.toString();

          // Don't log ping messages to reduce noise
          if (messageType != 'ping') {
            print('📨 [WebSocket] Received message: $message');
          }

          switch (messageType) {
            case 'ping':
              _sendPong();
              break;
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
              _onCallOffer?.call(callId, fromUserId, offer, callType);
              break;
            case 'call_answer':
              final callId = data['callId']?.toString() ?? '';
              final answer = data['answer']?.toString() ?? '';
              _onCallAnswer?.call(callId, answer);
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
              _onCallEnd?.call(callId);
              break;
            case 'chat':
              final messageId = data['id']?.toString() ?? '';
              final fromUserId = data['from']?.toString() ?? '';
              final toUserId = data['to']?.toString() ?? '';
              final message = data['message']?.toString() ?? '';
              _onChatMessage?.call(messageId, fromUserId, toUserId, message);
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
  Future<void> sendMessage(String message) async {
    try {
      if (_isConnected && _channel != null) {
        _channel!.sink.add(message);
        print('📤 [WebSocket] Message sent: $message');
      } else {
        print('⚠️ [WebSocket] WebSocket not connected, cannot send message');
      }
    } catch (e) {
      print('❌ [WebSocket] Error sending message: $e');
    }
  }

  /// Set call-related callbacks
  void setCallCallbacks({
    Function(String, String, String, String)? onCallInitiate,
    Function(String, String, String, String)? onCallOffer,
    Function(String, String)? onCallAnswer,
    Function(String, String, String, int)? onIceCandidate,
    Function(String)? onCallEnd,
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
  /// Only reconnects if app is in foreground (not called when disconnected intentionally)
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('❌ [WebSocket] Max reconnection attempts reached. Giving up.');
      _updateConnectionMetrics('failed');
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

  /// Disconnect from WebSocket
  void disconnect() {
    print('🔌 [WebSocket] Disconnecting from WebSocket...');
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;

    // Clear message queues
    _messageQueue.clear();
    _pendingMessages.clear();
    print('✅ [WebSocket] Disconnected from WebSocket');
    
    // Update online status to false when disconnected
    _updateOnlineStatusOnDisconnect();
  }

  /// Update online status when disconnecting
  /// Note: This is handled by app lifecycle in main.dart to avoid duplicate updates
  Future<void> _updateOnlineStatusOnDisconnect() async {
    // Online status is managed by app lifecycle, not WebSocket disconnect
    // This prevents duplicate updates when app goes to background
  }
}
