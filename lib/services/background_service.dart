import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'notification_service.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  WebSocketChannel? _webSocketChannel;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isInitialized = false;
  final NotificationService _notificationService = NotificationService();
  static const MethodChannel _methodChannel = MethodChannel('no.skybyn.app/background_service');

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    try {
      print('🔄 [Background] Initializing background service...');
      
      // Start Android foreground service
      await _startAndroidBackgroundService();
      
      // Start WebSocket connection
      await _startWebSocketConnection();
      
      _isInitialized = true;
      print('✅ [Background] Background service initialized and started');
    } catch (e) {
      print('❌ [Background] Error initializing background service: $e');
    }
  }

  Future<void> _startAndroidBackgroundService() async {
    try {
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod('startBackgroundService');
        print('✅ [Background] Android background service started');
      }
    } catch (e) {
      print('❌ [Background] Error starting Android background service: $e');
    }
  }

  Future<void> _startWebSocketConnection() async {
    try {
      print('🔄 [Background] Starting background WebSocket connection...');
      
      final uri = Uri.parse('wss://dev.skybyn.no:4433');
      _webSocketChannel = WebSocketChannel.connect(uri);
      
      _webSocketChannel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          print('❌ [Background] WebSocket error: $error');
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          print('🔌 [Background] WebSocket connection closed');
          _isConnected = false;
          _scheduleReconnect();
        },
      );
      
      _isConnected = true;
      print('✅ [Background] Background WebSocket started');
    } catch (e) {
      print('❌ [Background] Error starting WebSocket: $e');
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      print('📨 [Background] Received message: $message');
      
      if (message is String) {
        final data = json.decode(message);
        
        if (data['type'] == 'broadcast') {
          print('📢 [Background] Processing broadcast message: ${data['message']}');
          
          // Show notification for broadcast
          _notificationService.showNotification(
            title: 'Broadcast',
            body: data['message'] ?? 'New broadcast message',
            payload: message,
          ).then((_) {
            print('✅ [Background] Broadcast notification sent successfully');
          }).catchError((error) {
            print('❌ [Background] Error sending broadcast notification: $error');
          });
        } else if (data['type'] == 'new_post') {
          print('📝 [Background] Processing new post message');
          _notificationService.showNotification(
            title: 'New Post',
            body: 'Someone posted something new',
            payload: message,
          );
        } else if (data['type'] == 'new_comment') {
          print('💬 [Background] Processing new comment message');
          _notificationService.showNotification(
            title: 'New Comment',
            body: 'Someone commented on a post',
            payload: message,
          );
        }
      }
    } catch (e) {
      print('❌ [Background] Error handling message: $e');
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 30), () {
      if (!_isConnected) {
        print('🔄 [Background] Attempting to reconnect...');
        _startWebSocketConnection();
      }
    });
  }

  Future<void> stop() async {
    try {
      print('🛑 [Background] Stopping background service...');
      
      // Stop Android foreground service
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod('stopBackgroundService');
      }
      
      // Close WebSocket connection
      _webSocketChannel?.sink.close();
      _reconnectTimer?.cancel();
      _isConnected = false;
      _isInitialized = false;
      
      print('✅ [Background] Background service stopped');
    } catch (e) {
      print('❌ [Background] Error stopping background service: $e');
    }
  }

  Future<void> sendMessage(String message) async {
    try {
      if (_isConnected && _webSocketChannel != null) {
        _webSocketChannel!.sink.add(message);
        print('📤 [Background] Message sent: $message');
      } else {
        print('⚠️ [Background] WebSocket not connected, cannot send message');
      }
    } catch (e) {
      print('❌ [Background] Error sending message: $e');
    }
  }
}



 