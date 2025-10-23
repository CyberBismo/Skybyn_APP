import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/services.dart';
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

  // Services
  final NotificationService _notificationService = NotificationService();
  static const MethodChannel _methodChannel = MethodChannel('no.skybyn.app/background_service');

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
        break;
      case 'failed':
        _connectionMetrics['failedConnections']++;
        break;
      case 'message_sent':
        _connectionMetrics['messagesSent']++;
        break;
      case 'message_received':
        _connectionMetrics['messagesReceived']++;
        break;
      case 'error':
        _connectionMetrics['errors']++;
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

      // Start Android foreground service if on Android
      if (Platform.isAndroid) {
        await _startAndroidBackgroundService();
      }

      _isInitialized = true;
      print('✅ [WebSocket] WebSocket service initialized');
    } catch (e) {
      print('❌ [WebSocket] Error initializing WebSocket service: $e');
    }
  }

  /// Start Android background service
  Future<void> _startAndroidBackgroundService() async {
    try {
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod('startBackgroundService');
        print('✅ [WebSocket] Android background service started');
      }
    } catch (e) {
      print('❌ [WebSocket] Error starting Android background service: $e');
    }
  }

  /// Connect to WebSocket with callbacks
  Future<void> connect({
    Function(Post)? onNewPost,
    Function(String, String)? onNewComment,
    Function(String)? onDeletePost,
    Function(String, String)? onDeleteComment,
    Function(String)? onBroadcast,
    Function()? onAppUpdate,
  }) async {
    _onNewPost = onNewPost;
    _onNewComment = onNewComment;
    _onDeletePost = onDeletePost;
    _onDeleteComment = onDeleteComment;
    _onBroadcast = onBroadcast;
    _onAppUpdate = onAppUpdate;

    if (_isConnected || _isConnecting) {
      return;
    }

    _isConnecting = true;
    _updateConnectionMetrics('connecting');
    _sessionId = _generateSessionId();
    const wsUrl = 'wss://server.skybyn.no:4433';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _isConnecting = false;
      _updateConnectionMetrics('connected');

      _channel!.stream.listen(
        _handleMessage,
        onDone: _onConnectionClosed,
        onError: _onConnectionError,
        cancelOnError: true,
      );

      await _sendConnectMessage();
      _processMessageQueue(); // Process any queued messages
      print('✅ [WebSocket] Connected to WebSocket server');

      // Start retry timer
      Timer.periodic(const Duration(seconds: 2), (timer) {
        if (!_isConnected) {
          timer.cancel();
          return;
        }
        _retryPendingMessages();
      });
    } catch (e) {
      print('❌ [WebSocket] Connection error: $e');
      _isConnected = false;
      _isConnecting = false;
      _updateConnectionMetrics('failed');
      _scheduleReconnect();
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
    print('📱 [WebSocket] Processing app update notification');

    // Show notification for app update
    _notificationService.showNotification(
      title: 'App Update Available',
      body: 'A new version of Skybyn is ready to download',
      payload: 'app_update',
    );

    // Trigger update check callback
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
      if (!_isConnected) {
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

      // Stop Android foreground service
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod('stopBackgroundService');
      }

      // Close WebSocket connection
      _channel?.sink.close();
      _reconnectTimer?.cancel();
      _isConnected = false;
      _isInitialized = false;

      // Clear message queues
      _messageQueue.clear();
      _pendingMessages.clear();

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
    _channel?.sink.close();
    _reconnectTimer?.cancel();
    _isConnected = false;
    _isConnecting = false;

    // Clear message queues
    _messageQueue.clear();
    _pendingMessages.clear();
  }
}
