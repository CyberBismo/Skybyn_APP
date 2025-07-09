import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:http/http.dart' as http;
import '../models/post.dart';
import 'auth_service.dart';
import 'device_service.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_database/firebase_database.dart';

class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  // Android: TODO - Use Firestore snapshots or Firebase Realtime Database
  // iOS: Use WebSockets (existing code)

  WebSocketChannel? _channel;
  String? _sessionId;
  String? _userId;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  Function(Post)? _onNewPost;
  Function(String, String)? _onNewComment; // postId, commentId
  Function(String)? _onDeletePost;
  Function(String, String)? _onDeleteComment; // postId, commentId

  bool get isConnected => _isConnected;

  Future<void> connect({
    Function(Post)? onNewPost,
    Function(String, String)? onNewComment,
    Function(String)? onDeletePost,
    Function(String, String)? onDeleteComment,
  }) async {
    print('🔧 [WebSocket] Initializing and connecting...');
    _onNewPost = onNewPost;
    _onNewComment = onNewComment;
    _onDeletePost = onDeletePost;
    _onDeleteComment = onDeleteComment;

    if (_isConnected || _isConnecting) {
      print('🔌 [WebSocket] Already connected or connecting.');
      return;
    }
    _isConnecting = true;
    _sessionId = _generateSessionId();
    final wsUrl = 'wss://dev.skybyn.no:4433'; // Updated WebSocket endpoint
    print('🔌 [WebSocket] Connecting to $wsUrl');
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
      print('✅ [WebSocket] Connected');
    } catch (e, stackTrace) {
      print('❌ [WebSocket] Connection error: $e');
      print(stackTrace);
      _isConnected = false;
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  Future<void> _sendConnectMessage() async {
    print('🔧 [WebSocket] Preparing connect message...');
    final authService = AuthService();
    final user = await authService.getStoredUserProfile();
    final token = user?.token;
    _userId = user?.id;
    final deviceService = DeviceService();
    final deviceInfo = await deviceService.getDeviceInfo();
    
    // Remove the 'device' field from deviceInfo to avoid overwriting our device type
    deviceInfo.remove('device');
    
    final connectMessage = {
      'type': 'connect',
      'sessionId': _sessionId,
      'token': token,
      'url': 'mobile-app',
      'deviceInfo': {
        'device': await _getDeviceType(deviceInfo),
        'browser': 'Flutter Mobile App',
        ...deviceInfo,
      },
    };
    final messageJson = jsonEncode(connectMessage);
    _channel?.sink.add(messageJson);
    print('📤 [WebSocket] Connect message sent: $messageJson');
  }

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

  void _handleMessage(dynamic message) {
    print('📥 [WebSocket] Received message: $message');
    try {
      final data = jsonDecode(message);
      if (data is! Map) return;
      final messageType = data['type']?.toString();
      switch (messageType) {
        case 'ping':
          _sendPong();
          break;
        case 'new_post':
          final postId = data['id']?.toString();
          _handleNewPost(postId ?? '');
          break;
        case 'delete_post':
          final postId = data['id']?.toString();
          _handleDeletePost(postId ?? '');
          break;
        case 'new_comment':
          final postId = data['pid']?.toString();
          final commentId = data['cid']?.toString();
          _handleNewComment(postId ?? '', commentId ?? '');
          break;
        case 'delete_comment':
          final postId = data['pid']?.toString();
          final commentId = data['id']?.toString();
          _handleDeleteComment(postId ?? '', commentId ?? '');
          break;
        case 'broadcast':
          final broadcastMessage = data['message'];
          print('📢 [WebSocket] Broadcast message: $broadcastMessage');
          break;
        default:
          print('❓ [WebSocket] Unknown message type: $messageType');
      }
    } catch (e, stackTrace) {
      print('❌ [WebSocket] Error parsing message: $e');
      print(stackTrace);
    }
  }

  void _sendPong() {
    final pongMessage = {
      'type': 'pong',
      'sessionId': _sessionId,
    };
    final messageJson = jsonEncode(pongMessage);
    _channel?.sink.add(messageJson);
    print('🏓 [WebSocket] Sent pong');
  }

  void sendDeletePost(String postId) {
    if (!_isConnected) {
      print('❌ [WebSocket] Cannot send delete_post: not connected');
      return;
    }
    
    final deleteMessage = {
      'type': 'delete_post',
      'sessionId': _sessionId,
      'id': postId,
    };
    final messageJson = jsonEncode(deleteMessage);
    _channel?.sink.add(messageJson);
    print('🗑️ [WebSocket] Sent delete_post: $messageJson');
  }

  void sendDeleteComment(String postId, String commentId) {
    if (!_isConnected) {
      print('❌ [WebSocket] Cannot send delete_comment: not connected');
      return;
    }
    
    final deleteMessage = {
      'type': 'delete_comment',
      'sessionId': _sessionId,
      'pid': postId,
      'id': commentId,
    };
    final messageJson = jsonEncode(deleteMessage);
    _channel?.sink.add(messageJson);
    print('🗑️ [WebSocket] Sent delete_comment: $messageJson');
  }

  void sendNewPost(String postId) {
    if (!_isConnected) {
      print('❌ [WebSocket] Cannot send new_post: not connected');
      return;
    }
    
    final newPostMessage = {
      'type': 'new_post',
      'sessionId': _sessionId,
      'id': postId,
    };
    final messageJson = jsonEncode(newPostMessage);
    _channel?.sink.add(messageJson);
    print('📝 [WebSocket] Sent new_post: $messageJson');
  }

  void sendNewComment(String postId, String commentId) {
    if (!_isConnected) {
      print('❌ [WebSocket] Cannot send new_comment: not connected');
      return;
    }
    
    final newCommentMessage = {
      'type': 'new_comment',
      'sessionId': _sessionId,
      'pid': postId,
      'cid': commentId,
    };
    final messageJson = jsonEncode(newCommentMessage);
    _channel?.sink.add(messageJson);
    print('💬 [WebSocket] Sent new_comment: $messageJson');
  }

  Future<void> _handleNewPost(String postId) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.skybyn.no/post/get_post.php'),
        body: {'postID': postId, 'userID': _userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty && data.first['responseCode'] == '1') {
          final post = Post.fromJson(data.first);
          _onNewPost?.call(post);
        }
      }
    } catch (e, stackTrace) {
      print('❌ [WebSocket] Error fetching new post: $e');
      print(stackTrace);
    }
  }

  void _handleDeletePost(String postId) {
    _onDeletePost?.call(postId);
  }

  void _handleNewComment(String postId, String commentId) {
    _onNewComment?.call(postId, commentId);
  }

  void _handleDeleteComment(String postId, String commentId) {
    _onDeleteComment?.call(postId, commentId);
  }

  void _onConnectionClosed() {
    print('🔌 [WebSocket] Connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _onConnectionError(error) {
    print('❌ [WebSocket] Connection error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts > 5) {
      print('❌ [WebSocket] Max reconnect attempts reached. Giving up.');
      return;
    }
    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    print('🔄 [WebSocket] Reconnecting in ${delay.inSeconds} seconds...');
    Future.delayed(delay, () {
      if (!_isConnected) {
        connect();
      }
    });
  }

  String _generateSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    final sessionId = List.generate(8, (index) => chars[random.nextInt(chars.length)]).join() +
           '-' +
           List.generate(4, (index) => chars[random.nextInt(chars.length)]).join() +
           '-' +
           List.generate(4, (index) => chars[random.nextInt(chars.length)]).join() +
           '-' +
           List.generate(4, (index) => chars[random.nextInt(chars.length)]).join() +
           '-' +
           List.generate(12, (index) => chars[random.nextInt(chars.length)]).join();
    return sessionId;
  }

  void disconnect() {
    print('🔌 [WebSocket] Disconnecting...');
    if (_isConnected) {
      final disconnectMessage = {
        'type': 'disconnect',
        'sessionId': _sessionId,
      };
      final messageJson = jsonEncode(disconnectMessage);
      _channel?.sink.add(messageJson);
      _channel?.sink.close(status.goingAway);
    }
    _isConnected = false;
  }

  void dispose() {
    disconnect();
  }
} 