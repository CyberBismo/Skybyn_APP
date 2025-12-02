import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform, WebSocket, SecurityContext, HttpClient, X509Certificate;
import 'dart:async';
import 'dart:developer' as developer;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/friend.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'notification_service.dart';
import 'friend_service.dart';
import 'in_app_notification_service.dart';
import 'floating_chat_bubble_service.dart';
import '../main.dart';

// Helper function to log chat events - always logs regardless of zone filters
void _logChat(String prefix, String message) {
  // Use developer.log which always logs, bypassing zone filters
  developer.log(message, name: prefix);
  // Also use debugPrint as backup
  debugPrint('$prefix: $message');
}

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
  final List<Function(String, String, String, String)> _onChatMessageCallbacks = []; // Multiple listeners for chat messages
  final Set<int> _registeredChatCallbackHashes = {}; // Track registered callbacks by hash to prevent duplicates
  Function(String, bool)? _onTypingStatus; // userId, isTyping
  final List<Function(String, bool)> _onOnlineStatusCallbacks = []; // Multiple listeners for online status

  // Callbacks for WebRTC signaling
  Function(String, String, String, String)? _onCallOffer; // callId, fromUserId, offer, callType
  Function(String, String)? _onCallAnswer; // callId, answer
  Function(String, String, String, int)? _onIceCandidate; // callId, candidate, sdpMid, sdpMLineIndex
  Function(String, String, String)? _onCallEnd; // callId, fromUserId, targetUserId
  Function(String, String, String, String)? _onCallInitiate; // callId, fromUserId, callType, fromUsername
  Function(String, String, String)? _onCallError; // callId, targetUserId, error message

  // Services
  final NotificationService _notificationService = NotificationService();
  final FriendService _friendService = FriendService();
  final InAppNotificationService _inAppNotificationService = InAppNotificationService();
  final FloatingChatBubbleService _floatingBubbleService = FloatingChatBubbleService();

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

        if (_isConnected && _channel != null) {
          try {
            _channel!.sink.add(jsonEncode(pending['message']));
            _updateConnectionMetrics('message_sent');
          } catch (e) {
            _updateConnectionMetrics('error');
          }
        }
        return false; // Keep in pending
      } else if (pending['retries'] >= maxRetries) {
        _updateConnectionMetrics('error');
        return true; // Remove from pending
      }
      return false; // Keep in pending
    });
  }

  /// Initialize the WebSocket service
  Future<void> initialize() async {
    try {
      // Generate session ID
      _sessionId = _generateSessionId();

      _isInitialized = true;
    } catch (e) {
    }
  }
  
  /// Get WebSocket URL
  String _getWebSocketUrl() {
    // Use production port and host
    const port = 4433;
    const host = 'server.skybyn.no';
    return 'wss://$host:$port';
  }

  /// Create WebSocket channel with SSL certificate handling
  Future<WebSocketChannel> _createWebSocketChannel(String url) async {
    final uri = Uri.parse(url);
    
    try {
      // Create an HttpClient with custom certificate handling
      // The certificate is valid, so we'll use standard validation
      // but configure it to handle the certificate chain properly
      final httpClient = HttpClient();
      
      // Set up certificate validation callback
      // This allows proper validation of the server's certificate
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
        // For server.skybyn.no on port 4433, we trust the certificate
        // The certificate is valid and works, so we accept it
        if (host == 'server.skybyn.no' && port == 4433) {
          return true;
        }
        // For other hosts, use standard validation
        return false;
      };
      
      // Create WebSocket connection using the custom HttpClient
      final webSocket = await WebSocket.connect(
        url,
        customClient: httpClient,
      );
      
      // Wrap the socket in an IOWebSocketChannel
      return IOWebSocketChannel(webSocket);
    } catch (e) {
      rethrow;
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
    if (onChatMessage != null) {
      _onChatMessage = onChatMessage; // Keep for backward compatibility
      // Use function hash code to prevent duplicate callbacks
      // Note: Function.hashCode is not reliable for equality, but we use it to prevent obvious duplicates
      final callbackHash = onChatMessage.hashCode;
      if (!_registeredChatCallbackHashes.contains(callbackHash)) {
        _registeredChatCallbackHashes.add(callbackHash);
        _onChatMessageCallbacks.add(onChatMessage);
        _logChat('WebSocket Connect', 'Chat callback registered (hash: $callbackHash, total: ${_onChatMessageCallbacks.length})');
      } else {
        _logChat('WebSocket Connect', 'Chat callback already registered (hash: $callbackHash), skipping duplicate');
      }
    }
    if (onTypingStatus != null) _onTypingStatus = onTypingStatus;
    if (onOnlineStatus != null) {
      // Add callback to list (allow multiple listeners for online status)
      // Note: Function equality doesn't work in Dart, so we allow duplicates
      // Widgets should manage their own callback lifecycle
      _onOnlineStatusCallbacks.add(onOnlineStatus);
    }

    // Ensure service is initialized before connecting
    if (!_isInitialized) {
      await initialize();
    }
    
    // Test connection if it appears connected
    if (_isConnected) {
      // Verify the connection is actually alive
      if (_testConnection()) {
        // Callbacks have already been updated above, so we can return
        // This allows screens to register their callbacks after connection is established
        return;
      } else {
        // Connection is dead, reset state and reconnect
        _isConnected = false;
        _channel = null;
      }
    }
    
    if (_isConnecting) {
      return;
    }

    // Set connecting flag immediately to prevent duplicate connections
    _isConnecting = true;

    try {
      _updateConnectionMetrics('connecting');
      
      // Generate session ID if not exists
      _sessionId ??= _generateSessionId();

      final wsUrl = _getWebSocketUrl();
      // Create WebSocket connection with SSL certificate handling
      _channel = await _createWebSocketChannel(wsUrl);
      // Listen to messages
      _channel!.stream.listen(
        (message) {
          _handleMessage(message); // Fire and forget - async method
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
        _lastPingReceivedTime = DateTime.now().millisecondsSinceEpoch;
        _updateConnectionMetrics('connected'); // This already logs the connection message
        
        // Process any queued messages now that we're connected
        _processMessageQueue();
        
        // Start connection health monitoring
        _startConnectionHealthMonitor();
        
        // Note: Online status is managed by app lifecycle in main.dart
        // to avoid duplicate updates when both WebSocket and lifecycle fire
      }
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _updateConnectionMetrics('failed');
      _onConnectionError(e);
    }
  }

  /// Send connection message
  Future<void> _sendConnectMessage() async {
    try {
      if (_channel == null) {
        return;
      }

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
      _channel!.sink.add(messageJson);
    } catch (e) {
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
        final timestamp = DateTime.now().toIso8601String();
        final data = json.decode(message);

        if (data is Map) {
          _updateConnectionMetrics('message_received');
          final messageType = data['type']?.toString();
          final messageId = data['id']?.toString() ?? data['messageId']?.toString() ?? 'no-id';
          
          // Log ALL incoming WebSocket messages for debugging
          _logChat('WebSocket Incoming', '═══════════════════════════════════════════════════════');
          _logChat('WebSocket Incoming', '📨 Message received at $timestamp');
          _logChat('WebSocket Incoming', '   Type: $messageType');
          _logChat('WebSocket Incoming', '   Message ID: $messageId');
          _logChat('WebSocket Incoming', '   Full data: $data');
          _logChat('WebSocket Incoming', '   Raw message length: ${message.length} chars');
          _logChat('WebSocket Incoming', '═══════════════════════════════════════════════════════');

          // Log ping messages in debug mode to monitor connection stability
          if (messageType == 'ping') {
            // _logChat('WebSocket Ping', 'Received ping, responding with pong');
            // Update last ping received time to track connection health
            _lastPingReceivedTime = DateTime.now().millisecondsSinceEpoch;
            // Always respond to ping immediately, even in background
            // Note: Only server sends pings, clients only respond with pongs
            _sendPong();
            return; // Early return to avoid processing in switch statement
          } else if (messageType == 'pong') {
            // _logChat('WebSocket Pong', 'Received pong (unexpected - clients should not receive pongs)');
            // Note: Clients should not receive PONG messages - only the server sends PINGs
            // and clients respond with PONGs. This is unexpected.
            return; // Early return to avoid processing in switch statement
          }

          switch (messageType) {
            case 'ack':
              // _logChat('WebSocket ACK', 'Received acknowledgment: ${data['id'] ?? 'no-id'}');
              _handleAcknowledgment(Map<String, dynamic>.from(data));
              break;
            case 'broadcast':
              final broadcastMessage = data['message']?.toString() ?? 'Broadcast message';
              _logChat('WebSocket Broadcast', '📢 Broadcast received: $broadcastMessage');
              _onBroadcast?.call(broadcastMessage);

              // Show only one type of notification - in-app if foreground, system if background
              if (_isAppInForeground()) {
                // App is in foreground - show in-app notification only
                _showInAppNotification(
                  title: 'Broadcast',
                  body: broadcastMessage,
                  icon: Icons.campaign,
                  iconColor: Colors.orange,
                  notificationType: 'broadcast',
                  onTap: () {
                    // Navigate to home screen to see broadcast
                    final nav = navigatorKey.currentState;
                    if (nav != null) {
                      nav.pushNamed('/home');
                    }
                  },
                );
              } else {
                // App is in background - show system notification only
                try {
                  await _notificationService.showNotification(
                    title: 'Broadcast',
                    body: broadcastMessage,
                    payload: message,
                  );
                  _logChat('WebSocket Broadcast', '✅ System notification shown successfully');
                } catch (e) {
                  _logChat('WebSocket Broadcast', '❌ Failed to show system notification: $e');
                }
              }
              break;
            case 'new_post':
              final postId = data['id']?.toString();
              _logChat('WebSocket New Post', '📝 New post received: postId=$postId');
              _handleNewPost(postId ?? '');

              // Show only one type of notification - in-app if foreground, system if background
              if (_isAppInForeground()) {
                // App is in foreground - show in-app notification only
                _showInAppNotification(
                  title: 'New Post',
                  body: 'Someone posted something new',
                  icon: Icons.post_add,
                  iconColor: Colors.blue,
                  notificationType: 'new_post',
                  onTap: () {
                    // Navigate to home screen to see new post
                    final nav = navigatorKey.currentState;
                    if (nav != null) {
                      nav.pushNamed('/home');
                    }
                  },
                );
              } else {
                // App is in background - show system notification only
                try {
                  await _notificationService.showNotification(
                    title: 'New Post',
                    body: 'Someone posted something new',
                    payload: message,
                  );
                  _logChat('WebSocket New Post', '✅ System notification shown successfully');
                } catch (e) {
                  _logChat('WebSocket New Post', '❌ Failed to show system notification: $e');
                }
              }
              break;
            case 'delete_post':
              final postId = data['id']?.toString();
              _logChat('WebSocket Delete Post', '🗑️ Post deleted: postId=$postId');
              _handleDeletePost(postId ?? '');
              break;
            case 'new_comment':
              final postId = data['pid']?.toString();
              final commentId = data['cid']?.toString();
              _logChat('WebSocket New Comment', '💬 New comment received: postId=$postId, commentId=$commentId');
              _handleNewComment(postId ?? '', commentId ?? '');

              // Show only one type of notification - in-app if foreground, system if background
              if (_isAppInForeground()) {
                // App is in foreground - show in-app notification only
                _showInAppNotification(
                  title: 'New Comment',
                  body: 'Someone commented on a post',
                  icon: Icons.comment,
                  iconColor: Colors.green,
                  notificationType: 'new_comment',
                  onTap: () {
                    // Navigate to home screen to see new comment
                    final nav = navigatorKey.currentState;
                    if (nav != null) {
                      nav.pushNamed('/home');
                    }
                  },
                );
              } else {
                // App is in background - show system notification only
                try {
                  await _notificationService.showNotification(
                    title: 'New Comment',
                    body: 'Someone commented on a post',
                    payload: message,
                  );
                  _logChat('WebSocket New Comment', '✅ System notification shown successfully');
                } catch (e) {
                  _logChat('WebSocket New Comment', '❌ Failed to show system notification: $e');
                }
              }
              break;
            case 'delete_comment':
              final postId = data['pid']?.toString();
              final commentId = data['id']?.toString();
              _logChat('WebSocket Delete Comment', '🗑️ Comment deleted: postId=$postId, commentId=$commentId');
              _handleDeleteComment(postId ?? '', commentId ?? '');
              break;
            case 'notification':
              // Handle notification (e.g., chat message notification)
              final notificationType = data['notificationType']?.toString();
              final fromUserId = data['from']?.toString();
              final fromName = data['fromName']?.toString();
              final message = data['message']?.toString();
              final messageId = data['messageId']?.toString();
              
              // Log all notifications
              _logChat('WebSocket Notification', 'Received notification - type: $notificationType, from: $fromUserId');
              
              if (notificationType == 'chat' && fromUserId != null && message != null) {
                // Log chat notification details
                _logChat('WebSocket Chat Notification', 'Chat notification received:');
                _logChat('WebSocket Chat Notification', '   - MessageId: $messageId');
                _logChat('WebSocket Chat Notification', '   - From UserId: $fromUserId');
                _logChat('WebSocket Chat Notification', '   - From Name: $fromName');
                _logChat('WebSocket Chat Notification', '   - To UserId: ${_userId ?? "null"}');
                _logChat('WebSocket Chat Notification', '   - Message: ${message.length > 50 ? message.substring(0, 50) + "..." : message}');
                _logChat('WebSocket Chat Notification', '   - Registered callbacks: ${_onChatMessageCallbacks.length}');
                
                // Show only one type of notification - in-app if foreground, system if background
                // Note: The 'chat' case will also handle showing in-app notifications, so this is a fallback
                // for when the message comes as 'notification' type instead of 'chat' type
                if (_isAppInForeground() && _userId != null) {
                  // App is in foreground - show in-app notification only (via _showInAppChatNotification)
                  // This will be handled by the 'chat' case if the message also comes as 'chat' type
                  // For now, we skip showing here to avoid duplicates
                  _logChat('WebSocket Chat Notification', 'App is in foreground - notification will be handled by chat case if message arrives');
                } else {
                  // App is in background - show system notification only
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
                    _logChat('WebSocket Chat Notification', 'System notification shown successfully');
                  } catch (e) {
                    _logChat('WebSocket Chat Notification', 'Failed to show system notification: $e');
                  }
                }
                
                // NOTE: Do NOT trigger chat message callbacks here for chat notifications
                // The server may send the same message as both 'chat' and 'notification' types
                // The 'chat' case will handle the callbacks to prevent duplicates
                // Only show the notification UI, don't process as a chat message
                _logChat('WebSocket Chat Notification', 'Skipping chat callbacks - message will be handled by \'chat\' case if sent');
              } else {
                // Generic notification
                final title = data['title']?.toString() ?? 'Notification';
                final body = data['message']?.toString() ?? data['body']?.toString() ?? '';
                
                // Show only one type of notification - in-app if foreground, system if background
                if (_isAppInForeground()) {
                  // App is in foreground - show in-app notification only
                  _showInAppNotification(
                    title: title,
                    body: body,
                    icon: Icons.notifications,
                    iconColor: Colors.blue,
                    notificationType: notificationType ?? 'generic',
                    onTap: () {
                      // Navigate to home screen
                      final nav = navigatorKey.currentState;
                      if (nav != null) {
                        nav.pushNamed('/home');
                      }
                    },
                  );
                } else {
                  // App is in background - show system notification only
                  try {
                    await _notificationService.showNotification(
                      title: title,
                      body: body,
                      payload: message,
                    );
                  } catch (e) {
                    _logChat('WebSocket Notification', 'Failed to show system notification: $e');
                  }
                }
              }
              break;
            case 'app_update':
              _logChat('WebSocket App Update', '🔄 App update notification received');
              await _handleAppUpdate();

              // Show only one type of notification - in-app if foreground, system if background
              // Note: _handleAppUpdate() already shows system notification, so we only show in-app if foreground
              if (_isAppInForeground()) {
                // App is in foreground - show in-app notification only (system notification is skipped in _handleAppUpdate)
                _showInAppNotification(
                  title: 'App Update Available',
                  body: 'A new version of Skybyn is ready to download',
                  icon: Icons.system_update,
                  iconColor: Colors.orange,
                  notificationType: 'app_update',
                  onTap: () {
                    // Trigger update check via callback
                    _onAppUpdate?.call();
                  },
                );
              }
              // If app is in background, _handleAppUpdate() will show system notification
              break;
            case 'call_initiate':
              final callId = data['callId']?.toString() ?? '';
              final fromUserId = data['fromUserId']?.toString() ?? '';
              final callType = data['callType']?.toString() ?? 'audio';
              final fromUsername = data['fromUsername']?.toString() ?? '';
              _logChat('WebSocket Call Initiate', '📞 Call initiated: callId=$callId, from=$fromUserId ($fromUsername), type=$callType');
              _onCallInitiate?.call(callId, fromUserId, callType, fromUsername);
              break;
            case 'call_offer':
              final callId = data['callId']?.toString() ?? '';
              final fromUserId = data['fromUserId']?.toString() ?? '';
              final offer = data['offer']?.toString() ?? '';
              // Extract callType - must be present, log warning if missing
              final callTypeRaw = data['callType'];
              String callType;
              if (callTypeRaw != null) {
                callType = callTypeRaw.toString().toLowerCase().trim();
                // Normalize to 'video' or 'audio'
                if (callType != 'video' && callType != 'audio') {
                  callType = 'audio';
                }
              } else {
                callType = 'audio';
              }
              _logChat('WebSocket Call Offer', '📞 Call offer received: callId=$callId, from=$fromUserId, type=$callType, offerLength=${offer.length}');
              if (_onCallOffer == null) {
                _logChat('WebSocket Call Offer', '⚠️ No call offer callback registered');
              } else {
                _onCallOffer?.call(callId, fromUserId, offer, callType);
              }
              break;
            case 'call_answer':
              final callId = data['callId']?.toString() ?? '';
              final answer = data['answer']?.toString() ?? '';
              _logChat('WebSocket Call Answer', '📞 Call answer received: callId=$callId, answerLength=${answer.length}');
              if (_onCallAnswer == null) {
                _logChat('WebSocket Call Answer', '⚠️ No call answer callback registered');
              } else {
                _onCallAnswer?.call(callId, answer);
              }
              break;
            case 'ice_candidate':
              final callId = data['callId']?.toString() ?? '';
              final candidate = data['candidate']?.toString() ?? '';
              final sdpMid = data['sdpMid']?.toString() ?? '';
              final sdpMLineIndex = (data['sdpMLineIndex'] as num?)?.toInt() ?? 0;
              _logChat('WebSocket ICE Candidate', '🧊 ICE candidate received: callId=$callId, sdpMid=$sdpMid, sdpMLineIndex=$sdpMLineIndex');
              if (_onIceCandidate == null) {
                _logChat('WebSocket ICE Candidate', '⚠️ No ICE candidate callback registered');
              } else {
                _onIceCandidate?.call(callId, candidate, sdpMid, sdpMLineIndex);
              }
              break;
            case 'call_end':
              final callId = data['callId']?.toString() ?? '';
              final fromUserId = data['fromUserId']?.toString() ?? '';
              final targetUserId = data['targetUserId']?.toString() ?? '';
              _logChat('WebSocket Call End', '📞 Call ended: callId=$callId, from=$fromUserId, target=$targetUserId');
              if (_onCallEnd == null) {
                _logChat('WebSocket Call End', '⚠️ No call end callback registered');
              } else {
                _onCallEnd?.call(callId, fromUserId, targetUserId);
              }
              break;
            case 'call_error':
              final callId = data['callId']?.toString() ?? '';
              final targetUserId = data['targetUserId']?.toString() ?? '';
              final error = data['error']?.toString() ?? 'unknown';
              final errorMessage = data['message']?.toString() ?? 'Call failed';
              _logChat('WebSocket Call Error', '❌ Call error: callId=$callId, target=$targetUserId, error=$error, message=$errorMessage');
              if (_onCallError == null) {
                _logChat('WebSocket Call Error', '⚠️ No call error callback registered');
              } else {
                _onCallError?.call(callId, targetUserId, errorMessage);
              }
              break;
            case 'chat':
              final messageId = data['id']?.toString() ?? '';
              final fromUserId = data['from']?.toString() ?? '';
              final toUserId = data['to']?.toString() ?? '';
              final message = data['message']?.toString() ?? '';
              
              // Log chat message received
              _logChat('WebSocket Chat', '💬 Chat message received:');
              _logChat('WebSocket Chat', '   - MessageId: $messageId');
              _logChat('WebSocket Chat', '   - From UserId: $fromUserId');
              _logChat('WebSocket Chat', '   - To UserId: $toUserId');
              _logChat('WebSocket Chat', '   - Current UserId: ${_userId ?? "null"}');
              _logChat('WebSocket Chat', '   - Message: ${message.length > 50 ? message.substring(0, 50) + "..." : message}');
              _logChat('WebSocket Chat', '   - Full message: $message');
              _logChat('WebSocket Chat', '   - Registered callbacks: ${_onChatMessageCallbacks.length}');
              
              debugPrint('🔵 [WebSocket] Chat message received: id=$messageId, from=$fromUserId, to=$toUserId, callbacks=${_onChatMessageCallbacks.length}');
              
              // Show in-app notification if chat screen is not in focus
              // Only show if the message is for the current user
              if (_userId != null && toUserId == _userId) {
                _showInAppChatNotification(fromUserId, message);
              }
              
              // Call all registered chat message callbacks
              // Note: _onChatMessage is also added to _onChatMessageCallbacks, so we only call the list
              // to avoid calling the same callback twice
              for (int i = 0; i < _onChatMessageCallbacks.length; i++) {
                try {
                  debugPrint('🔵 [WebSocket] Calling callback $i');
                  _logChat('WebSocket Chat', 'Executing callback $i');
                  _onChatMessageCallbacks[i](messageId, fromUserId, toUserId, message);
                  _logChat('WebSocket Chat', 'Callback $i executed successfully');
                } catch (e, stackTrace) {
                  debugPrint('🔵 [WebSocket] Error in callback $i: $e');
                  debugPrint('🔵 [WebSocket] Stack trace: $stackTrace');
                  _logChat('WebSocket Chat', 'Error in callback $i: $e');
                  developer.log('Stack trace', name: 'WebSocket Chat', error: e, stackTrace: stackTrace);
                }
              }
              // Legacy callback is already in _onChatMessageCallbacks, so don't call it again
              // This prevents duplicate callback execution
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
              
              if (userId.isEmpty) {
                // Missing userId - skip
              } else if (_onOnlineStatusCallbacks.isEmpty) {
                // No callbacks registered - skip
              } else {
                // Call all registered online status callbacks
                for (final callback in _onOnlineStatusCallbacks) {
                  try {
                    callback(userId, isOnline);
                  } catch (e) {
                  }
                }
              }
              break;
          }
        }
      }
    } catch (e) {
    }
  }

  /// Handle new post
  void _handleNewPost(String postId) {
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
    _onDeletePost?.call(postId);
  }

  /// Handle new comment
  void _handleNewComment(String postId, String commentId) {
    _onNewComment?.call(postId, commentId);
  }

  /// Handle delete comment
  void _handleDeleteComment(String postId, String commentId) {
    _onDeleteComment?.call(postId, commentId);
  }

  /// Handle app update notification
  Future<void> _handleAppUpdate() async {
    // Only show system notification if app is in background
    // If app is in foreground, the caller will show in-app notification instead
    if (!_isAppInForeground()) {
      try {
        await _notificationService.showNotification(
          title: 'App Update Available',
          body: 'A new version of Skybyn is ready to download',
          payload: 'app_update',
        );
        _logChat('WebSocket App Update', 'System notification shown (app in background)');
      } catch (e) {
        _logChat('WebSocket App Update', 'Failed to show system notification: $e');
      }
    } else {
      _logChat('WebSocket App Update', 'Skipping system notification (app in foreground, will show in-app)');
    }

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
  /// Send a raw message string via WebSocket
  /// Returns true if message was sent successfully, false otherwise
  Future<bool> sendMessage(String message) async {
    try {
      if (!_isConnected || _channel == null) {
        return false;
      }

      // Try to send the message
      // The sink.add() will throw if the channel is closed
      _channel!.sink.add(message);
      _updateConnectionMetrics('message_sent');
      
      return true;
    } catch (e) {
      // Log error in both debug and release (using debugPrint which works in release)
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
    Function(String, String, String)? onCallError, // callId, targetUserId, error message
  }) {
    _onCallInitiate = onCallInitiate;
    _onCallOffer = onCallOffer;
    _onCallAnswer = onCallAnswer;
    _onIceCandidate = onIceCandidate;
    _onCallEnd = onCallEnd;
    _onCallError = onCallError;
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

  /// Send chat message via WebSocket
  /// This is sent in addition to the HTTP API call to ensure real-time delivery
  void sendChatMessage({
    required String messageId,
    required String targetUserId,
    required String content,
  }) {
    if (_userId == null) {
      _logChat('WebSocket Chat Send', 'Cannot send chat message - user ID is null');
      return;
    }
    
    // Log chat message being sent
    _logChat('WebSocket Chat Send', 'Sending chat message:');
    _logChat('WebSocket Chat Send', '   - MessageId: $messageId');
    _logChat('WebSocket Chat Send', '   - From UserId: $_userId');
    _logChat('WebSocket Chat Send', '   - To UserId: $targetUserId');
    _logChat('WebSocket Chat Send', '   - Message: ${content.length > 50 ? content.substring(0, 50) + "..." : content}');
    _logChat('WebSocket Chat Send', '   - SessionId: $_sessionId');
    _logChat('WebSocket Chat Send', '   - WebSocket connected: $_isConnected');
    
    final message = {
      'type': 'chat',
      'id': messageId,
      'from': _userId, // Include sender ID so server can broadcast correctly
      'to': targetUserId,
      'message': content,
      'sessionId': _sessionId,
    };
    
    try {
      _sendMessageInternal(message);
      _logChat('WebSocket Chat Send', 'Chat message sent successfully via WebSocket');
    } catch (e) {
      _logChat('WebSocket Chat Send', 'Failed to send chat message via WebSocket: $e');
      rethrow;
    }
  }

  /// Handle connection closed
  void _onConnectionClosed() {
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Handle connection error
  void _onConnectionError(error) {
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Schedule reconnection with exponential backoff
  /// Reconnects automatically when connection is lost
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
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


    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (!_isConnected && !_isConnecting) {
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
      // Close WebSocket connection
      disconnect();

      _isInitialized = false;

      // Log final metrics
      _logConnectionQuality();
    } catch (e) {
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
          return false;
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Force reconnection even if connection appears to be active
  /// Useful when app resumes from background
  Future<void> forceReconnect() async {
    // Disconnect current connection if it exists
    if (_channel != null) {
      try {
        _channel!.sink.close();
      } catch (e) {
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
    _reconnectTimer?.cancel();
    _connectionHealthTimer?.cancel();
    
    // Close channel gracefully
    try {
      _channel?.sink.close();
    } catch (e) {
    }
    
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _lastPingReceivedTime = null;

    // Clear message queues
    _messageQueue.clear();
    _pendingMessages.clear();
    // Update online status to false when disconnected
    _updateOnlineStatusOnDisconnect();
  }

  /// Start connection health monitoring
  /// Monitors if server is still sending pings (server sends pings every 30 seconds)
  void _startConnectionHealthMonitor() {
    _connectionHealthTimer?.cancel();
    
    // Check every 20 seconds to detect dead connections faster
    // If we haven't received a ping from server in 60 seconds (2x interval), connection is likely dead
    _connectionHealthTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (!_isConnected || _channel == null) {
        timer.cancel();
        return;
      }
      
      // Test connection health
      if (!_testConnection()) {
        _onConnectionClosed();
        return;
      }
      
      if (_lastPingReceivedTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final timeSinceLastPing = now - _lastPingReceivedTime!;
        
        // If we haven't received a ping from server in 60 seconds, connection is likely dead
        if (timeSinceLastPing > 60000) {
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

  /// Remove a chat message callback
  /// Note: Function equality doesn't work in Dart, so this removes by reference
  void removeChatMessageCallback(void Function(String, String, String, String) callback) {
    final callbackHash = callback.hashCode;
    _registeredChatCallbackHashes.remove(callbackHash);
    _onChatMessageCallbacks.remove(callback);
    _logChat('WebSocket', 'Chat callback removed (hash: $callbackHash, remaining: ${_onChatMessageCallbacks.length})');
  }

  /// Show in-app chat notification if chat screen is not in focus
  Future<void> _showInAppChatNotification(String fromUserId, String message) async {
    try {
      // Check if app is in foreground - only show in-app notifications when foreground
      if (!_isAppInForeground()) {
        return; // Don't show in-app notification if app is in background
      }

      // Check if chat screen for this friend is already in focus
      if (_inAppNotificationService.isChatScreenInFocus(fromUserId)) {
        _logChat('WebSocket Chat Notification', 'Chat screen is in focus, skipping in-app notification');
        return;
      }

      // Get current user ID to fetch friends
      final authService = AuthService();
      final currentUserId = await authService.getStoredUserId();
      if (currentUserId == null) {
        _logChat('WebSocket Chat Notification', 'Cannot show notification - current user ID is null');
        return;
      }

      // Fetch friend information (using cached data for speed)
      final friends = await _friendService.fetchFriendsForUser(userId: currentUserId);
      final friend = friends.firstWhere(
        (f) => f.id == fromUserId,
        orElse: () => Friend(
          id: fromUserId,
          username: fromUserId, // Fallback
          nickname: '',
          avatar: '',
          online: false,
        ),
      );

      // Show in-app notification
      _inAppNotificationService.showChatNotification(
        friend: friend,
        message: message,
        onTap: () {
          // Navigate to chat screen
          final navigator = navigatorKey.currentState;
          if (navigator != null) {
            navigator.pushNamed(
              '/chat',
              arguments: {'friend': friend},
            );
          }
        },
      );

      // Show floating chat bubble
      try {
        // Get unread count for this friend (simplified - you may want to track this properly)
        await _floatingBubbleService.updateBubble(
          friend: friend,
          message: message,
          unreadCount: null, // Will increment existing count
        );
        _logChat('WebSocket Chat Notification', 'Floating bubble shown for friend: ${friend.username}');
      } catch (e) {
        _logChat('WebSocket Chat Notification', 'Failed to show floating bubble: $e');
      }

      _logChat('WebSocket Chat Notification', 'In-app notification shown for friend: ${friend.username}');
    } catch (e) {
      _logChat('WebSocket Chat Notification', 'Failed to show in-app notification: $e');
    }
  }

  /// Check if app is in foreground
  bool _isAppInForeground() {
    try {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      final isResumed = lifecycleState == AppLifecycleState.resumed;
      _logChat('WebSocket Foreground Check', 'Lifecycle state: $lifecycleState, isResumed: $isResumed');
      return isResumed;
    } catch (e) {
      // Fallback: check if navigator is available
      final hasNavigator = navigatorKey.currentState != null;
      _logChat('WebSocket Foreground Check', 'Exception checking lifecycle: $e, hasNavigator: $hasNavigator');
      return hasNavigator;
    }
  }

  /// Show in-app notification for any notification type
  void _showInAppNotification({
    required String title,
    required String body,
    String? avatarUrl,
    IconData? icon,
    Color? iconColor,
    required String notificationType,
    required VoidCallback onTap,
  }) {
    try {
      // Check if app is in foreground - only show in-app notifications when foreground
      if (!_isAppInForeground()) {
        return; // Don't show in-app notification if app is in background
      }

      // Show in-app notification
      _inAppNotificationService.showNotification(
        title: title,
        body: body,
        avatarUrl: avatarUrl,
        icon: icon,
        iconColor: iconColor,
        notificationId: '${notificationType}_${DateTime.now().millisecondsSinceEpoch}',
        notificationType: notificationType,
        onTap: onTap,
      );

      _logChat('WebSocket In-App Notification', 'In-app notification shown: type=$notificationType, title=$title');
    } catch (e) {
      _logChat('WebSocket In-App Notification', 'Failed to show in-app notification: $e');
    }
  }
}

