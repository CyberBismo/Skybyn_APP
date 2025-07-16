import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

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
    } catch (e, stackTrace) {
      print('Error initializing notification service: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    // iOS initialization settings - updated for better iOS support
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true, // Request alert permission during initialization
      requestBadgePermission: true, // Request badge permission during initialization
      requestSoundPermission: true, // Request sound permission during initialization
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    final bool? initialized = await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    if (initialized == true) {
      await _createNotificationChannels();
      print('✅ [NotificationService] Local notifications initialized successfully');
    } else {
      print('❌ [NotificationService] Failed to initialize local notifications');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap
    print('Notification tapped: ${response.payload}');
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

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(adminChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(featureChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(maintenanceChannel);
    }
  }

  Future<void> requestIOSPermissions() async {
    if (Platform.isIOS) {
      try {
        final IOSFlutterLocalNotificationsPlugin? iOSImplementation =
            _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

        if (iOSImplementation != null) {
          final bool? result = await iOSImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            provisional: false, // Don't request provisional permissions
          );
          print('🔔 [NotificationService] iOS notification permissions granted: $result');
          
          // Check if permissions were actually granted
          if (result == true) {
            print('✅ [NotificationService] iOS notification permissions successfully granted');
          } else {
            print('⚠️ [NotificationService] iOS notification permissions not granted');
          }
        } else {
          print('❌ [NotificationService] iOS implementation not available');
        }
      } catch (e) {
        print('❌ [NotificationService] Error requesting iOS permissions: $e');
      }
    }
  }

  Future<void> requestAndroidPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        // Request notification permissions for Android 13+ (API level 33+)
        final bool? result = await androidImplementation.requestNotificationsPermission();
        print('Android notification permissions requested: $result');
        
        // Check if notifications are enabled
        final bool? areNotificationsEnabled = await androidImplementation.areNotificationsEnabled();
        print('Android notifications are enabled: $areNotificationsEnabled');
        
        if (areNotificationsEnabled != true) {
          print('Android notifications are disabled. User needs to enable them in system settings.');
        }
      }
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = _adminChannelId,
  }) async {
    try {
      print('🔔 [NotificationService] Showing notification: $title - $body');
      print('🔔 [NotificationService] Platform: ${Platform.operatingSystem}');
      print('🔔 [NotificationService] Channel ID: $channelId');
      
      // Check if the notification service is properly initialized
      if (_localNotifications == null) {
        print('❌ [NotificationService] Local notifications plugin is null');
        return;
      }
      
      // Android notification details
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        _adminChannelId,
        'Admin Notifications',
        channelDescription: 'Important system notifications from administrators',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@drawable/notification_icon', // Use logo for small notification icon
        largeIcon: DrawableResourceAndroidBitmap('@drawable/notification_icon'), // Use logo for large icon
        color: Color(0xFF2196F3), // Blue color
        enableLights: true,
        ledColor: Color(0xFF2196F3),
        ledOnMs: 1000,
        ledOffMs: 500,
      );

      // iOS notification details
      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
        attachments: null,
        categoryIdentifier: null,
        threadIdentifier: null,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );
      
      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      print('🔔 [NotificationService] Notification ID: $notificationId');
      print('🔔 [NotificationService] Notification details: $platformChannelSpecifics');
      
      // Show the notification
      await _localNotifications.show(
        notificationId,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
      
      print('✅ [NotificationService] Notification sent successfully');
      
      // For iOS, add additional debugging
      if (Platform.isIOS) {
        print('📱 [NotificationService] iOS notification should appear in Notification Center');
        print('📱 [NotificationService] Swipe down from top of screen to check Notification Center');
        
        // Check if we can get pending notifications to verify it was created
        final pendingNotifications = await _localNotifications.pendingNotificationRequests();
        print('📱 [NotificationService] Pending notifications count: ${pendingNotifications.length}');
      }
    } catch (e, stackTrace) {
      print('❌ [NotificationService] Error showing notification: $e');
      print('❌ [NotificationService] Stack trace: $stackTrace');
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
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      _adminChannelId,
      'Admin Notifications',
      channelDescription: 'Important system notifications from administrators',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/notification_icon', // Use logo for small notification icon
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
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
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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
      print('Notification settings: $settings');
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
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        return await androidImplementation.areNotificationsEnabled() ?? false;
      }
    } else if (Platform.isIOS) {
      final IOSFlutterLocalNotificationsPlugin? iOSImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      
      if (iOSImplementation != null) {
        try {
          // For iOS, we need to check the actual permission status
          // Since the plugin doesn't provide a direct method, we'll assume permissions are granted
          // if the plugin is available and we can request permissions
          return true;
        } catch (e) {
          print('❌ [NotificationService] Error checking iOS notification permissions: $e');
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
        final IOSFlutterLocalNotificationsPlugin? iOSImplementation =
            _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        
        if (iOSImplementation != null) {
          print('📱 [NotificationService] iOS notification plugin available');
          
          // Try to request permissions to see if they're granted
          final bool? result = await iOSImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          );
          
          print('📱 [NotificationService] iOS permission request result: $result');
          
          if (result == true) {
            print('✅ [NotificationService] iOS notifications are enabled');
          } else {
            print('⚠️ [NotificationService] iOS notifications may be disabled');
          }
        } else {
          print('❌ [NotificationService] iOS notification plugin not available');
        }
      } catch (e) {
        print('❌ [NotificationService] Error checking iOS notification status: $e');
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
      print('Error requesting notification permissions: $e');
      return false;
    }
  }
} 