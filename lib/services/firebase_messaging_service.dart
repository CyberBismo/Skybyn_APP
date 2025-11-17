import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'notification_service.dart';
import 'auth_service.dart';
import 'device_service.dart';
import '../config/constants.dart';
import 'background_activity_service.dart';
import 'call_service.dart';
import 'friend_service.dart';
import '../screens/call_screen.dart';
import '../models/friend.dart';
import '../main.dart' show navigatorKey;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

// Handle background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    print('📱 [FCM] Background message received: ${message.data}');
    
    // Process all messages, including in debug mode (for testing)
    // Debug mode check removed to ensure notifications work during development

    // Check if Firebase is already initialized
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    
    // Update user activity when receiving notification (user is active)
    // This helps maintain online status even when app is closed
    try {
      final authService = AuthService();
      await authService.updateActivity();
      print('✅ [FCM] Activity updated from background notification');
    } catch (e) {
      print('⚠️ [FCM] Failed to update activity from background: $e');
    }

    // Show local notification for background messages
    final notificationService = NotificationService();
    final type = message.data['type']?.toString();
    print('📱 [FCM] Background message type: $type');
    
    if (type == 'call') {
      print('📞 [FCM] Call notification received in background - showing notification with actions');
    }
    
    // For call notifications, include all call data in payload
    final payload = type == 'call' 
        ? jsonEncode({
            'type': 'call',
            'callId': message.data['callId']?.toString() ?? '',
            'sender': message.data['sender']?.toString(),
            'fromUserId': message.data['fromUserId']?.toString() ?? message.data['sender']?.toString() ?? '',
            'callType': message.data['callType']?.toString() ?? 'video',
            'incomingCall': message.data['incomingCall']?.toString() ?? 'true',
          })
        : jsonEncode(message.data);
    
    await notificationService.showNotification(
      title: message.notification?.title ?? 'New Message', 
      body: message.notification?.body ?? '', 
      payload: payload
    );
    print('✅ [FCM] Background notification shown');
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
          rethrow; // Re-throw to skip rest of initialization
        }
      }

      // Request permissions
      await _requestPermissions();

      // Get FCM token
      // This will fail on iOS if APN is not configured
      await _getFCMToken();

      // Register token immediately on app start (even without user)
      await _registerTokenOnAppStart();

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
      
      if (_fcmToken != null) {
        print('✅ [FCM] Token retrieved successfully: ${_fcmToken!.substring(0, 20)}...');
      } else {
        print('❌ [FCM] Token retrieval returned null');
      }

      // Store token locally (not in Firestore)
      await _storeFCMTokenLocally();
    } catch (e) {
      print('❌ [FCM] Error getting FCM token: $e');
      _fcmToken = null;
    }
  }

  /// Register FCM token on app start (without user ID)
  Future<void> _registerTokenOnAppStart() async {
    try {
      if (_fcmToken == null) {
        print('⚠️ [FCM] Cannot register token on app start - no FCM token available');
        return;
      }

      print('📤 [FCM] Registering FCM token on app start (without user ID)');

      // Use device service to get device info
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();

      // Send to token API endpoint without user ID
      try {
        final response = await http.post(
          Uri.parse(ApiConstants.token),
          body: {
            'fcmToken': _fcmToken!,
            'deviceId': deviceInfo['id'] ?? deviceInfo['deviceId'] ?? '',
            'platform': deviceInfo['platform'] ?? 'Unknown',
            'model': deviceInfo['model'] ?? 'Unknown'
          }
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1') {
            print('✅ [FCM] Token registered on app start successfully');
          } else {
            print('⚠️ [FCM] Token registration on app start: ${data['message'] ?? 'Unknown error'}');
          }
        } else {
          print('⚠️ [FCM] Token registration on app start failed - server returned status: ${response.statusCode}');
        }
      } catch (e) {
        print('⚠️ [FCM] Failed to register token on app start: $e');
        // Silently fail - device will be updated on login
      }
    } catch (e) {
      print('❌ [FCM] Error in _registerTokenOnAppStart: $e');
    }
  }

  /// Send FCM token to server to register in devices table (with user ID)
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

      // Send to token API endpoint with user ID
      try {
        final response = await http.post(
          Uri.parse(ApiConstants.token),
          body: {
            'userID': user.id.toString(),
            'fcmToken': _fcmToken!,
            'deviceId': deviceInfo['id'] ?? deviceInfo['deviceId'] ?? '',
            'platform': deviceInfo['platform'] ?? 'Unknown',
            'model': deviceInfo['model'] ?? 'Unknown'
          }
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1') {
            print('✅ [FCM] Token sent to server successfully');
          } else {
            print('❌ [FCM] Failed to send token: ${data['message'] ?? 'Unknown error'}');
          }
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
    // NOTE: When app is in foreground, WebSocket handles real-time updates
    // Firebase is only used for background notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final type = message.data['type']?.toString();
      print('📱 [FCM] Received foreground message: type=$type');
      
      // Update activity when receiving notification (user is active)
      // This helps maintain online status even when app is in background
      final authService = AuthService();
      await authService.updateActivity();
      
      // For app_update notifications in foreground, ignore Firebase notification
      // WebSocket will handle real-time delivery when app is in focus
      if (type == 'app_update') {
        
        print('📱 [FCM] App update notification received in foreground - WebSocket will handle notification display');
        
        // Don't show notification here - WebSocket will handle it to avoid duplicates
        // Just trigger the update check callback
        _triggerUpdateCheck();
        return;
      }
      
      // For call notifications, show notification with action buttons
      // IMPORTANT: Always show notification even when app is open, so user sees it
      if (type == 'call') {
        print('📞 [FCM] Call notification received in foreground - showing notification with actions');
        print('📞 [FCM] Call data: callId=${message.data['callId']}, fromUserId=${message.data['fromUserId']}, callType=${message.data['callType']}');
        
        final notificationService = NotificationService();
        try {
          await notificationService.showNotification(
            title: message.notification?.title ?? 'Incoming Call',
            body: message.notification?.body ?? '',
            payload: jsonEncode({
              'type': 'call',
              'callId': message.data['callId']?.toString() ?? '',
              'sender': message.data['sender']?.toString(),
              'fromUserId': message.data['fromUserId']?.toString() ?? message.data['sender']?.toString() ?? '',
              'callType': message.data['callType']?.toString() ?? 'video',
              'incomingCall': message.data['incomingCall']?.toString() ?? 'true',
            }),
          );
          print('✅ [FCM] Call notification shown successfully in foreground');
        } catch (e) {
          print('❌ [FCM] Error showing call notification in foreground: $e');
        }
        // Don't return - also trigger the in-app handler if WebSocket hasn't handled it yet
        // The notification will show as a heads-up, and the in-app dialog will also appear
        return;
      }
      
      // For other message types, show notification
      final notificationService = NotificationService();
      await notificationService.showNotification(
        title: message.notification?.title ?? 'Notification',
        body: message.notification?.body ?? '',
        payload: jsonEncode(message.data),
      );
    });

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Handle navigation based on message data
      _handleNotificationTap(message.data);
    });

    // Check if app was opened from notification
    RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
    if (initialMessage != null) {
      await _handleNotificationTap(initialMessage.data);
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
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
        case 'call_offer':
        case 'call_initiate':
        case 'call':
          // Handle call notification - fetch call offer from Firestore
          final callId = data['callId']?.toString();
          final fromUserId = data['fromUserId']?.toString() ?? data['sender']?.toString();
          final callTypeRaw = data['callType'];
          String callType;
          if (callTypeRaw != null) {
            callType = callTypeRaw.toString().toLowerCase().trim();
            if (callType != 'video' && callType != 'audio') {
              callType = 'audio'; // Default to audio if invalid
            }
          } else {
            callType = 'audio'; // Default to audio if missing
          }
          
          print('📞 [FCM] Call notification tapped - callId: $callId, fromUserId: $fromUserId, type: $callType');
          
          if (callId != null && fromUserId != null) {
            // Fetch call offer from Firestore (stored by WebSocket server)
            try {
              final firestore = FirebaseFirestore.instance;
              final callDoc = await firestore.collection('call_signals').doc(callId).get().timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  print('⚠️ [FCM] Firestore timeout - database may not be configured');
                  throw TimeoutException('Firestore query timeout');
                },
              );
              
              if (callDoc.exists) {
                final callData = callDoc.data();
                final offer = callData?['offer']?.toString() ?? '';
                final callTypeFromFirestore = callData?['callType']?.toString() ?? callType;
                String offerCallType = callTypeFromFirestore.toLowerCase().trim();
                if (offerCallType != 'video' && offerCallType != 'audio') {
                  offerCallType = callType;
                }
                
                print('📞 [FCM] Call offer found in Firestore - callType: $offerCallType');
                
                if (offer.isNotEmpty) {
                  // Wait for app to fully initialize, then handle the call
                  Future.delayed(const Duration(milliseconds: 500), () async {
                    try {
                      final callService = CallService();
                      await callService.handleIncomingOffer(
                        callId: callId,
                        fromUserId: fromUserId,
                        offer: offer,
                        callType: offerCallType,
                      );
                      
                      // Navigate to call screen
                      if (navigatorKey.currentContext != null) {
                        final authService = AuthService();
                        final currentUserId = await authService.getStoredUserId();
                        if (currentUserId != null) {
                          final friendService = FriendService();
                          final friends = await friendService.fetchFriendsForUser(userId: currentUserId);
                          final friend = friends.firstWhere(
                            (f) => f.id == fromUserId,
                            orElse: () => Friend(
                              id: fromUserId,
                              username: fromUserId,
                              nickname: '',
                              avatar: '',
                              online: false,
                            ),
                          );
                          
                          Navigator.of(navigatorKey.currentContext!).push(
                            MaterialPageRoute(
                              builder: (context) => CallScreen(
                                friend: friend,
                                callType: offerCallType == 'video' ? CallType.video : CallType.audio,
                                isIncoming: true,
                              ),
                            ),
                          );
                          print('✅ [FCM] Navigated to call screen for incoming call');
                        }
                      }
                    } catch (e) {
                      print('❌ [FCM] Error handling call offer from Firestore: $e');
                    }
                  });
                } else {
                  print('⚠️ [FCM] Call offer found but offer is empty');
                }
              } else {
                print('⚠️ [FCM] Call offer not found in Firestore - may have expired or database not configured');
                // Show error to user
                if (navigatorKey.currentContext != null) {
                  ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
                    SnackBar(
                      content: Text('Call offer expired or unavailable. Please ask the caller to try again.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            } catch (e) {
              print('❌ [FCM] Error fetching call offer from Firestore: $e');
              // Show error to user
              if (navigatorKey.currentContext != null) {
                ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
                  SnackBar(
                    content: Text('Unable to retrieve call. Please ask the caller to try again.'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }
          } else {
            print('⚠️ [FCM] Call notification missing callId or fromUserId');
          }
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
      final existingToken = _prefs?.getString('fcm_token');
      final isNewToken = existingToken != _fcmToken;
      
      await _prefs?.setString('fcm_token', _fcmToken!);
      
      // Only log if it's a new token or first time storing
      if (isNewToken || existingToken == null) {
        print('✅ [FCM] Token stored locally for user: ${user.id}');
      }
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

  /// Public static method to trigger update check (called from NotificationService)
  /// This avoids circular import issues
  static void triggerUpdateCheck() {
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

  /// Auto-register FCM token when app opens ( apparently not initialized yet
  Future<void> autoRegisterTokenOnAppOpen() async {
    
    try {
      // Check if FCM service is initialized
      if (!_isInitialized) {
        print('❌ [FCM] Cannot auto-register - Firebase Messaging not initialized');
        return;
      }

      // Token was already retrieved during initialize(), just send it to server
      if (_fcmToken == null) {
        // If for some reason we don't have a token, try to get it once more
        await _getFCMToken();
        
        if (_fcmToken == null) {
          print('❌ [FCM] Cannot auto-register - FCM token unavailable after retrieval attempt');
          return;
        }
      }

      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        print('❌ [FCM] Cannot auto-register token - user not logged in');
        return;
      }

      // Get device info for token registration
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();
      
      // Send the token to the token API endpoint
      final response = await http.post(
        Uri.parse(ApiConstants.token),
        body: {
          'userID': user.id.toString(),
          'fcmToken': _fcmToken!,
          'deviceId': deviceInfo['id'] ?? deviceInfo['deviceId'] ?? '',
          'platform': deviceInfo['platform'] ?? 'Unknown',
          'model': deviceInfo['model'] ?? 'Unknown'
        },
      );

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1') {
            print('✅ [FCM] Token auto-registered successfully via token API');
          } else {
            print('❌ [FCM] Auto-registration failed: ${data['message'] ?? 'Unknown error'}');
          }
        } catch (e) {
          print('❌ [FCM] Failed to parse API response: $e');
        }
      } else {
        print('❌ [FCM] Auto-registration failed - HTTP Status: ${response.statusCode}');
        if (response.statusCode == 404) {
          print('⚠️ [FCM] Endpoint not found. Check if ${ApiConstants.token} exists on the server.');
        }
      }
    } catch (e, stackTrace) {
      print('❌ [FCM] Error auto-registering FCM token: $e');
      print('❌ [FCM] Stack trace: $stackTrace');
    }
  }
}
