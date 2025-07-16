import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'auth_service.dart';

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
  await notificationService.showNotification(
    title: message.notification?.title ?? 'New Message',
    body: message.notification?.body ?? '',
    payload: jsonEncode(message.data),
  );
}

class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  SharedPreferences? _prefs;

  String? _fcmToken;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  Future<void> _initPrefs() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
  }

  Future<void> initialize() async {
    try {
      print('🔄 [Firebase] Initializing Firebase Messaging...');
      
      // Set background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      
      // Configure foreground notification presentation for iOS
      if (Platform.isIOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,    // Show alert banner
          badge: true,    // Show badge
          sound: true,    // Play sound
        );
        print('✅ [Firebase] iOS foreground notification presentation configured');
      }
      
      // Request permissions
      await _requestPermissions();
      
      // Get FCM token
      await _getFCMToken();
      
      // Set up message handlers
      await _setupMessageHandlers();
      
      _isInitialized = true;
      print('✅ [Firebase] Firebase Messaging initialized successfully');
    } catch (e) {
      print('❌ [Firebase] Error initializing Firebase Messaging: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      print('🔔 [Firebase] User granted permission: ${settings.authorizationStatus}');
    } catch (e) {
      print('❌ [Firebase] Error requesting permissions: $e');
    }
  }

  Future<void> _getFCMToken() async {
    try {
      _fcmToken = await _messaging.getToken();
      print('🔑 [Firebase] FCM Token: ${_fcmToken?.substring(0, 20)}...');
      
      // Store token locally (not in Firestore)
      await _storeFCMTokenLocally();
    } catch (e) {
      print('❌ [Firebase] Error getting FCM token: $e');
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
} 