import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:workmanager/workmanager.dart' as workmanager;
import 'package:background_fetch/background_fetch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'auth_service.dart';
import 'realtime_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  static const String _backgroundTaskName = 'websocket_background_task';
  static const String _backgroundFetchTask = 'background_fetch_task';
  
  // WebSocket connection for background
  WebSocketChannel? _backgroundChannel;
  Timer? _keepAliveTimer;
  bool _isBackgroundConnected = false;

  Future<void> initialize() async {
    try {
      print('🔄 [Background] Initializing background service...');
      
      // Initialize WorkManager for Android background tasks
      await workmanager.Workmanager().initialize(callbackDispatcher);
      
      // Register periodic background task
      await workmanager.Workmanager().registerPeriodicTask(
        _backgroundTaskName,
        _backgroundTaskName,
        frequency: const Duration(minutes: 15), // Minimum 15 minutes on Android
        constraints: workmanager.Constraints(
          networkType: workmanager.NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      // Initialize Background Fetch for iOS
      await BackgroundFetch.configure(
        BackgroundFetchConfig(
          minimumFetchInterval: 15, // 15 minutes
          stopOnTerminate: false,
          enableHeadless: true,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresStorageNotLow: false,
          requiresDeviceIdle: false,
          startOnBoot: true,
        ),
        _backgroundFetchCallback,
        _backgroundFetchHeadlessTask,
      );

      print('✅ [Background] Background service initialized');
    } catch (e) {
      print('❌ [Background] Error initializing background service: $e');
    }
  }

  Future<void> startBackgroundService() async {
    try {
      print('🔄 [Background] Starting background service manually...');
      
      // Start background WebSocket connection
      await startBackgroundWebSocket();
      
      // For Android, also register a one-time task for immediate execution
      if (Platform.isAndroid) {
        await workmanager.Workmanager().registerOneOffTask(
          'immediate_background_task',
          'immediate_background_task',
          initialDelay: const Duration(seconds: 5),
        );
      }
      
      print('✅ [Background] Background service started manually');
    } catch (e) {
      print('❌ [Background] Error starting background service: $e');
    }
  }

  Future<void> startBackgroundWebSocket() async {
    try {
      print('🔄 [Background] Starting background WebSocket connection...');
      
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      
      if (user?.token == null) {
        print('❌ [Background] No user token available for background WebSocket');
        return;
      }

      final sessionId = _generateSessionId();
      final wsUrl = 'wss://dev.skybyn.no:4433';
      
      _backgroundChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isBackgroundConnected = true;
      
      // Send connect message
      final connectMessage = {
        'type': 'connect',
        'sessionId': sessionId,
        'token': user!.token,
        'url': 'mobile-app-background',
        'deviceInfo': {
          'device': Platform.isIOS ? 'iOS Background' : 'Android Background',
          'browser': 'Flutter Background Service',
        },
      };
      
      _backgroundChannel!.sink.add(jsonEncode(connectMessage));
      
      // Listen for messages
      _backgroundChannel!.stream.listen(
        (message) => _handleBackgroundMessage(message),
        onDone: () {
          print('🔌 [Background] WebSocket connection closed');
          _isBackgroundConnected = false;
        },
        onError: (error) {
          print('❌ [Background] WebSocket error: $error');
          _isBackgroundConnected = false;
        },
      );

      // Start keep-alive timer
      _keepAliveTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
        if (_isBackgroundConnected) {
          final pongMessage = {
            'type': 'pong',
            'sessionId': sessionId,
          };
          _backgroundChannel?.sink.add(jsonEncode(pongMessage));
        }
      });

      print('✅ [Background] Background WebSocket started');
    } catch (e) {
      print('❌ [Background] Error starting background WebSocket: $e');
    }
  }

  void _handleBackgroundMessage(dynamic message) {
    try {
      print('📥 [Background] Received message: $message');
      final data = jsonDecode(message);
      
      if (data is! Map) return;
      
      final messageType = data['type']?.toString();
      
      switch (messageType) {
        case 'new_post':
          _showBackgroundNotification(
            'New Post',
            'Someone posted something new!',
            'new_post',
            data['id']?.toString() ?? '',
          );
          break;
          
        case 'new_comment':
          _showBackgroundNotification(
            'New Comment',
            'Someone commented on a post!',
            'new_comment',
            '${data['pid']}_${data['cid']}',
          );
          break;
          
        case 'broadcast':
          final broadcastMessage = data['message']?.toString() ?? 'New broadcast message';
          print('📢 [Background] Broadcast message: $broadcastMessage');
          _showBackgroundNotification(
            'Broadcast',
            broadcastMessage,
            'broadcast',
            '',
          );
          break;
          
        case 'ping':
          // Respond to ping
          final pongMessage = {
            'type': 'pong',
            'sessionId': data['sessionId'],
          };
          _backgroundChannel?.sink.add(jsonEncode(pongMessage));
          break;
      }
    } catch (e) {
      print('❌ [Background] Error handling message: $e');
    }
  }

  Future<void> _showBackgroundNotification(
    String title,
    String body,
    String type,
    String payload,
  ) async {
    try {
      final notificationService = NotificationService();
      await notificationService.showNotification(
        title: title,
        body: body,
        payload: jsonEncode({
          'type': type,
          'data': payload,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      
      // Store notification data for when app opens
      await _storeNotificationData(type, payload, title, body);
      
      print('✅ [Background] Notification shown: $title - $body');
    } catch (e) {
      print('❌ [Background] Error showing notification: $e');
    }
  }

  Future<void> _storeNotificationData(
    String type,
    String payload,
    String title,
    String body,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifications = prefs.getStringList('background_notifications') ?? [];
      
      final notificationData = {
        'type': type,
        'payload': payload,
        'title': title,
        'body': body,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      notifications.add(jsonEncode(notificationData));
      
      // Keep only last 50 notifications
      if (notifications.length > 50) {
        notifications.removeRange(0, notifications.length - 50);
      }
      
      await prefs.setStringList('background_notifications', notifications);
    } catch (e) {
      print('❌ [Background] Error storing notification data: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getStoredNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifications = prefs.getStringList('background_notifications') ?? [];
      
      return notifications
          .map((notification) => jsonDecode(notification) as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('❌ [Background] Error getting stored notifications: $e');
      return [];
    }
  }

  Future<void> clearStoredNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('background_notifications');
    } catch (e) {
      print('❌ [Background] Error clearing stored notifications: $e');
    }
  }

  String _generateSessionId() {
    return DateTime.now().millisecondsSinceEpoch.toString() + 
           (1000 + (DateTime.now().microsecond % 9000)).toString();
  }

  Future<void> dispose() async {
    _keepAliveTimer?.cancel();
    await _backgroundChannel?.sink.close();
    _isBackgroundConnected = false;
  }
}

// Background task callback for WorkManager (Android)
@pragma('vm:entry-point')
void callbackDispatcher() {
  workmanager.Workmanager().executeTask((task, inputData) async {
    print('🔄 [Background] WorkManager task started: $task');
    
    try {
      final backgroundService = BackgroundService();
      await backgroundService.startBackgroundWebSocket();
      
      // Keep the connection alive for a short time
      await Future.delayed(const Duration(minutes: 5));
      
      print('✅ [Background] WorkManager task completed');
      return true;
    } catch (e) {
      print('❌ [Background] WorkManager task failed: $e');
      return false;
    }
  });
}

// Background fetch callback for iOS
@pragma('vm:entry-point')
void _backgroundFetchCallback(String taskId) async {
  print('🔄 [Background] Background fetch started: $taskId');
  
  try {
    final backgroundService = BackgroundService();
    await backgroundService.startBackgroundWebSocket();
    
    // Keep the connection alive for a short time
    await Future.delayed(const Duration(minutes: 5));
    
    BackgroundFetch.finish(taskId);
    print('✅ [Background] Background fetch completed');
  } catch (e) {
    print('❌ [Background] Background fetch failed: $e');
    BackgroundFetch.finish(taskId);
  }
}

// Headless background fetch task for iOS
@pragma('vm:entry-point')
void _backgroundFetchHeadlessTask(String taskId) async {
  print('🔄 [Background] Headless background fetch started: $taskId');
  
  try {
    final backgroundService = BackgroundService();
    await backgroundService.startBackgroundWebSocket();
    
    // Keep the connection alive for a short time
    await Future.delayed(const Duration(minutes: 5));
    
    BackgroundFetch.finish(taskId);
    print('✅ [Background] Headless background fetch completed');
  } catch (e) {
    print('❌ [Background] Headless background fetch failed: $e');
    BackgroundFetch.finish(taskId);
  }
} 