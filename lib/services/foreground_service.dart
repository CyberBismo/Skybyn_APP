import 'package:flutter/services.dart';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

/// Service to manage the Android foreground service for background WebSocket communication
/// This service maintains WebSocket connection and performs background checks even when app is in background
class ForegroundService {
  static const MethodChannel _channel = MethodChannel('no.skybyn.app/background_service');

  /// Start the foreground service
  /// This will keep the app running in the background to maintain WebSocket connection
  /// and perform periodic background checks
  static Future<void> start() async {
    if (!Platform.isAndroid) {
      // Foreground service is Android-only
      return;
    }
    
    try {
      await _channel.invokeMethod('startBackgroundService');
      developer.log('Foreground service started', name: 'ForegroundService');
    } catch (e) {
      developer.log('Error starting foreground service: $e', name: 'ForegroundService');
    }
  }

  /// Stop the foreground service
  static Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    
    try {
      await _channel.invokeMethod('stopBackgroundService');
      developer.log('Foreground service stopped', name: 'ForegroundService');
    } catch (e) {
      developer.log('Error stopping foreground service: $e', name: 'ForegroundService');
    }
  }
}

