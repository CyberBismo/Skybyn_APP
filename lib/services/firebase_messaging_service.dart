import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:developer' as developer;
import 'notification_service.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'websocket_service.dart';
import 'in_app_notification_service.dart';
import 'friend_service.dart';
import '../config/constants.dart';
import '../models/friend.dart';
import '../main.dart';
// Firestore disabled - using WebSocket for real-time features instead
// import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

// Helper function to log chat events - always logs regardless of zone filters
void _logChat(String prefix, String message) {
  // Use developer.log which always logs, bypassing zone filters
  developer.log(message, name: prefix);
  // Also use debugPrint as backup
  debugPrint('$prefix: $message');
}

// Handle background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Log ALL incoming Firebase background messages
    final timestamp = DateTime.now().toIso8601String();
    final type = message.data['type']?.toString();
    final messageId = message.messageId ?? 'no-id';
    
    developer.log('═══════════════════════════════════════════════════════', name: 'FCM Background');
    developer.log('📨 Background message received at $timestamp', name: 'FCM Background');
    developer.log('   Message ID: $messageId', name: 'FCM Background');
    developer.log('   Type: $type', name: 'FCM Background');
    developer.log('   Notification title: ${message.notification?.title ?? "null"}', name: 'FCM Background');
    developer.log('   Notification body: ${message.notification?.body ?? "null"}', name: 'FCM Background');
    developer.log('   Full data: ${message.data}', name: 'FCM Background');
    developer.log('   Has notification payload: ${message.notification != null}', name: 'FCM Background');
    developer.log('═══════════════════════════════════════════════════════', name: 'FCM Background');
    
    // Process all messages, including in debug mode (for testing)
    // Debug mode check removed to ensure notifications work during development

    // Check if Firebase is already initialized
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    
    // Initialize NotificationService in background isolate
    // This is critical - NotificationService must be initialized in the background isolate
    // When app is completely closed, FCM will automatically show the notification from the notification field
    // We still initialize the service to show local notifications as a fallback
    final notificationService = NotificationService();
    try {
      await notificationService.initialize();
    } catch (e) {
      // If initialization fails (e.g., app is terminated), FCM will still show the notification automatically
      developer.log('NotificationService initialization failed in background: $e', name: 'FCM Background Handler');
      // Continue - FCM will show the notification from the notification field
    }
    
    // Update user activity when receiving notification (user is active)
    // This helps maintain online status even when app is closed
    try {
      final authService = AuthService();
      await authService.updateActivity();
    } catch (e) {
      // Silently fail - activity update is not critical for notifications
    }

    // Show local notification for background messages
    
    // For call notifications, show with proper call notification format
    if (type == 'call') {
      final callId = message.data['callId']?.toString() ?? '';
      final fromUserId = message.data['fromUserId']?.toString() ?? message.data['sender']?.toString() ?? '';
      final callType = message.data['callType']?.toString() ?? 'video';
      final callTypeText = callType == 'video' ? 'video call' : 'voice call';
      
      final payload = jsonEncode({
        'type': 'call',
        'callId': callId,
        'sender': fromUserId,
        'fromUserId': fromUserId,
        'callType': callType,
        'incomingCall': 'true',
      });
      
      // Show call notification with action buttons (Answer/Decline)
      await notificationService.showNotification(
        title: message.notification?.title ?? 'Incoming Call',
        body: message.notification?.body ?? 'Incoming $callTypeText',
        payload: payload,
      );
    } else {
      // For other message types (including chat), show normal notification
      // IMPORTANT: When app is in background, FCM may automatically show notifications with notification payload
      // But we ALWAYS show a local notification to ensure it's displayed, especially for data-only messages
      final payload = jsonEncode(message.data);
      
      // For chat messages, log details
      if (type == 'chat') {
        final sender = message.data['sender']?.toString() ?? message.data['from']?.toString() ?? 'unknown';
        final messageId = message.data['messageId']?.toString() ?? 'unknown';
        _logChat('FCM Background Chat', 'Chat message received in background:');
        _logChat('FCM Background Chat', '   - Sender: $sender');
        _logChat('FCM Background Chat', '   - MessageId: $messageId');
        _logChat('FCM Background Chat', '   - Has notification payload: ${message.notification != null}');
        _logChat('FCM Background Chat', '   - Notification title: ${message.notification?.title ?? "null"}');
        _logChat('FCM Background Chat', '   - Notification body: ${message.notification?.body ?? "null"}');
        _logChat('FCM Background Chat', '   - Full data: ${message.data}');
      }
      
      // For chat messages, ensure we have a proper title and body
      String title = message.notification?.title ?? 'New Message';
      String body = message.notification?.body ?? '';
      
      // If notification payload is missing (data-only message), extract from data
      if (title == 'New Message' && body.isEmpty && type == 'chat') {
        // Try to get sender name and message from data payload
        final sender = message.data['sender']?.toString() ?? message.data['from']?.toString() ?? 'Someone';
        final messageText = message.data['message']?.toString() ?? message.data['body']?.toString() ?? 'New message';
        title = sender;
        body = messageText;
        if (type == 'chat') {
          _logChat('FCM Background Chat', 'Extracted title/body from data: title="$title", body="${body.length > 50 ? body.substring(0, 50) + "..." : body}"');
        }
      }
      
      // IMPORTANT: When app is TERMINATED, this background handler does NOT run.
      // FCM will automatically display notifications that have a 'notification' field.
      // This handler only runs when app is in BACKGROUND (not terminated).
      // 
      // For terminated apps: FCM automatically shows the notification from the 'notification' field.
      // For background apps: 
      // - FCM may or may not show the notification automatically depending on Android version
      // - To ensure reliability, we ALWAYS show a local notification for chat messages
      // - This ensures the notification is displayed even if FCM doesn't show it automatically
      // 
      // CRITICAL FIX: Always show local notification for chat messages to ensure delivery
      // Even if FCM shows it automatically, showing a local notification ensures it's displayed
      final hasNotificationPayload = message.notification != null && 
                                     message.notification!.title != null && 
                                     message.notification!.title!.isNotEmpty;
      
      // Chat notification handling removed - UI only
      // For other types, only show local notification if it's data-only
      if (!hasNotificationPayload && type != 'chat') {
        try {
          await notificationService.showNotification(
            title: title, 
            body: body, 
            payload: payload
          );
        } catch (e) {
          // Don't rethrow - log the error but continue execution
        }
      }
    }
  } catch (e, stackTrace) {
    // Log errors in background handler for debugging
    // Use developer.log which always logs, even in background isolate
    developer.log('Error processing notification: $e', name: 'FCM Background Handler', error: e, stackTrace: stackTrace);
    developer.log('Message data: ${message.data}', name: 'FCM Background Handler');
    developer.log('Notification: ${message.notification?.title} - ${message.notification?.body}', name: 'FCM Background Handler');
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
  // Callback for incoming call from notification
  static Function(String, String, String)? _onIncomingCallFromNotification; // callId, fromUserId, callType
  bool _isInitialized = false;
  static bool _backgroundHandlerRegistered = false; // Track if background handler is already registered

  // Topic subscriptions
  final List<String> _subscribedTopics = [];
  
  // Key for storing last registered app version
  static const String _lastRegisteredVersionKey = 'fcm_last_registered_version';

  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> initialize() async {
    // Prevent duplicate initialization
    if (_isInitialized) {
      _logChat('FCM Init', 'Already initialized, skipping');
      return;
    }
    
    try {
      // Ensure Firebase Core is initialized first
      if (Firebase.apps.isEmpty) {
        throw Exception('Firebase Core must be initialized before Firebase Messaging');
      }
      // On iOS, check if APN is configured before proceeding
      if (Platform.isIOS) {
        try {
          // Attempt to get FirebaseMessaging instance - this will fail if APN not configured
          _messaging = FirebaseMessaging.instance;
        } catch (e) {
          // Reset messaging instance and fail gracefully
          _messaging = null;
          _isInitialized = false;
          rethrow;
        }
      } else {
        // Android - initialize normally
        _messaging = FirebaseMessaging.instance;
      }

      // Set background message handler - only register once to prevent duplicate isolate warning
      // Note: onBackgroundMessage should ideally be called before runApp(), but we check here to prevent duplicates
      // The duplicate warning can occur during hot reload or if initialize() is called multiple times
      if (!_backgroundHandlerRegistered) {
        try {
          FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
          _backgroundHandlerRegistered = true;
          _logChat('FCM Init', '✅ Background message handler registered');
        } catch (e) {
          // If it's already registered (e.g., during hot reload), that's okay - just log it
          _logChat('FCM Init', '⚠️ Background handler registration issue (may already be registered): $e');
          _backgroundHandlerRegistered = true; // Mark as registered to prevent retries
        }
      } else {
        _logChat('FCM Init', '⏭️ Background handler already registered, skipping');
      }

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
          rethrow; // Re-throw to skip rest of initialization
        }
      }

      // Don't request permissions on initialization - will be requested on login
      // Get FCM token
      // This will fail on iOS if APN is not configured
      await _getFCMToken();

      // Register FCM token immediately
      // If user is logged in, register with user ID; otherwise register anonymously
      if (_fcmToken != null) {
        // Check if user is logged in
        await _initPrefs();
        String? userIdString = _prefs?.getString('userID') ?? _prefs?.getString(StorageKeys.userId);
        int? userId;
        
        if (userIdString != null && userIdString.isNotEmpty) {
          userId = int.tryParse(userIdString);
          if (userId != null && userId > 0) {
            // User is logged in - register with user ID
            _logChat('FCM Init', '📱 User logged in (ID: $userId) - registering token with user ID');
            try {
              await sendFCMTokenToServer(userId: userId);
            } catch (e) {
              _logChat('FCM Init', '⚠️ Failed to register token with user ID, falling back to anonymous: $e');
              // Fallback to anonymous registration if sending with user ID fails
              await registerFCMTokenAnonymously();
            }
          } else {
            // Invalid user ID - register anonymously
            await registerFCMTokenAnonymously();
          }
        } else {
          // Try to get from user profile as fallback
          try {
            final user = await _authService.getStoredUserProfile();
            if (user != null && user.id.isNotEmpty) {
              final parsedUserId = int.tryParse(user.id);
              if (parsedUserId != null && parsedUserId > 0) {
                userId = parsedUserId;
                _logChat('FCM Init', '📱 User logged in (ID: $userId from profile) - registering token with user ID');
                try {
                  await sendFCMTokenToServer(userId: userId);
                } catch (e) {
                  _logChat('FCM Init', '⚠️ Failed to register token with user ID, falling back to anonymous: $e');
                  await registerFCMTokenAnonymously();
                }
              } else {
                // No valid user ID - register anonymously
                await registerFCMTokenAnonymously();
              }
            } else {
              // No user logged in - register anonymously
              await registerFCMTokenAnonymously();
            }
          } catch (e) {
            // Error getting user profile - register anonymously
            await registerFCMTokenAnonymously();
          }
        }
      }

      // Set up message handlers
      await _setupMessageHandlers();
      
      // Set up token refresh listener to automatically update database when token changes
      _setupTokenRefreshListener();
      
      // Check if app version changed and update FCM token if needed
      await _checkAndUpdateTokenAfterAppUpdate();

      // Auto-subscribe to default topics
      await autoSubscribeToTopics();
      
      // Mark as initialized only after everything succeeds
      _isInitialized = true;
      _logChat('FCM Init', '✅ Firebase Messaging initialized successfully');
    } catch (e) {
      if (Platform.isIOS) {
      } else {
      }
      // Reset messaging instance on failure
      _messaging = null;
      _isInitialized = false;
    }
  }

  /// Check if notification permission was previously denied
  Future<bool> wasPermissionDenied() async {
    try {
      await _initPrefs();
      final denied = _prefs?.getBool('notification_permission_denied') ?? false;
      return denied;
    } catch (e) {
      return false;
    }
  }

  /// Check current notification permission status
  Future<AuthorizationStatus> getPermissionStatus() async {
    try {
      if (_messaging == null) {
        return AuthorizationStatus.notDetermined;
      }
      
      final NotificationSettings settings = await _messaging!.getNotificationSettings();
      return settings.authorizationStatus;
    } catch (e) {
      return AuthorizationStatus.notDetermined;
    }
  }

  /// Request notification permissions (only if not previously denied)
  /// Returns true if permission was granted, false otherwise
  Future<bool> requestPermissions({bool force = false}) async {
    try {
      if (_messaging == null) {
        return false;
      }
      
      // Check if permission was previously denied (unless forcing)
      if (!force) {
        final wasDenied = await wasPermissionDenied();
        if (wasDenied) {
          _logChat('FCM Permissions', '⚠️ Notification permission was previously denied - not requesting again');
          return false;
        }
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
      
      await _initPrefs();
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // Permission granted - clear denied flag
        await _prefs?.setBool('notification_permission_denied', false);
        _logChat('FCM Permissions', '✅ Notification permission granted');
        return true;
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // Permission denied - store flag
        await _prefs?.setBool('notification_permission_denied', true);
        _logChat('FCM Permissions', '❌ Notification permission denied');
        return false;
      } else if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        _logChat('FCM Permissions', '⚠️ Notification permission not determined');
        return false;
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        _logChat('FCM Permissions', 'ℹ️ Notification permission provisional');
        return true; // Provisional is considered granted
      }
      
      return false;
    } catch (e) {
      _logChat('FCM Permissions', '❌ Error requesting notification permission: $e');
      return false;
    }
  }

  Future<void> _getFCMToken() async {
    try {
      if (_messaging == null) {
        return;
      }
      
      _fcmToken = await _messaging!.getToken();
      
      if (_fcmToken != null) {
      } else {
      }

      // Store token locally (not in Firestore)
      await _storeFCMTokenLocally();
    } catch (e) {
      _fcmToken = null;
    }
  }

  /// Register FCM token to server without user ID (anonymous registration)
  /// This is called when app opens, even if user is not logged in
  /// The device record will be created/updated with user=0, and updated with user ID on login
  Future<void> registerFCMTokenAnonymously() async {
    try {
      if (_fcmToken == null) {
        _logChat('FCM Anonymous', '⚠️ Cannot register token: FCM token is null');
        return;
      }

      _logChat('FCM Anonymous', '📱 Registering FCM token anonymously (no user ID)');
      
      // Use device service to get device info
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();

      // Send to token API endpoint without user ID
      try {
        final requestBody = {
          'fcmToken': _fcmToken!,
          'deviceId': deviceInfo['id'] ?? deviceInfo['deviceId'] ?? '',
          'platform': deviceInfo['platform'] ?? 'Unknown',
          'model': deviceInfo['model'] ?? 'Unknown'
        };
        
        _logChat('FCM Anonymous', '📱 Sending anonymous token registration: deviceId=${requestBody['deviceId']}');
        
        final response = await http.post(
          Uri.parse(ApiConstants.token),
          body: requestBody
        );

        _logChat('FCM Anonymous', '📱 Token registration response: statusCode=${response.statusCode}, body=${response.body}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1' || data['responseCode'] == 1) {
            _logChat('FCM Anonymous', '✅ Token registered successfully (anonymous)');
          } else {
            _logChat('FCM Anonymous', '❌ Token registration failed: ${data['message'] ?? 'Unknown error'}');
          }
        } else {
          _logChat('FCM Anonymous', '❌ Token registration HTTP error: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        _logChat('FCM Anonymous', '❌ Token registration exception: $e');
        // Don't throw - anonymous registration failure shouldn't block app initialization
      }
    } catch (e) {
      _logChat('FCM Anonymous', '❌ registerFCMTokenAnonymously error: $e');
      // Don't throw - anonymous registration failure shouldn't block app initialization
    }
  }

  /// Send FCM token to server to register in devices table (with or without user ID)
  /// If user ID is available, registers with user ID; otherwise registers anonymously
  /// Also updates the stored app version after successful registration
  /// 
  /// [userId] - Optional user ID to use. If not provided, will try to get from storage.
  Future<void> sendFCMTokenToServer({int? userId}) async {
    try {
      if (_fcmToken == null) {
        print('⚠️ [FCM] Cannot register token: FCM token is null');
        return;
      }

      // Get user ID - use provided userId parameter first, then try from storage
      int? finalUserId = userId;
      
      // If not provided, try from SharedPreferences first (faster, available immediately after login)
      if (finalUserId == null || finalUserId == 0) {
        await _initPrefs();
        // Try both 'userID' (from login response) and 'user_id' (from StorageKeys)
        String? userIdString = _prefs?.getString('userID') ?? _prefs?.getString(StorageKeys.userId);
        
        if (userIdString != null && userIdString.isNotEmpty) {
          finalUserId = int.tryParse(userIdString);
          if (finalUserId != null && finalUserId > 0) {
            print('[SKYBYN] 📱 [FCM] Got user ID from SharedPreferences: $finalUserId');
          } else {
            finalUserId = null;
          }
        }
      } else {
        print('[SKYBYN] 📱 [FCM] Using provided user ID: $finalUserId');
      }
      
      // If not found in SharedPreferences, try to get from user profile (with retries)
      if (finalUserId == null || finalUserId == 0) {
        var user = await _authService.getStoredUserProfile();
        int retries = 0;
        const maxRetries = 5;
        const retryDelay = Duration(milliseconds: 500);
        
        while ((user == null || user.id.isEmpty || int.tryParse(user.id) == null || int.parse(user.id) == 0) && retries < maxRetries) {
          user = await _authService.getStoredUserProfile();
          if (user != null && user.id.isNotEmpty) {
            final parsedUserId = int.tryParse(user.id);
            if (parsedUserId != null && parsedUserId > 0) {
              finalUserId = parsedUserId;
              print('[SKYBYN] 📱 [FCM] Got user ID from user profile: $finalUserId');
              break;
            }
          }
          print('[SKYBYN] ⚠️ [FCM] User ID not available yet, retrying... (${retries + 1}/$maxRetries)');
          await Future.delayed(retryDelay);
          retries++;
        }
      }
      
      // Use device service to get device info
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();

      // Build request body - include userID only if available
      final requestBody = <String, String>{
        'fcmToken': _fcmToken!,
        'deviceId': deviceInfo['id'] ?? deviceInfo['deviceId'] ?? '',
        'platform': deviceInfo['platform'] ?? 'Unknown',
        'model': deviceInfo['model'] ?? 'Unknown'
      };
      
      // Add user ID if available
      if (finalUserId != null && finalUserId > 0) {
        requestBody['userID'] = finalUserId.toString();
        print('[SKYBYN] 📱 [FCM] Registering token for user ID: $finalUserId');
      } else {
        print('[SKYBYN] ⚠️ [FCM] WARNING: User ID not available! Registering token anonymously (user ID will be 0)');
        print('[SKYBYN] ⚠️ [FCM] This should not happen after login. Check if user ID is stored in SharedPreferences.');
      }

      // Send to token API endpoint (with or without user ID)
      try {
        // Log the exact request body being sent
        print('[SKYBYN] 📱 [FCM] Sending token registration request:');
        print('[SKYBYN] 📱 [FCM]   - userID: ${requestBody['userID'] ?? 'NOT PROVIDED'}');
        print('[SKYBYN] 📱 [FCM]   - deviceId: ${requestBody['deviceId']}');
        print('[SKYBYN] 📱 [FCM]   - platform: ${requestBody['platform']}');
        print('[SKYBYN] 📱 [FCM]   - model: ${requestBody['model']}');
        print('[SKYBYN] 📱 [FCM]   - fcmToken: ${_fcmToken?.substring(0, 20)}...');
        
        final response = await http.post(
          Uri.parse(ApiConstants.token),
          body: requestBody
        );

        print('[SKYBYN] 📱 [FCM] Token registration response: statusCode=${response.statusCode}');
        print('[SKYBYN] 📱 [FCM] Response body: ${response.body}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1' || data['responseCode'] == 1) {
            final registeredUserId = data['userId'] ?? data['userID'] ?? 'unknown';
            if (finalUserId != null && finalUserId > 0) {
              print('[SKYBYN] ✅ [FCM] Token registered successfully for user $finalUserId (database shows: $registeredUserId)');
            } else {
              print('[SKYBYN] ✅ [FCM] Token registered successfully (anonymous, database shows: $registeredUserId)');
            }
            
            // Update stored app version after successful registration
            try {
              await _initPrefs();
              final PackageInfo packageInfo = await PackageInfo.fromPlatform();
              final String currentVersion = packageInfo.buildNumber.isNotEmpty ? packageInfo.buildNumber : packageInfo.version;
              await _prefs?.setString(_lastRegisteredVersionKey, currentVersion);
              print('📱 [FCM] Updated stored app version to $currentVersion');
            } catch (e) {
              print('⚠️ [FCM] Failed to update stored app version: $e');
            }
          } else {
            print('❌ [FCM] Token registration failed: ${data['message'] ?? 'Unknown error'}');
          }
        } else {
          print('❌ [FCM] Token registration HTTP error: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        print('❌ [FCM] Token registration exception: $e');
        // Don't silently fail - log the error so we can debug
        rethrow;
      }
    } catch (e) {
      print('❌ [FCM] sendFCMTokenToServer error: $e');
      // Re-throw so caller can handle it
      rethrow;
    }
  }

  Future<void> _setupMessageHandlers() async {
    if (_messaging == null) {
      return;
    }
    
    // Handle foreground messages
    // NOTE: When app is in foreground and WebSocket is connected, WebSocket handles real-time updates
    // Firebase is only used when WebSocket is not available (e.g., connection issues, app just started)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      try {
        final timestamp = DateTime.now().toIso8601String();
        final type = message.data['type']?.toString();
        final messageId = message.messageId ?? 'no-id';
        
        // Check if WebSocket is connected - if so, skip Firebase notifications
        final webSocketService = WebSocketService();
        final isWebSocketConnected = webSocketService.isConnected;
        
        // Log ALL incoming Firebase foreground messages
        _logChat('FCM Foreground', '═══════════════════════════════════════════════════════');
        _logChat('FCM Foreground', '📨 Foreground message received at $timestamp');
        _logChat('FCM Foreground', '   Message ID: $messageId');
        _logChat('FCM Foreground', '   Type: $type');
        _logChat('FCM Foreground', '   WebSocket connected: $isWebSocketConnected');
        _logChat('FCM Foreground', '   Notification title: ${message.notification?.title ?? "null"}');
        _logChat('FCM Foreground', '   Notification body: ${message.notification?.body ?? "null"}');
        _logChat('FCM Foreground', '   Full data: ${message.data}');
        _logChat('FCM Foreground', '   Has notification payload: ${message.notification != null}');
        _logChat('FCM Foreground', '═══════════════════════════════════════════════════════');
        
        // If WebSocket is connected, skip Firebase notifications (WebSocket handles them)
        if (isWebSocketConnected) {
          _logChat('FCM Foreground', '⏭️ Skipping Firebase notification - WebSocket is connected and will handle it');
          return;
        }
        
        _logChat('FCM Foreground', '✅ Processing Firebase notification - WebSocket not available');
        
        // Update activity when receiving notification (user is active)
        // This helps maintain online status even when app is in background
        try {
          final authService = AuthService();
          await authService.updateActivity();
        } catch (e) {
          _logChat('FCM Foreground', '⚠️ Failed to update activity: $e');
          // Continue processing notification even if activity update fails
        }
      
      // For app_update notifications in foreground, ignore Firebase notification
      // WebSocket will handle real-time delivery when app is in focus
      if (type == 'app_update') {
        // Don't show notification here - WebSocket will handle it to avoid duplicates
        // Just trigger the update check callback
        _triggerUpdateCheck();
        return;
      }
      
      // Chat message handling removed - UI only
      // if (type == 'chat') {
      //   // Chat notifications disabled
      // }
      
      // For call notifications, show notification with action buttons
      // Only show via Firebase if WebSocket is not available (WebSocket handles calls when connected)
      if (type == 'call') {
        final callId = message.data['callId']?.toString() ?? '';
        final fromUserId = message.data['fromUserId']?.toString() ?? message.data['sender']?.toString() ?? '';
        final callType = message.data['callType']?.toString() ?? 'video';
        _logChat('FCM Foreground Call', '📞 Call notification: callId=$callId, from=$fromUserId, type=$callType');
        _logChat('FCM Foreground Call', '   WebSocket connected: $isWebSocketConnected');
        
        // If WebSocket is connected, it should handle the call - skip Firebase notification
        if (isWebSocketConnected) {
          _logChat('FCM Foreground Call', '⏭️ Skipping Firebase call notification - WebSocket is connected and will handle it');
          return;
        }
        
        _logChat('FCM Foreground Call', '✅ Showing Firebase call notification - WebSocket not available');
        final notificationService = NotificationService();
        try {
          await notificationService.showNotification(
            title: message.notification?.title ?? 'Incoming Call',
            body: message.notification?.body ?? '',
            payload: jsonEncode({
              'type': 'call',
              'callId': callId,
              'sender': message.data['sender']?.toString(),
              'fromUserId': fromUserId,
              'callType': callType,
              'incomingCall': message.data['incomingCall']?.toString() ?? 'true',
            }),
          );
          _logChat('FCM Foreground Call', '✅ Call notification shown successfully');
        } catch (e) {
          _logChat('FCM Foreground Call', '❌ Failed to show call notification: $e');
        }
        return;
      }
      
      // For other message types (including chat), show in-app notification if foreground, system if background
      // Check if app is in foreground - if so, show in-app notification only (no system notification)
      bool isAppInForeground = false;
      try {
        isAppInForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      } catch (e) {
        _logChat('FCM Foreground', '⚠️ Failed to check app lifecycle state: $e');
        // Default to showing system notification if we can't determine state
        isAppInForeground = false;
      }
      
      if (isAppInForeground) {
        // App is in foreground - show in-app notification only, not system notification
        // Chat notification handling removed - UI only
        // For other types, show in-app notification
        if (type != 'chat') {
          final inAppNotificationService = InAppNotificationService();
          inAppNotificationService.showNotification(
            title: message.notification?.title ?? 'Notification',
            body: message.notification?.body ?? '',
            icon: Icons.notifications,
            iconColor: Colors.blue,
            notificationType: type ?? 'generic',
            onTap: () {
              final nav = navigatorKey.currentState;
              if (nav != null) {
                nav.pushNamed('/home');
              }
            },
          );
          _logChat('FCM Foreground', '✅ In-app notification shown for type: $type');
        }
      } else {
        // App is in background - show system notification only
        _logChat('FCM Foreground', 'App is in background, showing system notification for type: $type');
        final notificationService = NotificationService();
        try {
          await notificationService.showNotification(
            title: message.notification?.title ?? 'Notification',
            body: message.notification?.body ?? '',
            payload: jsonEncode(message.data),
          );
          _logChat('FCM Foreground', '✅ System notification shown successfully for type: $type');
        } catch (e) {
          _logChat('FCM Foreground', '❌ Failed to show system notification for type $type: $e');
        }
      }
    } catch (e, stackTrace) {
      // Catch any unhandled exceptions in the message handler to prevent app crashes
      _logChat('FCM Foreground', '❌ CRITICAL: Unhandled exception in onMessage handler: $e');
      _logChat('FCM Foreground', '   Stack trace: $stackTrace');
      _logChat('FCM Foreground', '   Message data: ${message.data}');
      _logChat('FCM Foreground', '   Notification: ${message.notification?.title} - ${message.notification?.body}');
      // Don't rethrow - prevent app crash
    }
    });

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      try {
        final type = message.data['type']?.toString();
        _logChat('FCM Opened App', '📱 App opened from notification: type=$type, messageId=${message.messageId}');
        _logChat('FCM Opened App', '   Full data: ${message.data}');
        // Handle navigation based on message data
        _handleNotificationTap(message.data);
      } catch (e, stackTrace) {
        _logChat('FCM Opened App', '❌ CRITICAL: Unhandled exception in onMessageOpenedApp handler: $e');
        _logChat('FCM Opened App', '   Stack trace: $stackTrace');
        _logChat('FCM Opened App', '   Message data: ${message.data}');
        // Don't rethrow - prevent app crash
      }
    });

    // Check if app was opened from notification
    try {
      RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        final type = initialMessage.data['type']?.toString();
        _logChat('FCM Initial Message', '📱 App opened from initial notification: type=$type, messageId=${initialMessage.messageId}');
        _logChat('FCM Initial Message', '   Full data: ${initialMessage.data}');
        await _handleNotificationTap(initialMessage.data);
      }
    } catch (e, stackTrace) {
      _logChat('FCM Initial Message', '❌ CRITICAL: Unhandled exception in getInitialMessage: $e');
      _logChat('FCM Initial Message', '   Stack trace: $stackTrace');
      // Don't rethrow - prevent app crash
    }
  }

  /// Handle chat notification tap - navigate to chat screen
  Future<void> _handleChatNotificationNavigation(Map<String, dynamic> data) async {
    try {
      final sender = data['sender']?.toString() ?? data['from']?.toString();
      if (sender == null) {
        _logChat('FCM Chat', 'Cannot navigate - sender ID is null');
        return;
      }

      // Log chat notification tap
      final messageId = data['messageId']?.toString() ?? 'unknown';
      _logChat('FCM Chat', 'Chat notification tapped:');
      _logChat('FCM Chat', '   - Sender: $sender');
      _logChat('FCM Chat', '   - MessageId: $messageId');

      // Get current user ID to fetch friends
      final authService = AuthService();
      final currentUserId = await authService.getStoredUserId();
      if (currentUserId == null) {
        _logChat('FCM Chat', 'Cannot navigate - current user ID is null');
        return;
      }

      // Fetch friend information
      final friendService = FriendService();
      final friends = await friendService.fetchFriendsForUser(userId: currentUserId);
      final friend = friends.firstWhere(
        (f) => f.id == sender,
        orElse: () => Friend(
          id: sender,
          username: sender,
          nickname: '',
          avatar: '',
          online: false,
        ),
      );

      // Navigate to chat screen
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamed(
          '/chat',
          arguments: {'friend': friend},
        );
        _logChat('FCM Chat', '✅ Navigated to chat screen for friend: ${friend.username}');
      } else {
        _logChat('FCM Chat', '⚠️ Cannot navigate - navigator is null');
      }
    } catch (e) {
      _logChat('FCM Chat', '❌ Failed to handle chat notification tap: $e');
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
    try {
      final type = data['type']?.toString();
      final payload = data['payload']?.toString();
      
      // Log notification tap
      _logChat('FCM', 'Notification tapped - type: $type');

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
        case 'chat':
          // Handle chat notification tap - navigate to chat screen
          await _handleChatNotificationNavigation(data);
          break;
        case 'call_offer':
        case 'call_initiate':
        case 'call':
          // Handle call notification when app opens from notification
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
          if (callId != null && fromUserId != null) {
            // Store pending call info and trigger call handling
            // The WebSocket service will connect and receive the call offer
            // We'll handle it in main.dart when WebSocket connects
            _handleIncomingCallFromNotification(callId, fromUserId, callType);
          }
          break;
        default:
      }
    } catch (e) {
    }
  }

  Future<void> _storeFCMTokenLocally() async {
    try {
      if (_fcmToken == null) {
        return;
      }

      // Store token locally using SharedPreferences
      await _initPrefs();
      final existingToken = _prefs?.getString('fcm_token');
      final isNewToken = existingToken != null && existingToken != _fcmToken;
      
      await _prefs?.setString('fcm_token', _fcmToken!);
      
      // If token changed and user is logged in, update database automatically
      if (isNewToken && existingToken != null) {
        _logChat('FCM Token', '🔄 FCM token changed - checking if user is logged in to update database');
        
        // Check if user is logged in
        String? userIdString = _prefs?.getString('userID') ?? _prefs?.getString(StorageKeys.userId);
        int? userId;
        
        if (userIdString != null && userIdString.isNotEmpty) {
          userId = int.tryParse(userIdString);
        }
        
        // If user ID not found in SharedPreferences, try user profile
        if ((userId == null || userId == 0) && _isInitialized) {
          try {
            final user = await _authService.getStoredUserProfile();
            if (user != null && user.id.isNotEmpty) {
              final parsedUserId = int.tryParse(user.id);
              if (parsedUserId != null && parsedUserId > 0) {
                userId = parsedUserId;
              }
            }
          } catch (e) {
            // Silently fail - user profile might not be available yet
          }
        }
        
        // Update database if user is logged in
        if (userId != null && userId > 0) {
          _logChat('FCM Token', '✅ User logged in (ID: $userId) - updating FCM token in database');
          // Use a delayed call to avoid blocking initialization
          final userIdToUse = userId; // Capture for closure
          Future.delayed(const Duration(seconds: 1), () async {
            try {
              await sendFCMTokenToServer(userId: userIdToUse);
              _logChat('FCM Token', '✅ FCM token updated in database after token change');
            } catch (e) {
              _logChat('FCM Token', '❌ Failed to update FCM token in database: $e');
            }
          });
        } else {
          _logChat('FCM Token', '⚠️ User not logged in - FCM token will be updated on next login');
        }
      }
      
      // Only log if it's a new token or first time storing
      if (isNewToken || existingToken == null) {
      }
    } catch (e) {
    }
  }

  Future<String?> getStoredFCMToken() async {
    try {
      await _initPrefs();
      final token = _prefs?.getString('fcm_token');
      if (token != null) {
      } else {
      }
      return token;
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteFCMToken() async {
    try {
      await _initPrefs();
      await _prefs?.remove('fcm_token');
      _fcmToken = null;
    } catch (e) {
    }
  }

  /// Set callback for update check requests
  static void setUpdateCheckCallback(VoidCallback? callback) {
    _onUpdateCheckRequested = callback;
  }

  /// Set callback for incoming call from notification
  static void setIncomingCallCallback(Function(String, String, String)? callback) {
    _onIncomingCallFromNotification = callback;
  }

  /// Handle incoming call from notification
  void _handleIncomingCallFromNotification(String callId, String fromUserId, String callType) {
    // Trigger callback if set (will be handled in main.dart)
    _onIncomingCallFromNotification?.call(callId, fromUserId, callType);
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
        return false;
      }
      
      await _messaging!.subscribeToTopic(topic);
      if (!_subscribedTopics.contains(topic)) {
        _subscribedTopics.add(topic);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Unsubscribe from a topic
  Future<bool> unsubscribeFromTopic(String topic) async {
    try {
      if (_messaging == null) {
        return false;
      }
      
      await _messaging!.unsubscribeFromTopic(topic);
      _subscribedTopics.remove(topic);
      return true;
    } catch (e) {
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
      for (final topic in defaultTopics) {
        final success = await subscribeToTopic(topic);
        if (!success) {
        }
        // Small delay to avoid overwhelming the service
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
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
        return;
      }

      // User-specific topics
      final userTopics = [
        'user_${user.id}', // User-specific notifications
        'rank_${user.rank}', // Rank-based notifications
        'status_${user.online}', // Online status notifications
      ];
      for (final topic in userTopics) {
        final success = await subscribeToTopic(topic);
        if (!success) {
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
    }
  }

  /// Get list of subscribed topics
  List<String> get subscribedTopics => List.from(_subscribedTopics);

  /// Check if subscribed to a specific topic
  bool isSubscribedToTopic(String topic) => _subscribedTopics.contains(topic);

  /// Check if app version changed and update FCM token if needed
  /// This ensures FCM token is updated after each app update
  Future<void> _checkAndUpdateTokenAfterAppUpdate() async {
    try {
      await _initPrefs();
      
      // Get current app version/build number
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.buildNumber.isNotEmpty ? packageInfo.buildNumber : packageInfo.version;
      
      // Get last registered version
      final String? lastRegisteredVersion = _prefs?.getString(_lastRegisteredVersionKey);
      
      // If version changed or never registered, update FCM token
      if (lastRegisteredVersion != currentVersion) {
        print('📱 [FCM] App version changed from ${lastRegisteredVersion ?? 'unknown'} to $currentVersion - updating FCM token');
        
        // Check if user is logged in before updating
        String? userIdString = _prefs?.getString('userID') ?? _prefs?.getString(StorageKeys.userId);
        int? userId;
        
        if (userIdString!.isNotEmpty) {
          userId = int.tryParse(userIdString);
          if (userId != null && userId > 0) {
            // User is logged in - update FCM token
            await sendFCMTokenToServer(userId: userId);
            
            // Update stored version
            await _prefs?.setString(_lastRegisteredVersionKey, currentVersion);
            print('✅ [FCM] FCM token updated after app update to version $currentVersion');
          } else {
            print('⚠️ [FCM] User not logged in - FCM token will be updated after login');
          }
        } else {
          // Try to get from user profile
          final user = await _authService.getStoredUserProfile();
          if (user != null && user.id.isNotEmpty) {
            final parsedUserId = int.tryParse(user.id);
            if (parsedUserId != null && parsedUserId > 0) {
              userId = parsedUserId;
              // User is logged in - update FCM token
              await sendFCMTokenToServer(userId: userId);
              
              // Update stored version
              await _prefs?.setString(_lastRegisteredVersionKey, currentVersion);
              print('✅ [FCM] FCM token updated after app update to version $currentVersion');
            } else {
              print('⚠️ [FCM] User not logged in - FCM token will be updated after login');
            }
          } else {
            print('⚠️ [FCM] User not logged in - FCM token will be updated after login');
          }
        }
      } else {
        print('📱 [FCM] App version unchanged ($currentVersion) - FCM token up to date');
      }
    } catch (e) {
      print('❌ [FCM] Error checking app version for FCM token update: $e');
      // Don't throw - this is a background check
    }
  }

  /// Auto-register FCM token when app opens (with user ID)
  Future<void> autoRegisterTokenOnAppOpen() async {
    try {
      // Check if FCM service is initialized
      if (!_isInitialized) {
        print('⚠️ [FCM] Cannot auto-register token: FCM service not initialized');
        return;
      }

      // Token was already retrieved during initialize(), just send it to server
      if (_fcmToken == null) {
        // If for some reason we don't have a token, try to get it once more
        await _getFCMToken();
        
        if (_fcmToken == null) {
          print('⚠️ [FCM] Cannot auto-register token: FCM token is null');
          return;
        }
      }

      // Get user ID - try from SharedPreferences first (faster, available immediately after login)
      await _initPrefs();
      // Try both 'userID' (from login response) and 'user_id' (from StorageKeys)
      String? userIdString = _prefs?.getString('userID') ?? _prefs?.getString(StorageKeys.userId);
      int? userId;
      
      if (userIdString!.isNotEmpty) {
        userId = int.tryParse(userIdString);
        if (userId != null && userId > 0) {
          print('📱 [FCM] Auto-registering token for user ID (from SharedPreferences): $userId');
        } else {
          userId = null;
        }
      }
      
      // If not found in SharedPreferences, try to get from user profile
      if (userId == null || userId == 0) {
        final user = await _authService.getStoredUserProfile();
        if (user != null && user.id.isNotEmpty) {
          final parsedUserId = int.tryParse(user.id);
          if (parsedUserId != null && parsedUserId > 0) {
            userId = parsedUserId;
            print('📱 [FCM] Auto-registering token for user ID (from profile): $userId');
          }
        }
      }

      // Final check - user ID must be valid (not null, not 0)
      if (userId == null || userId == 0) {
        print('⚠️ [FCM] Cannot auto-register token: User ID is invalid or user not logged in (userId=$userId)');
        return;
      }

      // Get device info for token registration
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();
      
      final requestBody = {
        'userID': userId.toString(),
        'fcmToken': _fcmToken!,
        'deviceId': deviceInfo['id'] ?? deviceInfo['deviceId'] ?? '',
        'platform': deviceInfo['platform'] ?? 'Unknown',
        'model': deviceInfo['model'] ?? 'Unknown'
      };
      
      print('📱 [FCM] Sending auto-registration request: userID=${requestBody['userID']}, deviceId=${requestBody['deviceId']}');
      
      // Send the token to the token API endpoint
      final response = await http.post(
        Uri.parse(ApiConstants.token),
        body: requestBody,
      );

      print('📱 [FCM] Auto-registration response: statusCode=${response.statusCode}, body=${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1' || data['responseCode'] == 1) {
            print('✅ [FCM] Token auto-registered successfully for user $userId');
          } else {
            print('❌ [FCM] Token auto-registration failed: ${data['message'] ?? 'Unknown error'}');
          }
        } catch (e) {
          print('❌ [FCM] Failed to parse auto-registration response: $e');
        }
      } else {
        if (response.statusCode == 404) {
          print('❌ [FCM] Token API endpoint not found (404)');
        } else {
          print('❌ [FCM] Token auto-registration HTTP error: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e, stackTrace) {
      print('❌ [FCM] autoRegisterTokenOnAppOpen error: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Set up token refresh listener to automatically update database when FCM token changes
  /// This ensures the database is always up-to-date even if Firebase refreshes the token
  void _setupTokenRefreshListener() {
    if (_messaging == null) {
      return;
    }
    
    try {
      // Listen for token refresh events
      _messaging!.onTokenRefresh.listen((String newToken) async {
        _logChat('FCM Token Refresh', '🔄 FCM token refreshed by Firebase');
        _logChat('FCM Token Refresh', '   Old token: ${_fcmToken?.substring(0, 20) ?? 'null'}...');
        _logChat('FCM Token Refresh', '   New token: ${newToken.substring(0, 20)}...');
        
        // Update local token
        _fcmToken = newToken;
        await _storeFCMTokenLocally();
        
        // Check if user is logged in and update database
        await _initPrefs();
        String? userIdString = _prefs?.getString('userID') ?? _prefs?.getString(StorageKeys.userId);
        int? userId;
        
        if (userIdString != null && userIdString.isNotEmpty) {
          userId = int.tryParse(userIdString);
        }
        
        // If user ID not found, try user profile
        if ((userId == null || userId == 0)) {
          try {
            final user = await _authService.getStoredUserProfile();
            if (user != null && user.id.isNotEmpty) {
              final parsedUserId = int.tryParse(user.id);
              if (parsedUserId != null && parsedUserId > 0) {
                userId = parsedUserId;
              }
            }
          } catch (e) {
            // Silently fail
          }
        }
        
        // Update database - register anonymously if user not logged in, or with user ID if logged in
        if (userId != null && userId > 0) {
          _logChat('FCM Token Refresh', '✅ User logged in (ID: $userId) - updating database');
          try {
            await sendFCMTokenToServer(userId: userId);
            _logChat('FCM Token Refresh', '✅ FCM token updated in database after refresh');
          } catch (e) {
            _logChat('FCM Token Refresh', '❌ Failed to update FCM token in database: $e');
          }
        } else {
          _logChat('FCM Token Refresh', '⚠️ User not logged in - registering token anonymously');
          try {
            await registerFCMTokenAnonymously();
            _logChat('FCM Token Refresh', '✅ FCM token updated in database (anonymous) after refresh');
          } catch (e) {
            _logChat('FCM Token Refresh', '❌ Failed to update FCM token in database: $e');
          }
        }
      });
      
      _logChat('FCM Init', '✅ Token refresh listener registered');
    } catch (e) {
      _logChat('FCM Init', '⚠️ Failed to set up token refresh listener: $e');
    }
  }
}
