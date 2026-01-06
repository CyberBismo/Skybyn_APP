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
  // Use developer.log for tracing chat events
  developer.log(message, name: prefix);
  // Also print to console with [SKYBYN] prefix so it bypasses the Zone filter in main.dart
  print('[SKYBYN] [$prefix] $message');
}

// Handle background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Log basic info about incoming Firebase background message
    final type = message.data['type']?.toString();
    developer.log('📨 Background message: ID=${message.messageId}, Type=$type', name: 'FCM Background');
    
    // Process all messages, including in debug mode (for testing)
    // Debug mode check removed to ensure notifications work during development

    // Check if Firebase is already initialized
    // Gracefully handle Firebase unavailability
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      // Firebase is unavailable - log but continue
      developer.log('⚠️ [FCM Background] Firebase Core unavailable: $e', name: 'FCM Background Handler');
      developer.log('⚠️ [FCM Background] App will continue to function normally', name: 'FCM Background Handler');
      // Continue - notification may still be shown by system
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
      developer.log('⚠️ [FCM Background] NotificationService initialization failed: $e', name: 'FCM Background Handler');
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
      // - If notification has 'notification' field: FCM will show it automatically, don't show duplicate
      // - If notification is data-only: Show local notification to ensure it's displayed
      // 
      // Only show local notification if FCM won't show it automatically (data-only messages)
      final hasNotificationPayload = message.notification != null && 
                                     message.notification!.title != null && 
                                     message.notification!.title!.isNotEmpty;
      
      // For chat messages, always show local notification to ensure it's displayed
      // This is critical for background and terminated app states
      if (type == 'chat') {
        try {
          await notificationService.showNotification(
            title: title, 
            body: body, 
            payload: payload
          );
          _logChat('FCM Background Chat', 'Local notification shown for chat message (ensuring delivery)');
        } catch (e) {
          _logChat('FCM Background Chat', 'Failed to show local notification: $e');
          // Don't rethrow - log the error but continue execution
        }
      } else if (!hasNotificationPayload) {
        // For other types, only show local notification if it's data-only
        try {
          await notificationService.showNotification(
            title: title, 
            body: body, 
            payload: payload
          );
          if (type == 'chat') {
            _logChat('FCM Background Chat', 'Local notification shown (data-only message)');
          }
        } catch (e) {
          if (type == 'chat') {
            _logChat('FCM Background Chat', 'Failed to show local notification: $e');
          }
          // Don't rethrow - log the error but continue execution
        }
      } else {
        // Notification has 'notification' field - FCM should show it automatically
        // For non-chat messages, we can rely on FCM's automatic display
        if (type == 'chat') {
          _logChat('FCM Background Chat', 'FCM should show notification automatically (has notification payload)');
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
  
  // Keys for storing registration state
  static const String _lastRegisteredVersionKey = 'fcm_last_registered_version';
  static const String _lastRegisteredTokenKey = 'fcm_last_registered_token';
  static const String _lastRegisteredUserKey = 'fcm_last_registered_user';

  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> initialize() async {
    _logChat('FCM Init', '🚀 initialize() called');
    // Prevent duplicate initialization
    if (_isInitialized) {
      _logChat('FCM Init', 'Already initialized, skipping');
      return;
    }
    
    try {
      // Ensure Firebase Core is initialized first
      if (Firebase.apps.isEmpty) {
        // Try to initialize Firebase Core if not already done
        try {
          await Firebase.initializeApp();
          _logChat('FCM Init', '✅ Firebase Core initialized');
        } catch (e) {
          _logChat('FCM Init', '⚠️ Firebase Core initialization failed: $e');
          _logChat('FCM Init', '⚠️ App will continue without push notifications');
          _messaging = null;
          _isInitialized = false;
          return; // Exit gracefully - app will work without Firebase
        }
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
          _logChat('FCM Init', '⚠️ Firebase Messaging unavailable on iOS: $e');
          _logChat('FCM Init', '⚠️ App will continue without push notifications');
          return; // Exit gracefully - app will work without Firebase
        }
      } else {
        // Android - initialize normally with error handling
        try {
          _messaging = FirebaseMessaging.instance;
        } catch (e) {
          _messaging = null;
          _isInitialized = false;
          _logChat('FCM Init', '⚠️ Firebase Messaging unavailable: $e');
          _logChat('FCM Init', '⚠️ App will continue without push notifications');
          return; // Exit gracefully - app will work without Firebase
        }
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

      // Don't request permissions here - they will be requested after login
      // This prevents asking for permissions before user is logged in
      // Permissions will be requested via requestPermissions() method after login

      // Get FCM token (gracefully handles Firebase Installations Service unavailability)
      // This will fail on iOS if APN is not configured, or if Firebase Installations Service is unavailable
      try {
        await _getFCMToken();
      } catch (e) {
        // FCM token retrieval failure is non-critical - app can still function
        _logChat('FCM Init', '⚠️ FCM token retrieval failed: $e');
        _logChat('FCM Init', '⚠️ App will continue without FCM token (push notifications unavailable)');
        // Don't rethrow - continue initialization
      }

      // Note: FCM token registration requires a logged-in user
      // Token registration will happen after login via sendFCMTokenToServer()
      // Also check and update token if app version changed

      // Set up message handlers
      await _setupMessageHandlers();
      
      // Check if app version changed and update FCM token if needed
      try {
        await _checkAndUpdateTokenAfterAppUpdate();
      } catch (e) {
        // Token update check failure is non-critical
        _logChat('FCM Init', '⚠️ Token update check failed: $e');
      }

      // Auto-subscribe to default topics (gracefully handles Firebase unavailability)
      try {
        await autoSubscribeToTopics();
      } catch (e) {
        // Topic subscription failures are non-critical - log and continue
        _logChat('FCM Init', '⚠️ Topic subscription failed: $e');
        _logChat('FCM Init', '⚠️ App will continue without topic subscriptions');
      }
      
      // Mark as initialized only after everything succeeds
      _isInitialized = true;
      _logChat('FCM Init', '✅ Firebase Messaging initialized successfully');
    } catch (e, stackTrace) {
      // Firebase is unavailable - log error but don't crash the app
      _logChat('FCM Init', '⚠️ Firebase Messaging initialization failed: $e');
      _logChat('FCM Init', '⚠️ App will continue to function normally without push notifications');
      // Reset messaging instance on failure
      _messaging = null;
      _isInitialized = false;
      // Don't rethrow - allow app to continue without Firebase
    }
  }

  /// Request notification permissions (public method to be called after login)
  Future<void> requestPermissions() async {
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    try {
      if (_messaging == null) {
        return;
      }
      
      // Permissions are optional; we log the attempt but do not block functionality.
      _logChat('FCM Permissions', '⚠️ Skipping permission request to keep app functional without permissions');
      // Directly attempt to get FCM token without requesting permissions.
      try {
        await _getFCMToken();
      } catch (e) {
        _logChat('FCM Permissions', '⚠️ Failed to get FCM token without permission request: $e');
      }
    } catch (e) {
      _logChat('FCM Permissions', '❌ Error requesting permissions: $e');
    }
  }

  Future<void> _getFCMToken() async {
    _logChat('FCM Token', '🚀 _getFCMToken calling...');
    try {
      if (_messaging == null) {
        _logChat('FCM Token', '⚠️ _messaging is null, aborting');
        return;
      }
      
      _fcmToken = await _messaging!.getToken();
      
      if (_fcmToken != null) {
        _logChat('FCM Token', '✅ FCM token retrieved successfully');
        _logChat('FCM Token', '🔥 FCM TOKEN: $_fcmToken'); // Log token for debugging
        // After retrieving token, check device status on server
        // This is lighter than full registration and updates timestamps/user association
        await _checkDeviceOnServer();
        // Also check if app version changed and update if needed
        await _checkAndUpdateTokenAfterAppUpdate();
      } else {
        _logChat('FCM Token', '⚠️ FCM token is null');
      }

      // Store token locally (not in Firestore)
      await _storeFCMTokenLocally();
    } catch (e) {
      // Firebase Installations Service (FIS) errors are common when Firebase is unavailable
      // Check if it's a FIS error specifically
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('firebase installations') || 
          errorStr.contains('fis_auth_error') ||
          errorStr.contains('installations service is unavailable')) {
        _logChat('FCM Token', '⚠️ Firebase Installations Service unavailable: $e');
        _logChat('FCM Token', '⚠️ App will continue without push notifications');
      } else {
        _logChat('FCM Token', '⚠️ Failed to get FCM token: $e');
      }
      _fcmToken = null;
      // Don't rethrow - allow app to continue without FCM token
    }
  }

  // Removed _registerTokenOnAppStart() - FCM token registration now requires a logged-in user
  // Devices are registered via sendFCMTokenToServer() after login

  /// Send FCM token to server to register in devices table (with user ID)
  /// Also updates the stored app version after successful registration
  /// Gracefully handles Firebase unavailability - app continues to work without push notifications
  Future<void> sendFCMTokenToServer({bool force = false}) async {
    try {
      // Check if Firebase is available
      // Note: We don't check _isInitialized here because this might be called DURING initialization (via _checkDeviceOnServer)
      if (_messaging == null) {
        print('⚠️ [FCM] Firebase Messaging not available - skipping token registration');
        print('⚠️ [FCM] App will continue to function normally without push notifications');
        return; // Exit gracefully
      }
      
      if (_fcmToken == null) {
        print('⚠️ [FCM] Cannot register token: FCM token is null');
        return;
      }

      // Get user ID - try from SharedPreferences first (faster, available immediately after login)
      // Then fall back to user profile if needed
      await _initPrefs();
      // Before sending token, log version comparison
      await _logVersionComparison();
      // Try both 'userID' (from login response) and 'user_id' (from StorageKeys)
      String? userIdString = _prefs?.getString('userID') ?? _prefs?.getString(StorageKeys.userId);
      int? userId;
      
      if (userIdString != null && userIdString.isNotEmpty) {
        userId = int.tryParse(userIdString);
        if (userId != null && userId > 0) {
          _logChat('FCM Register', '📱 Got user ID from SharedPreferences: $userId');
          // Log version info when registering token
          await _logVersionComparison();
        } else {
          userId = null;
        }
      }
      
      // If not found in SharedPreferences, try to get from user profile (with retries)
      if (userId == null || userId == 0) {
        var user = await _authService.getStoredUserProfile();
        int retries = 0;
        const maxRetries = 5;
        const retryDelay = Duration(milliseconds: 500);
        
        while ((user == null || user.id.isEmpty || int.tryParse(user.id) == null || int.parse(user.id) == 0) && retries < maxRetries) {
          user = await _authService.getStoredUserProfile();
          if (user != null && user.id.isNotEmpty) {
            final parsedUserId = int.tryParse(user.id);
            if (parsedUserId != null && parsedUserId > 0) {
              userId = parsedUserId;
              _logChat('FCM Register', '📱 Got user ID from user profile: $userId');
              break;
            }
          }
          _logChat('FCM Register', '⚠️ User ID not available yet, retrying... (${retries + 1}/$maxRetries)');
          await Future.delayed(retryDelay);
          retries++;
        }
      }
      
      // Final check - user ID validation
      // Optimization: Allow registration with userId=0 (device-only registration)
      if (userId == null) {
        userId = 0;
        _logChat('FCM Register', '⚠️ User not logged in, registering device with User ID 0');
      }
      
      /* REMOVED: User ID enforcement
      if (userId == null || userId == 0) {
        _logChat('FCM Register', '❌ Cannot register token: User ID is invalid or not available (userId=$userId)');
        return;
      }
      */
      
      // Check if token already registered for this user
      final String? lastToken = _prefs?.getString(_lastRegisteredTokenKey);
      final String? lastUser = _prefs?.getString(_lastRegisteredUserKey);
      
      if (!force) {
        if (lastToken == _fcmToken && lastUser == userId.toString()) {
          _logChat('FCM Register', '📱 Token already registered for user $userId - skipping update');
          return;
        }
      } else {
        _logChat('FCM Register', '📱 Forcing token registration update (server requested)');
      }
      
      _logChat('FCM Register', '📱 Registering token for user ID: $userId');
      
      // Use device service to get device info
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();

      // Send to token API endpoint with user ID
      try {
        final requestBody = {
          'userID': userId.toString(),
          'fcmToken': _fcmToken!,
          'deviceId': deviceInfo['id'] ?? deviceInfo['deviceId'] ?? '',
          'platform': deviceInfo['platform'] ?? 'Unknown',
          'model': deviceInfo['model'] ?? 'Unknown'
        };
        
        _logChat('FCM Register', '📱 Sending token registration request...');
        _logChat('FCM Register', 'Request URL: ${ApiConstants.token}');
        _logChat('FCM Register', 'Request Body: userID=${requestBody['userID']}, deviceId=${requestBody['deviceId']}, platform=${requestBody['platform']}');
        
        final response = await http.post(
          Uri.parse(ApiConstants.token),
          body: requestBody
        );

        _logChat('FCM Register', '📱 Token registration response: statusCode=${response.statusCode}, body=${response.body}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1' || data['responseCode'] == 1) {
            _logChat('FCM Register', '✅ Token registered successfully for user $userId');
            
            // Update stored registration state after successful registration
            try {
              await _initPrefs();
              await _prefs?.setString(_lastRegisteredTokenKey, _fcmToken!);
              await _prefs?.setString(_lastRegisteredUserKey, userId.toString());
              
              final PackageInfo packageInfo = await PackageInfo.fromPlatform();
              final String currentVersion = packageInfo.buildNumber.isNotEmpty ? packageInfo.buildNumber : packageInfo.version;
              await _prefs?.setString(_lastRegisteredVersionKey, currentVersion);
              _logChat('FCM Register', '📱 Updated stored registration state (token, user, version: $currentVersion)');
            } catch (e) {
              _logChat('FCM Register', '⚠️ Failed to update stored registration state: $e');
            }
          } else {
            _logChat('FCM Register', '❌ Token registration failed: ${data['message'] ?? 'Unknown error'}');
          }
        } else {
          _logChat('FCM Register', '❌ Token registration HTTP error: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        _logChat('FCM Register', '⚠️ Token registration exception: $e');
        _logChat('FCM Register', '⚠️ App will continue to function normally without push notifications');
        // Don't rethrow - allow app to continue without Firebase token registration
      }
    } catch (e) {
      _logChat('FCM Register', '⚠️ sendFCMTokenToServer error: $e');
      _logChat('FCM Register', '⚠️ App will continue to function normally without push notifications');
      // Don't rethrow - allow app to continue without Firebase token registration
    }
  }

  /// Check device status with lightweight API check
  Future<void> _checkDeviceOnServer() async {
    try {
      if (_fcmToken == null) return;
      
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();
      final deviceId = deviceInfo['id'] ?? deviceInfo['deviceId'] ?? '';
      
      if (deviceId.isEmpty) return;
      
      await _initPrefs();
      String? userIdString = _prefs?.getString('userID') ?? _prefs?.getString(StorageKeys.userId);
      int? userId;
      
      if (userIdString != null && userIdString.isNotEmpty) {
        userId = int.tryParse(userIdString);
      }
      
      // If no user ID, try to get from profile like in registration
      if (userId == null || userId == 0) {
        var user = await _authService.getStoredUserProfile();
        if (user != null && user.id.isNotEmpty) {
           userId = int.tryParse(user.id);
        }
      }
      
      _logChat('FCM Check', 'checking device status on server...');
      _logChat('FCM Check', 'Request URL: ${ApiConstants.checkDevice}');
      _logChat('FCM Check', 'Request Body: deviceId=$deviceId, fcm_token=${_fcmToken!.substring(0, 10)}..., user=${userId?.toString() ?? '0'}');
      
      final response = await http.post(
        Uri.parse(ApiConstants.checkDevice),
        body: {
          'deviceId': deviceId,
          'fcm_token': _fcmToken!,
          'user': userId?.toString() ?? '0'
        }
      );
      
      _logChat('FCM Check', 'Response Status: ${response.statusCode}');
      _logChat('FCM Check', 'Response Body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' || data['responseCode'] == 1) {
           _logChat('FCM Check', '✅ Device check/update successful (lightweight)');
        } else {
           _logChat('FCM Check', '⚠️ Device check returned: ${data['message']} - Triggering full registration');
           // If check fails (e.g. device doesn't exist in JSON/DB yet), do full registration
           // Force update because local prefs might think we are registered but server says no
           await sendFCMTokenToServer(force: true);
        }
      } else {
         _logChat('FCM Check', '⚠️ Server error during check: ${response.statusCode}');
      }
    } catch (e) {
      _logChat('FCM Check', '⚠️ Error checking device: $e');
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
      final authService = AuthService();
      await authService.updateActivity();
      
      // For app_update notifications in foreground, ignore Firebase notification
      // WebSocket will handle real-time delivery when app is in focus
      if (type == 'app_update') {
        // Don't show notification here - WebSocket will handle it to avoid duplicates
        // Just trigger the update check callback
        _triggerUpdateCheck();
        return;
      }
      
      // For chat messages in foreground, log details
      if (type == 'chat') {
        final sender = message.data['sender']?.toString() ?? message.data['from']?.toString() ?? 'unknown';
        final messageId = message.data['messageId']?.toString() ?? 'unknown';
        final title = message.notification?.title ?? 'New Message';
        final body = message.notification?.body ?? '';
        _logChat('FCM Foreground Chat', 'Chat message received:');
        _logChat('FCM Foreground Chat', '   - Sender: $sender');
        _logChat('FCM Foreground Chat', '   - MessageId: $messageId');
        _logChat('FCM Foreground Chat', '   - Title: $title');
        _logChat('FCM Foreground Chat', '   - Body: ${body.length > 50 ? body.substring(0, 50) + "..." : body}');
        _logChat('FCM Foreground Chat', '   - Full data: ${message.data}');
      }
      
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
      final isAppInForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (isAppInForeground) {
        // App is in foreground - show in-app notification only, not system notification
        if (type == 'chat') {
          // For chat messages, use the in-app notification service
          final sender = message.data['sender']?.toString() ?? message.data['from']?.toString() ?? '';
          final messageText = message.notification?.body ?? message.data['message']?.toString() ?? '';
          
          // Check if chat screen is in focus - if so, don't show notification
          final inAppNotificationService = InAppNotificationService();
          if (inAppNotificationService.isChatScreenInFocus(sender)) {
            _logChat('FCM Foreground Chat', 'Chat screen is in focus, skipping notification');
            return;
          }
          
          // Get friend info and show in-app notification
          try {
            final authService = AuthService();
            final currentUserId = await authService.getStoredUserId();
            if (currentUserId != null) {
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
              
              inAppNotificationService.showChatNotification(
                friend: friend,
                message: messageText,
                onTap: () {
                  final nav = navigatorKey.currentState;
                  if (nav != null) {
                    nav.pushNamed('/chat', arguments: {'friend': friend});
                  }
                },
              );
              _logChat('FCM Foreground Chat', '✅ In-app notification shown successfully');
            }
          } catch (e) {
            _logChat('FCM Foreground Chat', '❌ Failed to show in-app notification: $e');
          }
        } else {
          // For other types, show in-app notification
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
    });

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final type = message.data['type']?.toString();
      _logChat('FCM Opened App', '📱 App opened from notification: type=$type, messageId=${message.messageId}');
      _logChat('FCM Opened App', '   Full data: ${message.data}');
      // Handle navigation based on message data
      _handleNotificationTap(message.data);
    });

    // Check if app was opened from notification
    RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
    if (initialMessage != null) {
      final type = initialMessage.data['type']?.toString();
      _logChat('FCM Initial Message', '📱 App opened from initial notification: type=$type, messageId=${initialMessage.messageId}');
      _logChat('FCM Initial Message', '   Full data: ${initialMessage.data}');
      await _handleNotificationTap(initialMessage.data);
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

      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        return;
      }

      // Store token locally using SharedPreferences
      await _initPrefs();
      final existingToken = _prefs?.getString('fcm_token');
      final isNewToken = existingToken != _fcmToken;
      
      await _prefs?.setString('fcm_token', _fcmToken!);
      
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
  /// Returns false if subscription fails (e.g., Firebase unavailable)
  Future<bool> subscribeToTopic(String topic) async {
    try {
      if (_messaging == null) {
        _logChat('FCM Topic', '⚠️ Cannot subscribe to topic "$topic": Firebase Messaging not initialized');
        return false;
      }
      
      await _messaging!.subscribeToTopic(topic);
      if (!_subscribedTopics.contains(topic)) {
        _subscribedTopics.add(topic);
      }
      _logChat('FCM Topic', '✅ Subscribed to topic: $topic');
      return true;
    } catch (e) {
      // Check if it's a Firebase Installations Service (FIS) error
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('firebase installations') || 
          errorStr.contains('fis_auth_error') ||
          errorStr.contains('installations service is unavailable') ||
          errorStr.contains('failed to sync topics')) {
        _logChat('FCM Topic', '⚠️ Firebase Installations Service unavailable - cannot subscribe to topic "$topic"');
        _logChat('FCM Topic', '⚠️ App will continue without topic subscriptions');
      } else {
        _logChat('FCM Topic', '⚠️ Failed to subscribe to topic "$topic": $e');
      }
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
  /// Gracefully handles Firebase unavailability
  Future<void> autoSubscribeToTopics() async {
    try {
      if (!_isInitialized || _messaging == null) {
        _logChat('FCM Topics', '⚠️ Firebase Messaging not available - skipping topic subscriptions');
        return;
      }
      
      // Default topics for all users
      final defaultTopics = [
        'all', // All users
        'app_updates', // App update notifications
        'general', // General announcements
      ];
      
      int successCount = 0;
      int failCount = 0;
      
      for (final topic in defaultTopics) {
        final success = await subscribeToTopic(topic);
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
        // Small delay to avoid overwhelming the service
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (failCount > 0) {
        _logChat('FCM Topics', '⚠️ Failed to subscribe to $failCount/$defaultTopics.length topics (Firebase may be unavailable)');
      } else {
        _logChat('FCM Topics', '✅ Successfully subscribed to all default topics');
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('firebase installations') || 
          errorStr.contains('fis_auth_error') ||
          errorStr.contains('installations service is unavailable')) {
        _logChat('FCM Topics', '⚠️ Firebase Installations Service unavailable - skipping topic subscriptions');
        _logChat('FCM Topics', '⚠️ App will continue without topic subscriptions');
      } else {
        _logChat('FCM Topics', '⚠️ Error subscribing to default topics: $e');
      }
      // Don't rethrow - allow app to continue without topic subscriptions
    }
  }

  /// Try to register FCM token after login
  Future<void> tryRegisterFCMTokenAfterLogin() async {
    // Deprecated: FCM token is now sent via profile API
    // Kept for backward compatibility
  }

  /// Subscribe to user-specific topics based on user data
  /// Gracefully handles Firebase unavailability
  Future<void> subscribeToUserTopics() async {
    try {
      if (!_isInitialized || _messaging == null) {
        _logChat('FCM User Topics', '⚠️ Firebase Messaging not available - skipping user topic subscriptions');
        return;
      }
      
      final user = await _authService.getStoredUserProfile();
      if (user == null) {
        _logChat('FCM User Topics', '⚠️ User not logged in - skipping user topic subscriptions');
        return;
      }

      // User-specific topics
      final userTopics = [
        'user_${user.id}', // User-specific notifications
        'rank_${user.rank}', // Rank-based notifications
        'status_${user.online}', // Online status notifications
      ];
      
      int successCount = 0;
      int failCount = 0;
      
      for (final topic in userTopics) {
        final success = await subscribeToTopic(topic);
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (failCount > 0) {
        _logChat('FCM User Topics', '⚠️ Failed to subscribe to $failCount/${userTopics.length} user topics (Firebase may be unavailable)');
      } else {
        _logChat('FCM User Topics', '✅ Successfully subscribed to all user topics');
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('firebase installations') || 
          errorStr.contains('fis_auth_error') ||
          errorStr.contains('installations service is unavailable')) {
        _logChat('FCM User Topics', '⚠️ Firebase Installations Service unavailable - skipping user topic subscriptions');
        _logChat('FCM User Topics', '⚠️ App will continue without user topic subscriptions');
      } else {
        _logChat('FCM User Topics', '⚠️ Error subscribing to user topics: $e');
      }
      // Don't rethrow - allow app to continue without topic subscriptions
    }
  }

  /// Get list of subscribed topics
  List<String> get subscribedTopics => List.from(_subscribedTopics);

  /// Check if subscribed to a specific topic
  bool isSubscribedToTopic(String topic) => _subscribedTopics.contains(topic);

  // Helper to log version comparison before token registration
  Future<void> _logVersionComparison() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.buildNumber.isNotEmpty ? packageInfo.buildNumber : packageInfo.version;
      final String? storedVersion = _prefs?.getString(_lastRegisteredVersionKey);
      _logChat('FCM Version', 'Current app version: $currentVersion, stored version: ${storedVersion ?? "none"}');
    } catch (e) {
      _logChat('FCM Version', '⚠️ Failed to retrieve app version for logging: $e');
    }
  }

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
         _logChat('FCM Version', 'App version changed from ${lastRegisteredVersion ?? 'unknown'} to $currentVersion - updating FCM token');
         
         // Trigger registration (will handle user=0 if not logged in)
         await sendFCMTokenToServer();
         
         // Note: sendFCMTokenToServer updates the stored version on success
      } else {
        _logChat('FCM Version', 'App version unchanged ($currentVersion) - FCM token up to date');
      }
    } catch (e) {
      _logChat('FCM Version', '❌ Error checking app version for FCM token update: $e');
      // Don't throw - this is a background check
    }
  }

  /// Auto-register FCM token when app opens (with user ID)
  Future<void> autoRegisterTokenOnAppOpen() async {
    try {
      // Check if FCM service is initialized
      if (!_isInitialized) {
        _logChat('FCM AutoRegister', '⚠️ Cannot auto-register token: FCM service not initialized');
        return;
      }

      // Token was already retrieved during initialize(), just send it to server
      if (_fcmToken == null) {
        // If for some reason we don't have a token, try to get it once more
        await _getFCMToken();
        
        if (_fcmToken == null) {
          _logChat('FCM AutoRegister', '⚠️ Cannot auto-register token: FCM token is null');
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
          _logChat('FCM AutoRegister', '📱 Auto-registering token for user ID (from SharedPreferences): $userId');
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
            _logChat('FCM AutoRegister', '📱 Auto-registering token for user ID (from profile): $userId');
          }
        }
      }

      // Final check - user ID must be valid (not null, not 0)
      if (userId == null || userId == 0) {
        _logChat('FCM AutoRegister', '⚠️ Cannot auto-register token: User ID is invalid or user not logged in (userId=$userId)');
        return;
      }
      
      // Check if already registered
      final String? lastToken = _prefs?.getString(_lastRegisteredTokenKey);
      final String? lastUser = _prefs?.getString(_lastRegisteredUserKey);
      
      if (lastToken == _fcmToken && lastUser == userId.toString()) {
        _logChat('FCM AutoRegister', '📱 Token already registered for user $userId (auto-register) - skipping');
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
      
      _logChat('FCM AutoRegister', 'Sending auto-registration request for ${requestBody['userID']}, deviceId=${requestBody['deviceId']}');
      
      // Send the token to the token API endpoint
      final response = await http.post(
        Uri.parse(ApiConstants.token),
        body: requestBody,
      );

      _logChat('FCM AutoRegister', '📱 Auto-registration response: statusCode=${response.statusCode}, body=${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1' || data['responseCode'] == 1) {
            _logChat('FCM AutoRegister', '✅ Token auto-registered successfully for user $userId');
            
            // Update stored registration state
            await _prefs?.setString(_lastRegisteredTokenKey, _fcmToken!);
            await _prefs?.setString(_lastRegisteredUserKey, userId.toString());
          } else {
            _logChat('FCM AutoRegister', '❌ Token auto-registration failed: ${data['message'] ?? 'Unknown error'}');
          }
        } catch (e) {
          _logChat('FCM AutoRegister', '❌ Failed to parse auto-registration response: $e');
        }
      } else {
        if (response.statusCode == 404) {
          _logChat('FCM AutoRegister', '❌ Token API endpoint not found (404)');
        } else {
          _logChat('FCM AutoRegister', '❌ Token auto-registration HTTP error: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e, stackTrace) {
      _logChat('FCM AutoRegister', '❌ autoRegisterTokenOnAppOpen error: $e');
      _logChat('FCM AutoRegister', 'Stack trace: $stackTrace');
    }
  }
}
