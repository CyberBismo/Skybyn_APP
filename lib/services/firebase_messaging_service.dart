import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../main.dart'; // for navigatorKey
import '../models/friend.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'friend_service.dart';
import 'in_app_notification_service.dart';
import 'message_sync_worker.dart';
import 'chat_message_count_service.dart';
import 'notification_service.dart';
// Note: WebSocketService is intentionally NOT imported here to strictly separate concerns.
// FCM logic should handle FCM messages completely independently of WebSocket status.
// We assume the backend handles logic regarding whether to send a push notification or not 
// based on user's online status, or that duplicate handling is managed at the UI layer.

// -----------------------------------------------------------------------------
// Top-Level Background Handler
// -----------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (e) {
    // Ignore - might be already initialized or unavailable
  }

  // Initialize Notification Service to ensure channels are ready in background isolate
  try {
    await NotificationService().initialize();
  } catch (e) {
    developer.log('⚠️ Failed to initialize NotificationService in background: $e', name: 'FCM');
  }

  developer.log('📨 Background Message: ${message.messageId} (Type: ${message.data['type']})', name: 'FCM');

  // Terminated/Background State:
  // If the message has a 'notification' payload, the OS (System Tray) handles it automatically.
  // We ONLY need to manually show a notification if:
  // 1. It is a Data-Only message (no notification payload).
  // 2. It is a 'Call' type (needs specific handling).

  final type = message.data['type']?.toString();
  final hasNotificationPayload = message.notification != null;

  if (type == 'call') {
    // Show Incoming Call Notification (Full Screen Intent / High Priority)
    await NotificationService().showNotification(
      title: message.notification?.title ?? 'Incoming Call',
      body: message.notification?.body ?? 'Tap to answer',
      payload: jsonEncode(message.data),
    );
  } else if (type == 'app_update') {
    // Handle App Update (Background Download)
    developer.log('🚀 FCM: Received App Update Signal', name: 'FCM');
    MessageSyncWorker.scheduleUpdateDownload();
  } else if (type == 'chat') {
      // Explicitly handle Chat messages to ensuring they "wake up" the device
      if (!hasNotificationPayload) {
        var senderName = message.data['senderName'] ?? message.data['username'] ?? 'Friend';
        final msgBody = message.data['body'] ?? message.data['message'] ?? 'Sent a message';
        var avatarUrl = message.data['avatar'] ?? message.data['userAvatar']; // Adjust key based on payload

        // Try to get cached info to match App UI and use cached images
        try {
           final authService = AuthService();
           final userId = await authService.getStoredUserId();
           final senderId = message.data['sender']?.toString() ?? message.data['senderId']?.toString();
           
           if (userId != null && senderId != null) {
              final friendService = FriendService();
              // This returns cached data immediately if available
              final friends = await friendService.fetchFriendsForUser(userId: userId);
              
              // Find friend in cache
              final friend = friends.firstWhere(
                  (f) => f.id == senderId, 
                  orElse: () => Friend(id: '0', username: '', nickname: '', avatar: '', online: false)
              );
              
              if (friend.id != '0') {
                  // Use cached name (Nickname > Username)
                  if (friend.nickname.isNotEmpty) {
                    senderName = friend.nickname;
                  } else if (friend.username.isNotEmpty) {
                    senderName = friend.username;
                  }
                  
                  // Use cached avatar URL (matches main app cache keys)
                  if (friend.avatar.isNotEmpty) {
                      avatarUrl = UrlHelper.convertUrl(friend.avatar);
                  }
              }
           }
        } catch (e) {
           // Ignore cache lookup errors, stick to payload data
           developer.log('Failed to load cached friend data: $e', name: 'FCM');
        }

        final senderId = message.data['sender']?.toString() ?? message.data['senderId']?.toString() ?? '0';
        final notificationId = int.tryParse(senderId) ?? senderId.hashCode;
        
        await NotificationService().showNotification(
          title: '$senderName sent a message',
          body: msgBody,
          payload: jsonEncode(message.data),
          largeIconUrl: avatarUrl,
          notificationId: notificationId,
        );
      }
  } else if (type == 'friend_request') {
      // Handle Friend Request messages (Data-Only to support Action Buttons)
      if (!hasNotificationPayload) {
        final senderName = message.data['senderName'] ?? message.data['username'] ?? message.data['title'] ?? 'Friend';
        // 'body' might be in data payload from our server logic
        final msgBody = message.data['body'] ?? 'sent you a friend request.';
        
        await NotificationService().showNotification(
          title: senderName,
          body: msgBody,
          payload: jsonEncode(message.data),
        );
      }
  } else if (!hasNotificationPayload) {
    // Data-only message: We MUST show a local notification manually
    final title = message.data['title']?.toString();
    final body = message.data['body']?.toString() ?? message.data['message']?.toString();
    
    // If both title and body are missing, do not show a notification
    // This allows for "silent" data-only messages used for background sync
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      developer.log('🔇 Skipping empty data-only notification', name: 'FCM');
      return;
    }

    await NotificationService().showNotification(
      title: title ?? 'Skybyn',
      body: body ?? 'New update received',
      payload: jsonEncode(message.data),
    );
  }
}

// -----------------------------------------------------------------------------
// Service Class
// -----------------------------------------------------------------------------
class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final AuthService _authService = AuthService();
  bool _isInitialized = false;

  // Static Callbacks
  static Function(String callId, String fromUserId, String callType)? onIncomingCallFromNotification;
  static Function()? _onUpdateCheck;

  // Internal State
  String? _currentToken;
  final Set<String> _subscribedTopics = {};

  // Getters
  bool get isInitialized => _isInitialized;
  String? get fcmToken => _currentToken;
  List<String> get subscribedTopics => _subscribedTopics.toList();

  // Static Methods
  static void setUpdateCheckCallback(Function() callback) {
    _onUpdateCheck = callback;
  }

  static void triggerUpdateCheck() {
    _onUpdateCheck?.call();
  }

  // ---------------------------------------------------------------------------
  // Public Interface
  // ---------------------------------------------------------------------------

  /// Initialize FCM: Listeners, Permissions (if allowed), and Initial Token Sync
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Register Background Handler first
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 2. Setup Foreground Handlers
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // 3. Check for Initial Message (Dead App -> Open via Notification)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // 4. iOS Foreground Options
      if (Platform.isIOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      
      // 5. Sync Token (Silent - don't force perms request yet)
      syncToken();

      // 6. Listen for Token Refreshes
      _messaging.onTokenRefresh.listen((newToken) {
        developer.log('🔄 FCM Token Refreshed', name: 'FCM');
        _currentToken = newToken;
        syncToken(force: true);
      });

      _isInitialized = true;
      developer.log('✅ FCM Service Initialized', name: 'FCM');
    } catch (e) {
      developer.log('❌ FCM Initialization Failed: $e', name: 'FCM');
    }
  }

  /// Explicitly request permissions (Call after Login)
  Future<void> requestPermissions() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      developer.log('User granted permission: ${settings.authorizationStatus}', name: 'FCM');
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        syncToken(force: true);
      }
    } catch (e) {
      developer.log('Permission Request Error: $e', name: 'FCM');
    }
  }

  /// Subscribe to user-specific topics
  Future<void> subscribeToUserTopics() async {
    try {
      final user = await _authService.getStoredUserProfile();
      if (user != null && user.id.isNotEmpty) {
        final userTopic = 'user_${user.id}';
        await _messaging.subscribeToTopic(userTopic);
        _subscribedTopics.add(userTopic);
        
        if (user.rank.isNotEmpty) {
           final rankTopic = 'rank_${user.rank}';
           await _messaging.subscribeToTopic(rankTopic);
           _subscribedTopics.add(rankTopic);
        }
        developer.log('✅ Subscribed to topics: $_subscribedTopics', name: 'FCM');
      }
    } catch (e) {
      developer.log('❌ Failed to subscribe to user topics: $e', name: 'FCM');
    }
  }

  /// Unsubscribe from a specific topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      _subscribedTopics.remove(topic);
    } catch (e) {
      developer.log('❌ Failed to unsubscribe from $topic: $e', name: 'FCM');
    }
  }

  /// Unified Token Sync: Handles Get, Store, and Send to Server
  /// Replaces: sendFCMTokenToServer, autoRegister, checkDevice
  Future<void> syncToken({bool force = false}) async {
    try {
      // 1. Get FCM Token
      String? token = await _messaging.getToken();
      _currentToken = token; // Cache the token
      if (token == null) {
        developer.log('⚠️ FCM Token is NULL', name: 'FCM');
        return;
      }

      // 2. Get User ID (0 if guest)
      final user = await _authService.getStoredUserProfile();
      final userId = (user != null && user.id.isNotEmpty) ? user.id : "0";

      // 3. Get Device Info
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();
      final deviceId = deviceInfo['id'] ?? deviceInfo['deviceId'] ?? 'unknown_device';

      // 4. Check if we need to update Server
      // We update if: Force=True, or Token Changed, or User Changed, or App Updated
      final prefs = await SharedPreferences.getInstance();
      final lastToken = prefs.getString('fcm_token');
      final lastUser = prefs.getString('fcm_user');
      final lastVersion = prefs.getString('fcm_version');
      
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.buildNumber;

      bool needsUpdate = force || 
                         (token != lastToken) || 
                         (userId != lastUser) || 
                         (currentVersion != lastVersion);

      if (!needsUpdate) {
        developer.log('✅ Token Sync: Up to date (User: $userId)', name: 'FCM');
        return;
      }

      // 5. Send to Server
      developer.log('🚀 Syncing Token to Server (User: $userId)...', name: 'FCM');
      final response = await http.post(
        Uri.parse(ApiConstants.token), // Ensure this endpoint handles upsert
        body: {
          'userID': userId,
          'fcmToken': token,
          'deviceId': deviceId,
          'platform': Platform.operatingSystem,
          'model': deviceInfo['model'] ?? 'Unknown'
        }
      );

      if (response.statusCode == 200) {
        // 6. Update Local Cache
        await prefs.setString('fcm_token', token);
        await prefs.setString('fcm_user', userId);
        await prefs.setString('fcm_version', currentVersion);
        developer.log('✅ Token Synced Successfully', name: 'FCM');
      } else {
        developer.log('❌ Token Sync Failed: ${response.statusCode}', name: 'FCM');
      }

    } catch (e) {
      developer.log('❌ Token Sync Error: $e', name: 'FCM');
    }
  }

  // ---------------------------------------------------------------------------
  // Internal Handlers
  // ---------------------------------------------------------------------------

  void _handleForegroundMessage(RemoteMessage message) {
    final type = message.data['type']?.toString();

    developer.log('📨 Foreground Message: Type=$type', name: 'FCM');

    // ROUTING LOGIC:
    // We treat every FCM message as a valid notification request.
    // Logic to avoid duplicates (FCM vs WebSocket) is assumed to be handled by backend
    // (backend should not send FCM if user is connected via WS) or UI layer.

    // Show Notification
    // We prefer InAppNotificationService for Foreground to look nice,
    // but NotificationService (System Tray) is safer if InApp fails.
    
    if (type == 'chat' && (message.notification == null)) {
       // Extract user info safely
       final senderName = message.data['senderName'] ?? message.data['username'] ?? 'Friend';
       final avatarUrl = message.data['avatar'] ?? message.data['userAvatar']; // Adjust key based on payload

       final senderId = message.data['sender']?.toString() ?? '0';
       
       // Suppress notification if chat screen is already open for this friend
       if (ChatMessageCountService().isChatOpenForFriend(senderId)) {
         developer.log('🚫 Suppressing notification - Chat open for $senderId', name: 'FCM');
         return;
       }

       // Show System Notification (Tray) instead of In-App Overlay
       // Use consistent ID based on senderId to allow updating/cancelling
       final notificationId = int.tryParse(senderId) ?? senderId.hashCode;
       
       NotificationService().showNotification(
          title: '$senderName sent a message',
          body: message.data['message'] ?? 'Sent a message',
          payload: jsonEncode(message.data),
          largeIconUrl: avatarUrl,
          notificationId: notificationId,
       );
    } else if (type == 'app_update') {
       // Handle App Update (Background Download)
       developer.log('🚀 FCM: Received App Update Signal (Foreground)', name: 'FCM');
       MessageSyncWorker.scheduleUpdateDownload();
    } else {
      // Generic System Notification as fallback
      final title = message.notification?.title ?? message.data['title']?.toString();
      final body = message.notification?.body ?? message.data['body']?.toString() ?? message.data['message']?.toString();

      // If both title and body are missing, do not show a notification
      if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
        developer.log('🔇 Skipping empty foreground notification', name: 'FCM');
        return;
      }

      NotificationService().showNotification(
        title: title ?? 'Skybyn',
        body: body ?? 'New message received',
        payload: jsonEncode(message.data),
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    developer.log('📱 App Opened via Notification', name: 'FCM');
    _handleNavigation(message.data);
  }

  void _handleNavigation(Map<String, dynamic> data) {
    final type = data['type'];
    final nav = navigatorKey.currentState;
    
    if (nav == null) return;

    switch (type) {
      case 'chat':
        // Simplest navigation - just go to home/chat list if specific friend logic is complex
        // Ideally: Fetch friend and push chat screen
        nav.pushNamed('/home'); 
        break;
      case 'call':
        final callId = data['callId']?.toString();
        final fromUserId = data['fromUserId']?.toString();
        final callType = data['callType']?.toString() ?? 'video';
        if (callId != null && fromUserId != null) {
          onIncomingCallFromNotification?.call(callId, fromUserId, callType);
        }
        break;
      case 'broadcast':
      case 'admin':
        // Maybe show a dialog?
        break;
      default:
        nav.pushNamed('/home');
    }
  }
  
  // Backward compatibility alias for legacy code
  Future<void> sendFCMTokenToServer({bool force = false}) async => syncToken(force: force);
  Future<void> autoRegisterTokenOnAppOpen() async => syncToken();
}
