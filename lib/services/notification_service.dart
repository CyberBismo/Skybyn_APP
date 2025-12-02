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
import 'firebase_messaging_service.dart';
import 'auto_update_service.dart';
import 'background_update_scheduler.dart';
import 'websocket_service.dart';
import 'auth_service.dart';
import 'friend_service.dart';
import '../widgets/update_dialog.dart';
import '../models/friend.dart';
import '../main.dart';

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

      // Request permissions after initialization
      if (Platform.isIOS) {
        await requestIOSPermissions();
      } else if (Platform.isAndroid) {
        await requestAndroidPermissions();
      }
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
          // Create category for incoming calls with answer/decline actions
          await iOSImplementation.requestPermissions();
          
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
          // Handle call notification tap (when user taps notification body, not action button)
          _handleCallNotificationTap(data);
        } else if (type == 'chat') {
          // Handle chat notification tap - navigate to chat screen
          await _handleChatNotificationTap(data);
        }
      } catch (e) {
      }
    }
  }

  // Background notification handler (for when app is terminated)
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTapped(NotificationResponse response) {
    // This is a static method that can be called from background
    final payload = response.payload;
    final action = response.actionId;
    
    // Handle call notification actions
    if (action != null && (action == 'answer' || action == 'decline')) {
      // Parse payload to get call data
      if (payload != null && payload.startsWith('{')) {
        try {
          final Map<String, dynamic> data = json.decode(payload);
          _handleCallNotificationActionStatic(action, data);
        } catch (e) {
        }
      }
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
      // When user answers, the app should open and WebSocket will handle the call
      // The call offer should still be available when app opens
      // Navigation will be handled by the app's main navigation/routing
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
      final fromUserId = data['from']?.toString();
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
    final sender = data['sender']?.toString();
    final callType = data['callType']?.toString() ?? 'video';
    
    if (sender == null) {
      return;
    }
    // TODO: Navigate to call screen
    // This will need to be handled by the app's navigation system
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

  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = _adminChannelId,
  }) async {
    try {
      // Check notification type from payload
      bool isAppUpdate = false;
      bool isChat = false;
      bool isCall = false;
      if (payload != null) {
        if (payload == 'app_update') {
          isAppUpdate = true;
        } else if (payload.startsWith('{')) {
          try {
            final Map<String, dynamic> data = json.decode(payload);
            final type = data['type']?.toString();
            if (type == 'app_update') {
              isAppUpdate = true;
            } else if (type == 'chat') {
              isChat = true;
            } else if (type == 'call') {
              isCall = true;
            }
          } catch (e) {
            // Not JSON, ignore
          }
        }
      }
      
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
      }
      // Android notification details - use appropriate channel
      String channelName;
      String channelDescription;
      Importance importance;
      List<AndroidNotificationAction>? actions;
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
      } else {
        channelName = 'Admin Notifications';
        channelDescription = 'Important system notifications from administrators';
        importance = Importance.max;
      }
      
      final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
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
        category: isCall ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
        fullScreenIntent: isCall, // Show full screen for calls (Android 11+)
      );

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

      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Show the notification
      await _localNotifications.show(
        notificationId,
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
      
      // Auto-dismiss app update notifications after 3 seconds (like login notifications)
      if (isAppUpdate && notificationId >= 0) {
        Timer(const Duration(seconds: 3), () {
          cancelNotification(notificationId);
        });
      }
      
      return notificationId;
    } catch (e) {
      rethrow;
    }
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

  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
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
        await requestIOSPermissions();
        return true;
      } else if (Platform.isAndroid) {
        await requestAndroidPermissions();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Show or update a progress notification for app updates
  /// [progress] should be between 0 and 100
  Future<void> showUpdateProgressNotification({
    required String title,
    required String status,
    required int progress,
    bool indeterminate = false,
  }) async {
    try {
      if (Platform.isAndroid) {
        // Android supports progress notifications
        final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          _updateProgressChannelId,
          'Update Progress',
          channelDescription: 'App update download and installation progress',
          importance: Importance.low,
          priority: Priority.low,
          showWhen: false,
          playSound: false,
          enableVibration: false,
          icon: '@drawable/notification_icon',
          progress: progress,
          maxProgress: 100,
          indeterminate: indeterminate,
          ongoing: true,
          onlyAlertOnce: true,
          autoCancel: false,
        );

        final NotificationDetails notificationDetails = NotificationDetails(
          android: androidDetails,
        );

        await _localNotifications.show(
          _updateProgressNotificationId,
          title,
          status,
          notificationDetails,
        );
      } else if (Platform.isIOS) {
        // iOS doesn't support progress notifications well, show simple status notification
        const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        );

        const NotificationDetails notificationDetails = NotificationDetails(
          iOS: iOSDetails,
        );

        await _localNotifications.show(
          _updateProgressNotificationId,
          title,
          status,
          notificationDetails,
        );
      }
    } catch (e) {
    }
  }

  /// Cancel the update progress notification
  Future<void> cancelUpdateProgressNotification() async {
    try {
      await _localNotifications.cancel(_updateProgressNotificationId);
    } catch (e) {
    }
  }
}
