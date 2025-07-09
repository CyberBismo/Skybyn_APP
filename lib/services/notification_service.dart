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
      print('=== INITIALIZING NOTIFICATION SERVICE ===');
      tz.initializeTimeZones();
      if (Platform.isIOS) {
        await requestIOSPermissions();
      }
      await _initializeLocalNotifications();
      print('Local notifications initialized successfully');
      print('=== NOTIFICATION SERVICE INITIALIZED SUCCESSFULLY ===');
    } catch (e, stackTrace) {
      print('=== ERROR INITIALIZING NOTIFICATION SERVICE ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
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

    final bool? initialized = await _localNotifications.initialize(initializationSettings);
    print('Local notifications initialized: $initialized');

    await _createNotificationChannels();
  }

  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel adminChannel = AndroidNotificationChannel(
      _adminChannelId,
      'Admin Notifications',
      description: 'Important system notifications from administrators',
      importance: Importance.high,
    );

    const AndroidNotificationChannel featureChannel = AndroidNotificationChannel(
      _featureChannelId,
      'Feature Announcements',
      description: 'Updates about new features and improvements',
      importance: Importance.defaultImportance,
    );

    const AndroidNotificationChannel maintenanceChannel = AndroidNotificationChannel(
      _maintenanceChannelId,
      'Maintenance Alerts',
      description: 'Scheduled maintenance and system updates',
      importance: Importance.high,
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

  Future<void> requestIOSPermissions() async {
    if (Platform.isIOS) {
      final IOSFlutterLocalNotificationsPlugin? iOSImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

      if (iOSImplementation != null) {
        final bool? result = await iOSImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        print('iOS notification permissions granted: $result');
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
      print('🔔 [Notification] Attempting to show notification: $title - $body');
      print('🔔 [Notification] Platform: ${Platform.isIOS ? 'iOS' : 'Android'}');
      
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        _adminChannelId,
        'Admin Notifications',
        channelDescription: 'Important system notifications from administrators',
        importance: Importance.max,
        priority: Priority.high,
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
      
      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      print('🔔 [Notification] Using notification ID: $notificationId');
      
      await _localNotifications.show(
        notificationId,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
      
      print('🔔 [Notification] Notification show() completed successfully');
    } catch (e, stackTrace) {
      print('🔔 [Notification] Error showing notification: $e');
      print('🔔 [Notification] Stack trace: $stackTrace');
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
} 