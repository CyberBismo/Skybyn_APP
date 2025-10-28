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
  try {
    // Check if Firebase is already initialized
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    // Show local notification for background messages
    final notificationService = NotificationService();
    await notificationService.showNotification(title: message.notification?.title ?? 'New Message', body: message.notification?.body ?? '', payload: jsonEncode(message.data));
  } catch (e) {
    print('❌ [FCM] Error in background handler: $e');
  }
}

class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  FirebaseMessaging? _messaging;
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
      print('🔄 [FCM] Initializing Firebase Messaging service...');
      
      // Ensure Firebase Core is initialized first
      if (Firebase.apps.isEmpty) {
        print('❌ [FCM] Firebase Core is not initialized - cannot proceed');
        throw Exception('Firebase Core must be initialized before Firebase Messaging');
      }
      print('✅ [FCM] Firebase Core is initialized');
      
      // On iOS, check if APN is configured before proceeding
      if (Platform.isIOS) {
        try {
          // Attempt to get FirebaseMessaging instance - this will fail if APN not configured
          _messaging = FirebaseMessaging.instance;
          print('✅ [FCM] FirebaseMessaging instance obtained for iOS');
        } catch (e) {
          print('⚠️ [FCM] Cannot get FirebaseMessaging instance on iOS (APN not configured): $e');
          // Reset messaging instance and fail gracefully
          _messaging = null;
          _isInitialized = false;
          rethrow;
        }
      } else {
        // Android - initialize normally
        _messaging = FirebaseMessaging.instance;
        print('✅ [FCM] FirebaseMessaging instance obtained for Android');
      }

      // Set background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Configure foreground notification presentation for iOS
      // Note: This will fail if APN is not configured in Firebase
      if (Platform.isIOS && _messaging != null) {
        try {
          await _messaging!.setForegroundNotificationPresentationOptions(
            alert: true, // Show alert banner
            badge: true, // Show badge
            sound: true, // Play sound
          );
        } catch (e) {
          // APN might not be configured - skip iOS notification setup
          print('⚠️ [FCM] iOS notification setup failed (APN not configured): $e');
          throw e; // Re-throw to skip rest of initialization
        }
      }

      // Request permissions
      await _requestPermissions();

      // Get FCM token
      // This will fail on iOS if APN is not configured
      await _getFCMToken();

      // Set up message handlers
      await _setupMessageHandlers();

      // Auto-subscribe to default topics
      await autoSubscribeToTopics();

      _isInitialized = true;
    } catch (e) {
      if (Platform.isIOS) {
        print('⚠️ [FCM] iOS Firebase Messaging failed: $e');
        print('⚠️ [FCM] This is expected if APN is not configured in Firebase Console');
        print('⚠️ [FCM] App will continue using WebSocket for notifications');
      } else {
        print('❌ [FCM] Error initializing Firebase Messaging: $e');
      }
      // Reset messaging instance on failure
      _messaging = null;
      _isInitialized = false;
    }
  }

  Future<void> _requestPermissions() async {
    try {
      if (_messaging == null) {
        print('❌ [FCM] Cannot request permissions - Firebase Messaging not initialized');
        return;
      }
      
      final NotificationSettings settings = await _messaging!.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true
      );
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ [FCM] Permission granted');
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print('❌ [FCM] Permission denied by user');
      } else if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        print('⚠️ [FCM] Permission not yet determined');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ [FCM] Provisional permission granted');
      }
    } catch (e) {
      print('❌ [FCM] Error requesting permissions: $e');
    }
  }

  Future<void> _getFCMToken() async {
    try {
      if (_messaging == null) {
        print('❌ [FCM] Cannot get FCM token - Firebase Messaging not initialized');
        return;
      }
      
      _fcmToken = await _messaging!.getToken();
      print('✅ [FCM] Token retrieved successfully: ${_fcmToken?.substring(0, 20)}...');

      // Store token locally (not in Firestore)
      await _storeFCMTokenLocally();
    } catch (e) {
      print('❌ [FCM] Error getting FCM token: $e');
      _fcmToken = null;
    }
  }

  /// Send FCM token to server to register in devices table
  Future<void> sendFCMTokenToServer() async {
    try {
      if (_fcmToken == null) {
        print('❌ [FCM] Cannot send token - no FCM token available');
        return;
      }

      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        print('❌ [FCM] Cannot send token - no user logged in');
        return;
      }

      print('📤 [FCM] Sending FCM token to server for user: ${user.id}');

      // Use device service to get device info
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();
      deviceInfo['fcmToken'] = _fcmToken;
      deviceInfo['userID'] = user.id;

      // Send to a device update endpoint or via login update
      try {
        final response = await http.post(
          Uri.parse('https://api.skybyn.no/api/register_device_token.php'),
          body: {'userID': user.id, 'deviceInfo': json.encode(deviceInfo)}
        );

        if (response.statusCode == 200) {
          print('✅ [FCM] Token sent to server successfully');
        } else {
          print('❌ [FCM] Failed to send token - server returned status: ${response.statusCode}');
        }
      } catch (e) {
        print('❌ [FCM] Failed to send token to server: $e');
        // Silently fail - device will be updated on next login
      }
    } catch (e) {
      print('❌ [FCM] Error in sendFCMTokenToServer: $e');
    }
  }

  Future<void> _setupMessageHandlers() async {
    if (_messaging == null) {
      return;
    }
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Don't show local notification - let FCM handle it
      // This will show as a system notification banner on iOS
    });

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Handle navigation based on message data
      _handleNotificationTap(message.data);
    });

    // Check if app was opened from notification
    RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage.data);
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    try {
      final type = data['type']?.toString();
      final payload = data['payload']?.toString();

      switch (type) {
        case 'new_post':
          // Navigate to post details
          break;
        case 'new_comment':
          // Navigate to comment
          break;
        case 'broadcast':
          // Show broadcast message
          break;
        case 'app_update':
          // Trigger update check - the home screen will handle showing the dialog
          _triggerUpdateCheck();
          break;
        default:
          print('❌ [FCM] Unknown notification type: $type');
      }
    } catch (e) {
      print('❌ [FCM] Error handling notification tap: $e');
    }
  }

  Future<void> _storeFCMTokenLocally() async {
    try {
      if (_fcmToken == null) {
        print('⚠️ [FCM] Cannot store token - token is null');
        return;
      }

      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        print('⚠️ [FCM] Cannot store token - no user logged in yet');
        return;
      }

      // Store token locally using SharedPreferences
      await _initPrefs();
      await _prefs?.setString('fcm_token', _fcmToken!);
      print('✅ [FCM] Token stored locally for user: ${user.id}');
    } catch (e) {
      print('❌ [FCM] Error storing FCM token locally: $e');
    }
  }

  Future<String?> getStoredFCMToken() async {
    try {
      await _initPrefs();
      final token = _prefs?.getString('fcm_token');
      if (token != null) {
        print('✅ [FCM] Retrieved stored token');
      } else {
        print('⚠️ [FCM] No stored token found');
      }
      return token;
    } catch (e) {
      print('❌ [FCM] Error getting stored FCM token: $e');
      return null;
    }
  }

  Future<void> deleteFCMToken() async {
    try {
      await _initPrefs();
      await _prefs?.remove('fcm_token');
      _fcmToken = null;
      print('✅ [FCM] Token deleted from local storage');
    } catch (e) {
      print('❌ [FCM] Error deleting FCM token: $e');
    }
  }

  /// Set callback for update check requests
  static void setUpdateCheckCallback(VoidCallback? callback) {
    _onUpdateCheckRequested = callback;
  }

  /// Trigger update check from notification
  void _triggerUpdateCheck() {
    if (_onUpdateCheckRequested != null) {
      _onUpdateCheckRequested!();
    }
  }

  /// Subscribe to a topic
  Future<bool> subscribeToTopic(String topic) async {
    try {
      if (_messaging == null) {
        print('❌ [FCM] Cannot subscribe to topic - Firebase Messaging not initialized');
        return false;
      }
      
      await _messaging!.subscribeToTopic(topic);
      if (!_subscribedTopics.contains(topic)) {
        _subscribedTopics.add(topic);
      }
      print('✅ [FCM] Subscribed to topic: $topic');
      return true;
    } catch (e) {
      print('❌ [FCM] Error subscribing to topic $topic: $e');
      return false;
    }
  }

  /// Unsubscribe from a topic
  Future<bool> unsubscribeFromTopic(String topic) async {
    try {
      if (_messaging == null) {
        print('❌ [FCM] Cannot unsubscribe from topic - Firebase Messaging not initialized');
        return false;
      }
      
      await _messaging!.unsubscribeFromTopic(topic);
      _subscribedTopics.remove(topic);
      print('✅ [FCM] Unsubscribed from topic: $topic');
      return true;
    } catch (e) {
      print('❌ [FCM] Error unsubscribing from topic $topic: $e');
      return false;
    }
  }

  /// Auto-subscribe to default topics on app launch/login
  Future<void> autoSubscribeToTopics() async {
    try {
      // Default topics for all users
      final defaultTopics = [
        'all', // All users
        'app_updates', // App update notifications
        'general', // General announcements
      ];

      print('📋 [FCM] Auto-subscribing to ${defaultTopics.length} default topics');

      for (final topic in defaultTopics) {
        final success = await subscribeToTopic(topic);
        if (!success) {
          print('❌ [FCM] Failed to subscribe to topic: $topic');
        }
        // Small delay to avoid overwhelming the service
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('✅ [FCM] Auto-subscription to default topics completed');
    } catch (e) {
      print('❌ [FCM] Error in auto-subscription: $e');
    }
  }

  /// Try to register FCM token after login
  Future<void> tryRegisterFCMTokenAfterLogin() async {
    // Deprecated: FCM token is now sent via profile API
    // Kept for backward compatibility
  }

  /// Subscribe to user-specific topics based on user data
  Future<void> subscribeToUserTopics() async {
    try {
      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        print('❌ [FCM] Cannot subscribe to user topics - no user logged in');
        return;
      }

      // User-specific topics
      final userTopics = [
        'user_${user.id}', // User-specific notifications
        'rank_${user.rank}', // Rank-based notifications
        'status_${user.online}', // Online status notifications
      ];

      print('📋 [FCM] Subscribing to ${userTopics.length} user-specific topics for user: ${user.id}');

      for (final topic in userTopics) {
        final success = await subscribeToTopic(topic);
        if (!success) {
          print('❌ [FCM] Failed to subscribe to user topic: $topic');
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('✅ [FCM] User-specific topic subscription completed');
    } catch (e) {
      print('❌ [FCM] Error subscribing to user topics: $e');
    }
  }

  /// Get list of subscribed topics
  List<String> get subscribedTopics => List.from(_subscribedTopics);

  /// Check if subscribed to a specific topic
  bool isSubscribedToTopic(String topic) => _subscribedTopics.contains(topic);

  /// Auto-register FCM token when app opens (called from main.dart)
  Future<void> autoRegisterTokenOnAppOpen() async {
    print('🔍 [FCM] autoRegisterTokenOnAppOpen() called');
    try {
      // Ensure we have the latest FCM token
      await _getFCMToken();

      if (_fcmToken == null) {
        print('❌ [FCM] Cannot auto-register - FCM token unavailable');
        return;
      }

      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        print('❌ [FCM] Cannot auto-register token - user not logged in');
        return;
      }

      // Send the token to the token API endpoint
      final response = await http.post(
        Uri.parse('https://api.skybyn.no/token.php'),
        body: {'user_id': user.id, 'token': _fcmToken},
      );

      if (response.statusCode == 200) {
        print('✅ [FCM] Token auto-registered successfully via token API');
      } else {
        print('❌ [FCM] Auto-registration failed - Status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [FCM] Error auto-registering FCM token: $e');
    }
  }
}
