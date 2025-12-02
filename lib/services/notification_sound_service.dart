import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSoundService {
  static final NotificationSoundService _instance = NotificationSoundService._internal();
  factory NotificationSoundService() => _instance;
  NotificationSoundService._internal();

  static const MethodChannel _channel = MethodChannel('no.skybyn.app/system_sounds');
  static const String _soundPreferenceKey = 'notification_sound_effect';
  static const String _soundEnabledKey = 'notification_sound_enabled';
  static const String _customSoundPathKey = 'custom_notification_sound_path';
  
  List<Map<String, String>>? _cachedSounds;
  
  // Available sound effects - will be populated from system
  static const String defaultSound = 'default';
  static const String customSound = 'custom';

  /// Get available system sounds
  Future<List<Map<String, String>>> getAvailableSounds() async {
    if (_cachedSounds != null) {
      return _cachedSounds!;
    }
    
    try {
      final List<dynamic> sounds = await _channel.invokeMethod('getSystemSounds');
      _cachedSounds = sounds.map((sound) => {
        'id': sound['id'] as String? ?? '',
        'title': sound['title'] as String? ?? '',
        'uri': sound['uri'] as String? ?? '',
      }).toList();
      
      // Always include default as first option
      _cachedSounds?.insert(0, {
        'id': defaultSound,
        'title': 'Default',
        'uri': defaultSound,
      });
      
      return _cachedSounds ?? [];
    } catch (e) {
      print('Failed to get system sounds: $e');
      // Return default sound if platform channel fails
      return [
        {
          'id': defaultSound,
          'title': 'Default',
          'uri': defaultSound,
        }
      ];
    }
  }

  /// Get the selected sound effect
  Future<String> getSelectedSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_soundPreferenceKey) ?? defaultSound;
  }

  /// Set the selected sound effect
  Future<void> setSelectedSound(String sound) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_soundPreferenceKey, sound);
  }

  /// Get the custom sound file path
  Future<String?> getCustomSoundPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customSoundPathKey);
  }

  /// Set the custom sound file path
  Future<void> setCustomSoundPath(String? filePath) async {
    final prefs = await SharedPreferences.getInstance();
    if (filePath != null) {
      await prefs.setString(_customSoundPathKey, filePath);
      // Also set the selected sound to custom
      await prefs.setString(_soundPreferenceKey, customSound);
    } else {
      await prefs.remove(_customSoundPathKey);
    }
  }

  /// Check if custom sound is set
  Future<bool> hasCustomSound() async {
    final path = await getCustomSoundPath();
    if (path == null) return false;
    final file = File(path);
    return await file.exists();
  }

  /// Check if notification sounds are enabled
  Future<bool> isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true; // Default to enabled
  }

  /// Enable or disable notification sounds
  Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, enabled);
  }

  /// Play the notification sound
  Future<void> playNotificationSound() async {
    try {
      // Check if sounds are enabled
      final isEnabled = await isSoundEnabled();
      if (!isEnabled) {
        return;
      }

      // Get the selected sound
      final selectedSound = await getSelectedSound();
      
      // If custom sound is selected, get the file path
      if (selectedSound == customSound) {
        final customPath = await getCustomSoundPath();
        if (customPath != null && await File(customPath).exists()) {
          await _channel.invokeMethod('playCustomSound', {'filePath': customPath});
          return;
        } else {
          // Fallback to default if custom sound doesn't exist
          await _channel.invokeMethod('playSound', {'soundId': defaultSound});
          return;
        }
      }
      
      // Play the sound using platform channel
      await _channel.invokeMethod('playSound', {'soundId': selectedSound});
    } catch (e) {
      // Silently fail if sound can't be played
      // This prevents errors from breaking the notification flow
      print('Failed to play notification sound: $e');
    }
  }

  /// Clear cached sounds (useful when system sounds change)
  void clearCache() {
    _cachedSounds = null;
  }
}

