import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// Service to track unread chat message counts
class ChatMessageCountService extends ChangeNotifier {
  static final ChatMessageCountService _instance = ChatMessageCountService._internal();
  factory ChatMessageCountService() => _instance;
  ChatMessageCountService._internal();

  final AuthService _authService = AuthService();
  final Map<String, int> _unreadCounts = {}; // Map of friendId -> unread count
  int _totalUnreadCount = 0;
  SharedPreferences? _prefs;

  int get totalUnreadCount => _totalUnreadCount;
  Map<String, int> get unreadCounts => Map.unmodifiable(_unreadCounts);

  /// Initialize the service
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadUnreadCounts();
    } catch (e) {
      print('❌ [ChatMessageCount] Error initializing: $e');
    }
  }

  /// Load unread counts from local storage
  Future<void> _loadUnreadCounts() async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return;

      final keys = _prefs?.getKeys() ?? {};
      _unreadCounts.clear();
      _totalUnreadCount = 0;

      for (final key in keys) {
        if (key.startsWith('chat_unread_$userId\_')) {
          final friendId = key.replaceFirst('chat_unread_$userId\_', '');
          final count = _prefs?.getInt(key) ?? 0;
          if (count > 0) {
            _unreadCounts[friendId] = count;
            _totalUnreadCount += count;
          }
        }
      }

      notifyListeners();
    } catch (e) {
      print('❌ [ChatMessageCount] Error loading unread counts: $e');
    }
  }

  /// Save unread count for a friend
  Future<void> _saveUnreadCount(String friendId, int count) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return;

      final key = 'chat_unread_$userId\_$friendId';
      if (count > 0) {
        await _prefs?.setInt(key, count);
      } else {
        await _prefs?.remove(key);
      }
    } catch (e) {
      print('❌ [ChatMessageCount] Error saving unread count: $e');
    }
  }

  /// Increment unread count for a friend
  Future<void> incrementUnreadCount(String friendId) async {
    final currentCount = _unreadCounts[friendId] ?? 0;
    _unreadCounts[friendId] = currentCount + 1;
    _totalUnreadCount = _unreadCounts.values.fold(0, (sum, count) => sum + count);
    
    await _saveUnreadCount(friendId, _unreadCounts[friendId]!);
    notifyListeners();
  }

  /// Clear unread count for a friend (when chat is opened)
  Future<void> clearUnreadCount(String friendId) async {
    if (_unreadCounts.containsKey(friendId)) {
      final removedCount = _unreadCounts[friendId] ?? 0;
      _unreadCounts.remove(friendId);
      _totalUnreadCount = _unreadCounts.values.fold(0, (sum, count) => sum + count);
      
      await _saveUnreadCount(friendId, 0);
      notifyListeners();
    }
  }

  /// Get unread count for a specific friend
  int getUnreadCount(String friendId) {
    return _unreadCounts[friendId] ?? 0;
  }

  /// Clear all unread counts (on logout)
  Future<void> clearAllUnreadCounts() async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return;

      final keys = _prefs?.getKeys() ?? {};
      for (final key in keys) {
        if (key.startsWith('chat_unread_$userId\_')) {
          await _prefs?.remove(key);
        }
      }

      _unreadCounts.clear();
      _totalUnreadCount = 0;
      notifyListeners();
    } catch (e) {
      print('❌ [ChatMessageCount] Error clearing all unread counts: $e');
    }
  }
}

