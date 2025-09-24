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
  Timer? _reconnectTimer;
  bool _isInitialized = false;
  
  // Callbacks for real-time updates
  Function(Post)? _onNewPost;
  Function(String, String)? _onNewComment; // postId, commentId
  Function(String)? _onDeletePost;
  Function(String, String)? _onDeleteComment; // postId, commentId
  Function(String)? _onBroadcast; // broadcast message
  
  // Services
  final NotificationService _notificationService = NotificationService();
  static const MethodChannel _methodChannel = MethodChannel('no.skybyn.app/background_service');

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

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
  }) async {
    _onNewPost = onNewPost;
    _onNewComment = onNewComment;
    _onDeletePost = onDeletePost;
    _onDeleteComment = onDeleteComment;
    _onBroadcast = onBroadcast;

    if (_isConnected || _isConnecting) {
      return;
    }
    
    _isConnecting = true;
    _sessionId = _generateSessionId();
    const wsUrl = 'wss://server.skybyn.no:4433';
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      
      _channel!.stream.listen(
        _handleMessage,
        onDone: _onConnectionClosed,
        onError: _onConnectionError,
        cancelOnError: true,
      );
      
      await _sendConnectMessage();
      print('✅ [WebSocket] Connected to WebSocket server');
    } catch (e) {
      print('❌ [WebSocket] Connection error: $e');
      _isConnected = false;
      _isConnecting = false;
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
          final messageType = data['type']?.toString();
          
          // Don't log ping messages to reduce noise
          if (messageType != 'ping') {
            print('📨 [WebSocket] Received message: $message');
          }
          
          switch (messageType) {
            case 'ping':
              _sendPong();
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

  /// Send pong response
  void _sendPong() {
    final pongMessage = {
      'type': 'pong',
      'sessionId': _sessionId,
    };
    final messageJson = jsonEncode(pongMessage);
    _channel?.sink.add(messageJson);
  }

  /// Send delete post message
  void sendDeletePost(String postId) {
    if (!_isConnected) return;
    
    final deleteMessage = {
      'type': 'delete_post',
      'sessionId': _sessionId,
      'id': postId,
    };
    final messageJson = jsonEncode(deleteMessage);
    _channel?.sink.add(messageJson);
  }

  /// Send delete comment message
  void sendDeleteComment(String postId, String commentId) {
    if (!_isConnected) return;
    
    final deleteMessage = {
      'type': 'delete_comment',
      'sessionId': _sessionId,
      'pid': postId,
      'id': commentId,
    };
    final messageJson = jsonEncode(deleteMessage);
    _channel?.sink.add(messageJson);
  }

  /// Send new post message
  void sendNewPost(String postId) {
    if (!_isConnected) return;
    
    final newPostMessage = {
      'type': 'new_post',
      'sessionId': _sessionId,
      'id': postId,
    };
    final messageJson = jsonEncode(newPostMessage);
    _channel?.sink.add(messageJson);
  }

  /// Send new comment message
  void sendNewComment(String postId, String commentId) {
    if (!_isConnected) return;
    
    final newCommentMessage = {
      'type': 'new_comment',
      'sessionId': _sessionId,
      'pid': postId,
      'cid': commentId,
    };
    final messageJson = jsonEncode(newCommentMessage);
    _channel?.sink.add(messageJson);
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

  /// Schedule reconnection
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 30), () {
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
      
      print('✅ [WebSocket] WebSocket service stopped');
    } catch (e) {
      print('❌ [WebSocket] Error stopping WebSocket service: $e');
    }
  }

  /// Disconnect from WebSocket
  void disconnect() {
    _channel?.sink.close();
    _reconnectTimer?.cancel();
    _isConnected = false;
    _isConnecting = false;
  }
} 