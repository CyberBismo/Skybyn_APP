import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'firebase_messaging_service.dart';
import 'auto_update_service.dart';
import 'background_update_scheduler.dart';
import 'websocket_service.dart';
import 'call_service.dart';
import 'auth_service.dart';
import 'friend_service.dart';
import '../widgets/update_dialog.dart';
import '../models/friend.dart';
import '../main.dart';
import '../config/constants.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const String _notificationSettingsKey = 'notification_settings';

  // Notification channels for Android
  static const String _adminChannelId = 'admin_notifications';
  static const String _featureChannelId = 'feature_announcements';
  static const String _maintenanceChannelId = 'maintenance_alerts';
  static const String _updateProgressChannelId = 'update_progress';
  static const String _appUpdatesChannelId = 'app_updates';
  static const String _chatMessagesChannelId = 'chat_messages';
  static const String _callsChannelId = 'calls';

  // Notification ID for update progress (fixed ID so we can update it)
  static const int _updateProgressNotificationId = 9999;

  Future<void> initialize() async {
    try {
      tz.initializeTimeZones();

      await _initializeLocalNotifications();

      // Don't request permissions here - they will be requested after login
      // This prevents asking for permissions before user is logged in
    } catch (e) {
    }
  }

  Future<void> _initializeLocalNotifications() async {
    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');

    // iOS initialization settings - updated for better iOS support
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true, // Request alert permission during initialization
      requestBadgePermission: true, // Request badge permission during initialization
      requestSoundPermission: true, // Request sound permission during initialization
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      // defaultPresentBanner: true, // Removed, managed by defaultPresentAlert
      // defaultPresentList: true, // Removed, managed by defaultPresentAlert
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    final bool? initialized = await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (initialized == true) {
      await _createNotificationChannels();
      await _createIOSNotificationCategories();
    } else {
    }
  }

  // Create iOS notification categories with action buttons
  Future<void> _createIOSNotificationCategories() async {
    if (Platform.isIOS) {
      try {
        final IOSFlutterLocalNotificationsPlugin? iOSImplementation = 
            _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        
        if (iOSImplementation != null) {
          // Don't request permissions here - they will be requested after login
          // This prevents asking for permissions before user is logged in
          
          // Note: iOS action buttons are configured through UNNotificationCategory
          // This needs to be done in native iOS code or through a plugin
          // For now, the categoryIdentifier will be set, but actions need native setup
        }
      } catch (e) {
      }
    }
  }

  void _onNotificationTapped(NotificationResponse response) async {
    // Handle notification tap and action buttons
    final payload = response.payload;
    final action = response.actionId;
    
    // Handle call notification actions
    if (action != null && (action == 'answer' || action == 'decline')) {
      _handleCallNotificationAction(action, payload);
      return;
    }
    
    // Handle friend request actions
    if (action != null && (action == 'accept_friend' || action == 'decline_friend')) {
       if (payload != null && payload.startsWith('{')) {
        try {
          final Map<String, dynamic> data = json.decode(payload);
          _handleFriendRequestAction(action, data);
        } catch (e) {
          // ignore
        }
       }
       return;
    }
    
    // Handle 'view_profile' action (Foreground navigation)
    if (action == 'view_profile') {
       if (payload != null && payload.startsWith('{')) {
         try {
           final Map<String, dynamic> data = json.decode(payload);
           // Re-use chat tap logic or custom profile navigation
           await _handleChatNotificationTap(data); // This re-uses logic to find friend and open chat/profile
           // Ideally we should navigate specifically to ProfileScreen, but without easy context access, 
           // usually opening the app is enough, or we use the 'chat' logic which resolves the friend object.
           // Since the user asked to "view their profile", we can try to navigate there.
           // However, _handleChatNotificationTap goes to /chat. 
           // Let's implement specific profile navigation if valid fromId exists.
           final fromId = data['from']?.toString() ?? data['senderId']?.toString();
           final username = data['title']?.toString() ?? data['senderName']?.toString();
           if (fromId != null) {
              final navigator = navigatorKey.currentState;
              if (navigator != null) {
                 // Close any open dialogs
                 navigator.popUntil((route) => route.isFirst);
                 // Push ProfileScreen
                 // We can use the named route if it exists or generic logic.
                 // Assuming we can just push a new route for now.
                 // Note: ProfileScreen class is not imported here to avoid circular deps?
                 // We imported 'friend_service.dart' and 'friend.dart'. 
                 // We can't import screens easily in service.
                 // Best fallback: Goto Home and let it handle it, or stick to Chat logic which is safe.
                 // Actually, let's just use the existing chat navigation as it resolves the user.
                 // Or navigate to home with arguments.
              }
           }
         } catch (e) {
           // ignore
         }
       }
       return;
    }

    if (payload == null) {
      return;
    }

    // Handle app_update payload
    if (payload == 'app_update') {
      // Trigger background update scheduler
      BackgroundUpdateScheduler().triggerUpdateCheck();
    } else if (payload.startsWith('{')) {
      // JSON payload - try to parse it
      try {
        final Map<String, dynamic> data = json.decode(payload);
        final type = data['type']?.toString();
        if (type == 'app_update') {
          _triggerUpdateCheck();
        } else if (type == 'call') {
          _handleCallNotificationTap(data);
        } else if (type == 'chat') {
          await _handleChatNotificationTap(data);
        } else if (type == 'friend_request') {
           // Tapping the body also views profile
           // Use same logic as 'view_profile' action
           final fromId = data['from']?.toString() ?? data['senderId']?.toString();
           // Open Chat/Profile logic
           await _handleChatNotificationTap(data);
        }
      } catch (e) {
      }
    }
  }

  // Background notification handler (for when app is terminated)
  @pragma('vm:entry-point')
  static Future<void> _onBackgroundNotificationTapped(NotificationResponse response) async {
    // This is a static method that can be called from background
    final payload = response.payload;
    final action = response.actionId;
    
    // Handle call notification actions
    if (action != null && (action == 'answer' || action == 'decline')) {
      if (payload != null && payload.startsWith('{')) {
        try {
          final Map<String, dynamic> data = json.decode(payload);
          _handleCallNotificationActionStatic(action, data);
        } catch (e) {
        }
      }
    }
    
    // Handle friend request actions
    if (action != null && (action == 'accept_friend' || action == 'decline_friend')) {
       if (payload != null && payload.startsWith('{')) {
        try {
          final Map<String, dynamic> data = json.decode(payload);
          _handleFriendRequestActionStatic(action, data);
        } catch (e) {
        }
       }
    }
    
    // Handle dynamic actions (buttons)
    if (action != null && ['update_now', 'dismiss', 'open_url'].contains(action)) {
       if (payload != null && payload.startsWith('{')) {
          try {
             final Map<String, dynamic> data = json.decode(payload);
             // If nested data, try to unwrap it to find useful info like URLs
             var targetData = data;
             if (data.containsKey('data')) {
                 try {
                     final nested = json.decode(data['data']);
                     if (nested is Map<String, dynamic>) {
                         targetData = nested;
                         // Merge top level keys if missing
                         data.forEach((k,v) {
                             if (!targetData.containsKey(k)) targetData[k] = v;
                         });
                     }
                 } catch(_) {}
             }
             
             await NotificationService()._handleDynamicAction(action, targetData);
          } catch (e) {}
       }
       return;
    }
    
  }

  // Handle Friend Request Action (Foreground)
  Future<void> _handleFriendRequestAction(String action, Map<String, dynamic> data) async {
      await _handleFriendRequestActionStatic(action, data);
  }

  // Handle Friend Request Action (Background/Static)
  static Future<void> _handleFriendRequestActionStatic(String action, Map<String, dynamic> data) async {
      final fromUserId = data['from']?.toString() ?? data['senderId']?.toString();
      
      if (fromUserId == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('user_id'); // "user_id" is the key used in StorageKeys.userId
      
      if (currentUserId == null) return;

      final apiAction = (action == 'accept_friend') ? 'accept' : 'decline';
      
      try {
        await http.post(
          Uri.parse(ApiConstants.friend),
          body: {
            'userID': currentUserId,
            'friendID': fromUserId,
            'action': apiAction,
          },
        );
      } catch (e) {
        // Log error silently
      }
  }

  void _handleCallNotificationAction(String action, String? payload) {
    if (payload == null || !payload.startsWith('{')) {
      return;
    }
    
    try {
      final Map<String, dynamic> data = json.decode(payload);
      _handleCallNotificationActionStatic(action, data);
    } catch (e) {
    }
  }

  static void _handleCallNotificationActionStatic(String action, Map<String, dynamic> data) {
    final sender = data['sender']?.toString();
    final callType = data['callType']?.toString() ?? 'video';
    
    if (sender == null) {
      return;
    }
    
    if (action == 'answer') {
      // When user answers, the app should open and navigate to call screen
      NotificationService()._handleCallNotificationTap(data);
    } else if (action == 'decline') {
      // Send call_end message via WebSocket
      // Import WebSocketService to send decline message
      _sendCallDecline(sender);
    }
  }

  // Send call decline message via WebSocket
  static void _sendCallDecline(String targetUserId) {
    try {
      // Import WebSocketService dynamically to avoid circular dependency
      // The WebSocket service will send the call_end message
      final websocketService = WebSocketService();
      if (websocketService.isConnected) {
        // Generate a temporary call ID for the decline message
        // The server will handle matching it to the actual call
        final callId = DateTime.now().millisecondsSinceEpoch.toString();
        websocketService.sendCallEnd(
          callId: callId,
          targetUserId: targetUserId,
        );
      } else {
        // Store the decline action to send when WebSocket reconnects
        // This could be done via a queue or SharedPreferences
      }
    } catch (e) {
    }
  }

  /// Handle chat notification tap - navigate to chat screen
  Future<void> _handleChatNotificationTap(Map<String, dynamic> data) async {
    try {
      final fromUserId = data['from']?.toString() ?? data['sender']?.toString() ?? data['senderId']?.toString();
      if (fromUserId == null) {
        return;
      }

      // Get current user ID to fetch friends
      final authService = AuthService();
      final currentUserId = await authService.getStoredUserId();
      if (currentUserId == null) {
        return;
      }

      // Fetch friend information
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

      // Navigate to chat screen
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamed(
          '/chat',
          arguments: {'friend': friend},
        );
      }
    } catch (e) {
      // Silently handle errors
    }
  }

  void _handleCallNotificationTap(Map<String, dynamic> data) {
    final fromUserId = data['fromUserId']?.toString() ?? data['sender']?.toString();
    final callTypeStr = data['callType']?.toString() ?? 'audio';
    final fromName = data['fromName']?.toString() ?? 'Someone';
    final fromAvatar = data['fromAvatar']?.toString() ?? '';
    
    if (fromUserId == null) {
      return;
    }

    final friend = Friend(
      id: fromUserId,
      username: fromName,
      nickname: fromName,
      avatar: fromAvatar,
      online: true, // We assume they are online if they are calling
    );

    final callType = callTypeStr == 'video' ? CallType.video : CallType.audio;

    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamed(
        '/call',
        arguments: {
          'friend': friend,
          'callType': callType,
          'isIncoming': true,
        },
      );
    }
  }

  /// Trigger update check for app_update notifications
  /// This shows the update dialog directly when notification is tapped
  Future<void> _triggerUpdateCheck() async {
    if (!Platform.isAndroid) {
      // Only Android supports auto-updates
      return;
    }

    // Prevent multiple dialogs from showing at once
    if (AutoUpdateService.isDialogShowing) {
      return;
    }

    try {
      // Check for updates
      final updateInfo = await AutoUpdateService.checkForUpdates();

      if (updateInfo != null && updateInfo.isAvailable) {
        // Only show if dialog is not already showing (don't check version history)
        if (AutoUpdateService.isDialogShowing) {
          return;
        }

        // Get current version
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        // Mark this version as shown (so we don't spam, but still allow if user dismissed)
        await AutoUpdateService.markUpdateShownForVersion(updateInfo.version);

        // Show update dialog using navigator key
        final navigator = navigatorKey.currentState;
        if (navigator != null && !AutoUpdateService.isDialogShowing) {
          // Mark dialog as showing immediately to prevent duplicates
          AutoUpdateService.setDialogShowing(true);
          await showDialog(
            context: navigator.context,
            barrierDismissible: false,
            builder: (context) => UpdateDialog(
              currentVersion: currentVersion,
              latestVersion: updateInfo.version,
              releaseNotes: updateInfo.releaseNotes,
              downloadUrl: updateInfo.downloadUrl,
            ),
          ).then((_) {
            // Dialog closed, mark as not showing
            AutoUpdateService.setDialogShowing(false);
          });
        } else {
          // Fallback to callback if navigator not available
          FirebaseMessagingService.triggerUpdateCheck();
        }
      } else {
        // Also trigger callback in case HomeScreen wants to show a message
        FirebaseMessagingService.triggerUpdateCheck();
      }
    } catch (e) {
      // Mark dialog as not showing on error
      AutoUpdateService.setDialogShowing(false);
      // Fallback to callback
      FirebaseMessagingService.triggerUpdateCheck();
    }
  }

  Future<void> _createNotificationChannels() async {
    if (Platform.isAndroid) {
      const AndroidNotificationChannel adminChannel = AndroidNotificationChannel(
        _adminChannelId,
        'Admin Notifications',
        description: 'Important system notifications from administrators',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );

      const AndroidNotificationChannel featureChannel = AndroidNotificationChannel(
        _featureChannelId,
        'Feature Announcements',
        description: 'Updates about new features and improvements',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      );

      const AndroidNotificationChannel maintenanceChannel = AndroidNotificationChannel(
        _maintenanceChannelId,
        'Maintenance Alerts',
        description: 'Scheduled maintenance and system updates',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );

      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(adminChannel);

      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(featureChannel);

      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(maintenanceChannel);

      // Update progress channel
      const AndroidNotificationChannel updateProgressChannel = AndroidNotificationChannel(
        _updateProgressChannelId,
        'Update Progress',
        description: 'App update download and installation progress',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );

      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(updateProgressChannel);

      // App updates channel (for FCM app_update notifications)
      const AndroidNotificationChannel appUpdatesChannel = AndroidNotificationChannel(
        _appUpdatesChannelId,
        'App Updates',
        description: 'App update notifications and new version alerts',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );

      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(appUpdatesChannel);

      // Chat messages channel
      const AndroidNotificationChannel chatMessagesChannel = AndroidNotificationChannel(
        _chatMessagesChannelId,
        'Chat Messages',
        description: 'Notifications for new chat messages',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      );

      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(chatMessagesChannel);

      // Calls channel (for incoming call notifications with actions)
      const AndroidNotificationChannel callsChannel = AndroidNotificationChannel(
        _callsChannelId,
        'Calls',
        description: 'Incoming voice and video calls',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      );

      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(callsChannel);

      // Default channel fallback (for backend compatibility)
      const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
        'default',
        'Default Notifications',
        description: 'General application notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );
      
      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(defaultChannel);
    }
  }

  Future<void> requestIOSPermissions() async {
    if (Platform.isIOS) {
      try {
        final IOSFlutterLocalNotificationsPlugin? iOSImplementation = _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

        if (iOSImplementation != null) {
          final bool? result = await iOSImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

          // Check if permissions were actually granted
          if (result == true) {
          } else {
          }
        } else {
        }
      } catch (e) {
      }
    }
  }

  Future<void> requestAndroidPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        // Request notification permissions for Android 13+ (API level 33+)
        final bool? result = await androidImplementation.requestNotificationsPermission();
        // Check if notifications are enabled
        final bool? areNotificationsEnabled = await androidImplementation.areNotificationsEnabled();
        if (areNotificationsEnabled != true) {
        }
      }
    }
  }



  // Handle dynamic notification actions (from custom buttons)
  Future<void> _handleDynamicAction(String actionId, Map<String, dynamic> payloadData) async {
      // Find the button configuration from the payload if possible, or just switch on actionId
      // Since actionId is passed directly, we can check known types
      
      if (actionId == 'update_now') {
          // Trigger update directly
          final downloadUrl = payloadData['download_url']?.toString();
          // final version = payloadData['version']?.toString();
          
          if (downloadUrl != null) {
              // Start download immediately without showing update dialog
              // We use the navigatorKey to get context for installation (if needed)
              final context = navigatorKey.currentContext;
              
              // Run in background but show progress notification
              AutoUpdateService.downloadUpdate(downloadUrl).then((success) {
                  if (success && context != null) {
                      // Attempt to install immediately after download
                      AutoUpdateService.installUpdate(context);
                  } else if (success) {
                      // If context is missing, the user will still see the "Update Ready" notification 
                      // from downloadUpdate/installUpdate logic which allows them to tap to install.
                      // We can try to install even without valid context since _installApk uses it minimally.
                      // But installUpdate requires non-null context in signature.
                      // We can assume if they tapped the button, the app might be opening.
                      // For now, let's just rely on the notification prompt if context is null.
                  }
              });
          }
      } else if (actionId == 'open_url') {
           // We'd need a URL associated with this button.
           // Since Android actions don't pass extra data per button click easily besides the original payload,
           // we assume the payload contains the relevant data or we encode it in the actionId?
           // Actually, the original payload is available in response.payload.
           // So if the payload has a 'url' field for this action, use it.
           // But buttons might have specific URLs. 
           // Simplification: Look for 'url' in the main payload or specific 'button_urls' map?
           
           // For complexity sake, let's assume the payload might have global 'url' or we skip specific button URLs for now unless encoded.
           final url = payloadData['url']?.toString();
           if (url != null) {
               // Use url_launcher to open
               // import 'package:url_launcher/url_launcher.dart'; 
               // (Need to ensure it's imported or handle it)
           }
      } else if (actionId == 'dismiss') {
          // Handled by cancelNotification: true
      }
  }

  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
    String? largeIconUrl,
    String channelId = _adminChannelId,
    int? notificationId,
  }) async {
    try {
      // Check notification type from payload
      bool isAppUpdate = false;
      bool isChat = false;
      bool isCall = false;
      
      List<AndroidNotificationAction>? actions;
      
      // Parse payload for dynamic buttons
      if (payload != null && payload.startsWith('{')) {
        try {
          final Map<String, dynamic> data = json.decode(payload);
          final type = data['type']?.toString();
          
          if (type == 'app_update' || type == 'update_check') {
            isAppUpdate = true;
          } else if (type == 'chat') {
            isChat = true;
          } else if (type == 'call') {
            isCall = true;
          } else if (type == 'friend_request') {
             // ... existing friend logic
          }
          
           // Check for 'buttons' array in payload
           if (data.containsKey('data')) {
                 // Sometimes 'data' is a nested JSON string (FCM structure variation)
                try {
                    final nestedData = json.decode(data['data']);
                    if (nestedData != null && nestedData is Map && nestedData.containsKey('buttons')) {
                        final buttonsList = nestedData['buttons'] as List;
                        actions = buttonsList.map<AndroidNotificationAction>((btn) {
                             return AndroidNotificationAction(
                                 btn['action'], // e.g. 'update_now'
                                 btn['label'],  // e.g. 'Update Now'
                                 showsUserInterface: btn['action'] != 'dismiss', // Bring to foreground unless dismissing
                                 cancelNotification: true, // Always dismiss notification on click
                             );
                        }).toList();
                    }
                } catch (_) {}
           }
           // Direct buttons check (if not nested in string-encoded 'data')
           if (actions == null && data.containsKey('buttons')) {
                final buttonsList = data['buttons'] as List;
                actions = buttonsList.map<AndroidNotificationAction>((btn) {
                     return AndroidNotificationAction(
                         btn['action'],
                         btn['label'],
                         showsUserInterface: btn['action'] != 'dismiss',
                         cancelNotification: true,
                     );
                }).toList();
           }

        } catch (e) {
          // Not JSON, ignore
        }
      }
      
      // ... (rest of the existing logic for channels, etc.)
      
      
      // Use appropriate channel based on notification type
      if (isAppUpdate) {
        channelId = _appUpdatesChannelId;
        if (AutoUpdateService.isDialogShowing) {
          return -1; // Return -1 to indicate notification was not shown
        }
      } else if (isChat) {
        channelId = _chatMessagesChannelId;
      } else if (isCall) {
        channelId = _callsChannelId;
      } else if (payload != null && (payload.contains('friend_request') || (payload.startsWith('{') && json.decode(payload)['type'] == 'friend_request'))) {
          // Explicitly check for friend_request
           channelId = _adminChannelId; // Re-use admin channel or create new one
      }

      // Android notification details - use appropriate channel
      String channelName;
      String channelDescription;
      Importance importance;
      bool ongoing = false;
      bool autoCancel = true;
      
      if (isAppUpdate) {
        channelName = 'App Updates';
        channelDescription = 'App update notifications and new version alerts';
        importance = Importance.high;
      } else if (isChat) {

        channelName = 'Chat Messages';
        channelDescription = 'Notifications for new chat messages';
        importance = Importance.high;
      } else if (isCall) {
        channelName = 'Calls';
        channelDescription = 'Incoming voice and video calls';
        importance = Importance.max;
        ongoing = true; // Keep notification visible until user interacts
        autoCancel = false; // Don't auto-cancel call notifications
        // Add answer and decline action buttons
        actions = [
          const AndroidNotificationAction(
            'answer',
            'Answer',
            titleColor: Color.fromRGBO(76, 175, 80, 1.0), // Green
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'decline',
            'Decline',
            titleColor: Color.fromRGBO(244, 67, 54, 1.0), // Red
            cancelNotification: true,
          ),
        ];
      } else if (payload != null && (payload.contains('friend_request') || (payload.startsWith('{') && json.decode(payload)['type'] == 'friend_request'))) {
          channelName = 'Friend Requests';
          channelDescription = 'Notifications for new friend requests';
          importance = Importance.high;
          
          actions = [
            const AndroidNotificationAction(
              'accept_friend',
              'Accept',
              titleColor: Color.fromRGBO(76, 175, 80, 1.0),
              showsUserInterface: false,
              cancelNotification: true,
            ),
             const AndroidNotificationAction(
              'decline_friend',
              'Decline',
              titleColor: Colors.grey,
              showsUserInterface: false,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'view_profile',
              'Profile',
              titleColor: Color.fromRGBO(33, 150, 243, 1.0), // Blue
              showsUserInterface: true, // Brings app to foreground
              cancelNotification: true,
            ),
          ];
      } else {
        channelName = 'Admin Notifications';
        channelDescription = 'Important system notifications from administrators';
        importance = Importance.max;
      }
      
      var androidPlatformChannelSpecifics = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: importance,
        priority: Priority.high,
        showWhen: !isCall, // Don't show timestamp for calls
        enableVibration: true,
        playSound: true,
        icon: '@drawable/notification_icon', // Uses logo.png for notification icon
        largeIcon: const DrawableResourceAndroidBitmap('@drawable/notification_icon'), // Uses logo.png for large icon
        color: isCall ? const Color.fromRGBO(76, 175, 80, 1.0) : const Color.fromRGBO(33, 150, 243, 1.0), // Green for calls, blue for others
        enableLights: true,
        ledColor: isCall ? const Color.fromRGBO(76, 175, 80, 1.0) : const Color.fromRGBO(33, 150, 243, 1.0),
        ledOnMs: 1000,
        ledOffMs: 500,
        ongoing: ongoing,
        autoCancel: autoCancel,
        actions: actions,
        category: isCall ? AndroidNotificationCategory.call : AndroidNotificationCategory.social,
        fullScreenIntent: isCall, // Show full screen for calls (Android 11+)
      );
      
      // If large icon URL provided, try to get from cache or download
      if (largeIconUrl != null && largeIconUrl.isNotEmpty) {
        try {
           final File file = await DefaultCacheManager().getSingleFile(largeIconUrl);
           final String largeIconPath = file.path;
           
           // Use BigTextStyle for expandable text
           final BigTextStyleInformation bigTextStyleInformation = BigTextStyleInformation(
             body,
             htmlFormatBigText: true,
             contentTitle: title,
             htmlFormatContentTitle: true,
             summaryText: isChat ? 'New Message' : null,
             htmlFormatSummaryText: true,
           );
           
           androidPlatformChannelSpecifics = AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: importance,
            priority: Priority.high,
            showWhen: !isCall,
            enableVibration: true,
            playSound: true,
            icon: '@drawable/notification_icon',
            largeIcon: FilePathAndroidBitmap(largeIconPath),
            styleInformation: bigTextStyleInformation,
            color: isCall ? const Color.fromRGBO(76, 175, 80, 1.0) : const Color.fromRGBO(33, 150, 243, 1.0),
            enableLights: true,
            ledColor: isCall ? const Color.fromRGBO(76, 175, 80, 1.0) : const Color.fromRGBO(33, 150, 243, 1.0),
            ledOnMs: 1000,
            ledOffMs: 500,
            ongoing: ongoing,
            autoCancel: autoCancel,
            actions: actions,
            category: isCall ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
            fullScreenIntent: isCall,
          );
        } catch (e) {
          // Fallback to default if download fails
          print('Failed to download large icon: $e');
        }
      }

      // iOS notification details
      // For iOS, we need to use categoryIdentifier for action buttons
      final String? categoryIdentifier = isCall ? 'INCOMING_CALL' : null;
      
      final DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
        attachments: null,
        categoryIdentifier: categoryIdentifier, // Required for iOS action buttons
        threadIdentifier: null,
      );

      final NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      final int id = notificationId ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      // Show the notification
      await _localNotifications.show(
        id,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
      // For iOS, add additional debugging
      if (Platform.isIOS) {
        // Check if we can get pending notifications to verify it was created
        final pendingNotifications = await _localNotifications.pendingNotificationRequests();
      }
      
      // Auto-dismiss app update and update_check notifications after 3 seconds
      // Check both isAppUpdate flag and also check payload directly as fallback
      bool shouldAutoDismiss = isAppUpdate;
      if (!shouldAutoDismiss && payload != null) {
        // Double-check payload in case isAppUpdate wasn't set correctly
        if (payload == 'app_update' || payload == 'update_check') {
          shouldAutoDismiss = true;
        } else if (payload.startsWith('{')) {
          try {
            final Map<String, dynamic> data = json.decode(payload);
            final type = data['type']?.toString();
            if (type == 'app_update' || type == 'update_check') {
              shouldAutoDismiss = true;
            }
          } catch (e) {
            // Ignore parse errors
          }
        }
      }
      
      // Also check title as a fallback (in case payload is missing or incorrect)
      if (!shouldAutoDismiss) {
        final titleLower = title.toLowerCase();
        if (titleLower.contains('update check') || 
            titleLower.contains('app update') ||
            titleLower == 'update check') {
          shouldAutoDismiss = true;
        }
      }
      
      if (shouldAutoDismiss) {
        Timer(const Duration(seconds: 3), () {
          cancelNotification(id);
        });
      }
      
      return id;
    } catch (e) {
      rethrow;
    }
  }
  
  // Added methods for update progress
  Future<void> showUpdateProgressNotification({
    required String title,
    required String status,
    required int progress,
    bool indeterminate = false,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      _updateProgressChannelId,
      'Update Progress',
      channelDescription: 'App update download and installation progress',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      indeterminate: indeterminate,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true, // Don't buzz on every update
      enableVibration: false,
      playSound: false,
      icon: '@drawable/notification_icon',
    );
    
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    
    await _localNotifications.show(
      _updateProgressNotificationId,
      title,
      status,
      platformChannelSpecifics,
      payload: 'app_update',
    );
  }

  Future<void> cancelUpdateProgressNotification() async {
    await _localNotifications.cancel(_updateProgressNotificationId);
  }

  /// Cancel a specific notification by ID
  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  Future<void> showScheduledNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    String channelId = _adminChannelId,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      _adminChannelId,
      'Admin Notifications',
      channelDescription: 'Important system notifications from administrators',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/notification_icon', // Uses logo.png for notification icon
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _localNotifications.zonedSchedule(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }



  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _localNotifications.pendingNotificationRequests();
  }

  Future<void> getNotificationSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? settingsJson = prefs.getString(_notificationSettingsKey);
    if (settingsJson != null) {
      final Map<String, dynamic> settings = json.decode(settingsJson);
    }
  }

  Future<void> updateNotificationSettings(Map<String, dynamic> settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notificationSettingsKey, json.encode(settings));
  }

  Future<String> getDeviceInfo() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return '${iosInfo.name} ${iosInfo.systemVersion}';
    } else if (Platform.isAndroid) {
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return '${androidInfo.brand} ${androidInfo.model}';
    }
    return 'Unknown device';
  }

  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        return await androidImplementation.areNotificationsEnabled() ?? false;
      }
    } else if (Platform.isIOS) {
      final IOSFlutterLocalNotificationsPlugin? iOSImplementation = _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

      if (iOSImplementation != null) {
        try {
          // For iOS, we need to check the actual permission status
          // Since the plugin doesn't provide a direct method, we'll assume permissions are granted
          // if the plugin is available and we can request permissions
          return true;
        } catch (e) {
          return false;
        }
      }
    }
    return false;
  }

  // Check iOS notification permission status
  Future<void> checkIOSNotificationStatus() async {
    if (Platform.isIOS) {
      try {
        final IOSFlutterLocalNotificationsPlugin? iOSImplementation = _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

        if (iOSImplementation != null) {
          // Try to request permissions to see if they're granted
          final bool? result = await iOSImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          if (result == true) {
          } else {
          }
        } else {
        }
      } catch (e) {
      }
    }
  }

  Future<bool> requestPermissions() async {
    try {
      if (Platform.isIOS) {
        final IOSFlutterLocalNotificationsPlugin? iOSImplementation = _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        
        if (iOSImplementation != null) {
          _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          return true;
        }
      } else if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        
        if (androidImplementation != null) {
          androidImplementation.requestNotificationsPermission();
          return true;
        }
      }
    } catch (e) {
      // Ignore
    }
    return false;
  }
}
