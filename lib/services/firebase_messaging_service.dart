import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'notification_service.dart';
import 'auth_service.dart';
import 'device_service.dart';

// Handle background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Check if Firebase is already initialized
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  print('Handling a background message: ${message.messageId}');

  // Show local notification for background messages
  final notificationService = NotificationService();
  await notificationService.showNotification(title: message.notification?.title ?? 'New Message', body: message.notification?.body ?? '', payload: jsonEncode(message.data));
}

class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final AuthService _authService = AuthService();
  SharedPreferences? _prefs;

  String? _fcmToken;

  // Callback for update check trigger
  static VoidCallback? _onUpdateCheckRequested;
  bool _isInitialized = false;

  // Topic subscriptions
  final List<String> _subscribedTopics = [];

  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> initialize() async {
    try {
      print('🔄 [Firebase] Initializing Firebase Messaging...');

      // Set background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Configure foreground notification presentation for iOS
      if (Platform.isIOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true, // Show alert banner
          badge: true, // Show badge
          sound: true, // Play sound
        );
        print('✅ [Firebase] iOS foreground notification presentation configured');
      }

      // Request permissions
      await _requestPermissions();

      // Get FCM token
      await _getFCMToken();

      // Set up message handlers
      await _setupMessageHandlers();

      // Auto-subscribe to default topics
      await autoSubscribeToTopics();

      _isInitialized = true;
      print('✅ [Firebase] Firebase Messaging initialized successfully');
    } catch (e) {
      print('❌ [Firebase] Error initializing Firebase Messaging: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(alert: true, announcement: false, badge: true, carPlay: false, criticalAlert: false, provisional: false, sound: true);

      print('🔔 [Firebase] User granted permission: ${settings.authorizationStatus}');
    } catch (e) {
      print('❌ [Firebase] Error requesting permissions: $e');
    }
  }

  Future<void> _getFCMToken() async {
    try {
      _fcmToken = await _messaging.getToken();
      print('🔑 [Firebase] FCM Token: ${_fcmToken?.substring(0, 20)}...');
      print('🔑 [Firebase] FULL FCM Token: $_fcmToken');

      // Store token locally (not in Firestore)
      await _storeFCMTokenLocally();
    } catch (e) {
      print('❌ [Firebase] Error getting FCM token: $e');
    }
  }

  /// Send FCM token to server to register in devices table
  Future<void> sendFCMTokenToServer() async {
    try {
      if (_fcmToken == null) {
        print('⚠️ [Firebase] No FCM token to send');
        return;
      }

      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        print('⚠️ [Firebase] No user logged in, cannot send FCM token to server');
        return;
      }

      print('📤 [Firebase] Sending FCM token to server...');

      // Use device service to get device info
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();
      deviceInfo['fcmToken'] = _fcmToken;
      deviceInfo['userID'] = user.id;

      // Send to a device update endpoint or via login update
      try {
        final response = await http.post(Uri.parse('https://api.skybyn.no/api/register_device_token.php'), body: {'userID': user.id, 'deviceInfo': json.encode(deviceInfo)});

        if (response.statusCode == 200) {
          print('✅ [Firebase] FCM token sent to server successfully');
        } else {
          print('⚠️ [Firebase] Failed to send FCM token to server: ${response.statusCode}');
        }
      } catch (e) {
        // Silently fail - device will be updated on next login
        print('⚠️ [Firebase] Could not send FCM token to server: $e');
      }
    } catch (e) {
      print('❌ [Firebase] Error sending FCM token to server: $e');
    }
  }

  Future<void> _setupMessageHandlers() async {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 [Firebase] Got a message whilst in the foreground!');
      print('📨 [Firebase] Message data: ${message.data}');

      if (message.notification != null) {
        print('📨 [Firebase] Message also contained a notification: ${message.notification}');
        print('📨 [Firebase] FCM will handle the notification display automatically');

        // Don't show local notification - let FCM handle it
        // This will show as a system notification banner on iOS
      }
    });

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 [Firebase] App opened from notification');
      print('📱 [Firebase] Message data: ${message.data}');

      // Handle navigation based on message data
      _handleNotificationTap(message.data);
    });

    // Check if app was opened from notification
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      print('📱 [Firebase] App opened from initial notification');
      _handleNotificationTap(initialMessage.data);
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    try {
      final type = data['type']?.toString();
      final payload = data['payload']?.toString();

      print('🎯 [Firebase] Handling notification tap - Type: $type, Payload: $payload');

      switch (type) {
        case 'new_post':
          // Navigate to post details
          print('🎯 [Firebase] Navigate to post: $payload');
          break;
        case 'new_comment':
          // Navigate to comment
          print('🎯 [Firebase] Navigate to comment: $payload');
          break;
        case 'broadcast':
          // Show broadcast message
          print('🎯 [Firebase] Show broadcast: $payload');
          break;
        case 'app_update':
          // Trigger update check - the home screen will handle showing the dialog
          print('🎯 [Firebase] App update notification received - triggering update check');
          _triggerUpdateCheck();
          break;
        default:
          print('🎯 [Firebase] Unknown notification type: $type');
      }
    } catch (e) {
      print('❌ [Firebase] Error handling notification tap: $e');
    }
  }

  Future<void> _storeFCMTokenLocally() async {
    try {
      if (_fcmToken == null) return;

      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        print('⚠️ [Firebase] No user logged in, skipping token storage');
        return;
      }

      // Store token locally using SharedPreferences
      await _initPrefs();
      await _prefs?.setString('fcm_token', _fcmToken!);

      print('✅ [Firebase] FCM token stored locally');
    } catch (e) {
      print('❌ [Firebase] Error storing FCM token locally: $e');
    }
  }

  Future<String?> getStoredFCMToken() async {
    try {
      await _initPrefs();
      return _prefs?.getString('fcm_token');
    } catch (e) {
      print('❌ [Firebase] Error getting stored FCM token: $e');
      return null;
    }
  }

  Future<void> deleteFCMToken() async {
    try {
      await _initPrefs();
      await _prefs?.remove('fcm_token');
      _fcmToken = null;
      print('✅ [Firebase] FCM token deleted');
    } catch (e) {
      print('❌ [Firebase] Error deleting FCM token: $e');
    }
  }

  /// Set callback for update check requests
  static void setUpdateCheckCallback(VoidCallback? callback) {
    _onUpdateCheckRequested = callback;
  }

  /// Trigger update check from notification
  void _triggerUpdateCheck() {
    if (_onUpdateCheckRequested != null) {
      print('🎯 [Firebase] Triggering update check callback');
      _onUpdateCheckRequested!();
    } else {
      print('⚠️ [Firebase] No update check callback set');
    }
  }

  /// Subscribe to a topic
  Future<bool> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      if (!_subscribedTopics.contains(topic)) {
        _subscribedTopics.add(topic);
      }
      print('✅ [Firebase] Subscribed to topic: $topic');
      return true;
    } catch (e) {
      print('❌ [Firebase] Error subscribing to topic $topic: $e');
      return false;
    }
  }

  /// Unsubscribe from a topic
  Future<bool> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      _subscribedTopics.remove(topic);
      print('✅ [Firebase] Unsubscribed from topic: $topic');
      return true;
    } catch (e) {
      print('❌ [Firebase] Error unsubscribing from topic $topic: $e');
      return false;
    }
  }

  /// Auto-subscribe to default topics on app launch/login
  Future<void> autoSubscribeToTopics() async {
    try {
      print('🔄 [Firebase] Auto-subscribing to default topics...');

      // Default topics for all users
      final defaultTopics = [
        'all', // All users
        'app_updates', // App update notifications
        'general', // General announcements
      ];

      for (final topic in defaultTopics) {
        await subscribeToTopic(topic);
        // Small delay to avoid overwhelming the service
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('✅ [Firebase] Auto-subscription to default topics completed');
    } catch (e) {
      print('❌ [Firebase] Error in auto-subscription: $e');
    }
  }

  /// Try to register FCM token after login
  Future<void> tryRegisterFCMTokenAfterLogin() async {
    // Deprecated: FCM token is now sent via profile API
    // Kept for backward compatibility
    print('ℹ️ [Firebase] FCM token registration handled via profile API');
  }

  /// Subscribe to user-specific topics based on user data
  Future<void> subscribeToUserTopics() async {
    try {
      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        print('⚠️ [Firebase] No user logged in, skipping user-specific topics');
        return;
      }

      print('🔄 [Firebase] Subscribing to user-specific topics...');

      // User-specific topics
      final userTopics = [
        'user_${user.id}', // User-specific notifications
        'rank_${user.rank}', // Rank-based notifications
        'status_${user.online}', // Online status notifications
      ];

      for (final topic in userTopics) {
        await subscribeToTopic(topic);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('✅ [Firebase] User-specific topic subscription completed');
    } catch (e) {
      print('❌ [Firebase] Error subscribing to user topics: $e');
    }
  }

  /// Get list of subscribed topics
  List<String> get subscribedTopics => List.from(_subscribedTopics);

  /// Check if subscribed to a specific topic
  bool isSubscribedToTopic(String topic) => _subscribedTopics.contains(topic);

  /// Auto-register FCM token when app opens (called from main.dart)
  Future<void> autoRegisterTokenOnAppOpen() async {
    // Deprecated: FCM token is now sent via profile API
    // Kept for backward compatibility
    print('ℹ️ [Firebase] FCM token registration handled via profile API');
  }
}
