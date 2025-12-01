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
  final Set<String> _processedMessageIds = {}; // Track processed message IDs to prevent duplicates
  final Map<String, int> _recentMessageHashes = {}; // Track recent messages by hash (friendId_messageHash -> timestamp) to handle temp/real ID duplicates

  int get totalUnreadCount => _totalUnreadCount;
  Map<String, int> get unreadCounts => Map.unmodifiable(_unreadCounts);

  /// Initialize the service
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadUnreadCounts();
    } catch (e) {
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
        if (key.startsWith('chat_unread_${userId}_')) {
          final friendId = key.replaceFirst('chat_unread_${userId}_', '');
          final count = _prefs?.getInt(key) ?? 0;
          if (count > 0) {
            _unreadCounts[friendId] = count;
            _totalUnreadCount += count;
          }
        }
      }

      notifyListeners();
    } catch (e) {
    }
  }

  /// Save unread count for a friend
  Future<void> _saveUnreadCount(String friendId, int count) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return;

      final key = 'chat_unread_${userId}_$friendId';
      if (count > 0) {
        await _prefs?.setInt(key, count);
      } else {
        await _prefs?.remove(key);
      }
    } catch (e) {
    }
  }

  /// Increment unread count for a friend
  /// [messageId] is optional - if provided, prevents duplicate increments for the same message
  /// [messageContent] is optional - if provided, used for content-based deduplication (handles temp/real ID duplicates)
  Future<void> incrementUnreadCount(String friendId, {String? messageId, String? messageContent}) async {
    // Use print with [SKYBYN] prefix - zone will allow it through
    print('[SKYBYN] ═══════════════════════════════════════════════════════');
    print('[SKYBYN] 📊 [ChatMessageCount] incrementUnreadCount called');
    print('[SKYBYN]    FriendId: $friendId');
    print('[SKYBYN]    MessageId: ${messageId ?? "null"}');
    print('[SKYBYN]    MessageContent: ${messageContent != null ? (messageContent.length > 50 ? messageContent.substring(0, 50) + "..." : messageContent) : "null"}');
    
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // First check: messageId-based deduplication
    if (messageId != null && messageId.isNotEmpty && messageId != 'no-id' && messageId != 'null') {
      final messageKey = '${friendId}_$messageId';
      if (_processedMessageIds.contains(messageKey)) {
        print('[SKYBYN] ⏭️ [ChatMessageCount] SKIPPING DUPLICATE - Already processed (by messageId)');
        print('[SKYBYN]    MessageKey: $messageKey');
        print('[SKYBYN]    Processed count: ${_processedMessageIds.length}');
        print('[SKYBYN] ═══════════════════════════════════════════════════════');
        return; // Already processed this message
      }
    }
    
    // Second check: content-based deduplication (handles temp ID -> real ID duplicates)
    // If we have message content, check if we've seen the same content from this friend recently (within 10 seconds)
    if (messageContent != null && messageContent.isNotEmpty) {
      final contentHash = messageContent.hashCode.toString();
      final contentKey = '${friendId}_$contentHash';
      final lastSeen = _recentMessageHashes[contentKey];
      
      if (lastSeen != null && (now - lastSeen) < 10000) { // 10 seconds window
        print('[SKYBYN] ⏭️ [ChatMessageCount] SKIPPING DUPLICATE - Same content seen recently (temp/real ID duplicate)');
        print('[SKYBYN]    ContentKey: $contentKey');
        print('[SKYBYN]    Last seen: ${now - lastSeen}ms ago');
        print('[SKYBYN] ═══════════════════════════════════════════════════════');
        return; // Same content from same friend within 10 seconds - likely temp/real ID duplicate
      }
      
      // Track this content
      _recentMessageHashes[contentKey] = now;
      print('[SKYBYN] ✅ [ChatMessageCount] Content tracked: $contentKey');
      
      // Clean up old content hashes (older than 30 seconds)
      _recentMessageHashes.removeWhere((key, timestamp) => (now - timestamp) > 30000);
    }
    
    // Track by messageId if available
    if (messageId != null && messageId.isNotEmpty && messageId != 'no-id' && messageId != 'null') {
      final messageKey = '${friendId}_$messageId';
      _processedMessageIds.add(messageKey);
      print('[SKYBYN] ✅ [ChatMessageCount] Message ID tracked: $messageKey');
      
      // Clean up old message IDs (keep last 1000 to prevent memory issues)
      if (_processedMessageIds.length > 1000) {
        final toRemove = _processedMessageIds.take(_processedMessageIds.length - 1000).toList();
        _processedMessageIds.removeAll(toRemove);
      }
    } else {
      print('[SKYBYN] ⚠️ [ChatMessageCount] No valid messageId provided');
    }
    
    final currentCount = _unreadCounts[friendId] ?? 0;
    final newCount = currentCount + 1;
    
    print('[SKYBYN] 📈 [ChatMessageCount] Incrementing count:');
    print('[SKYBYN]    Current: $currentCount');
    print('[SKYBYN]    New: $newCount');
    
    _unreadCounts[friendId] = newCount;
    _totalUnreadCount = _unreadCounts.values.fold(0, (sum, count) => sum + count);
    
    print('[SKYBYN]    Total unread: $_totalUnreadCount');
    print('[SKYBYN] ✅ [ChatMessageCount] Count saved and listeners notified');
    print('[SKYBYN] ═══════════════════════════════════════════════════════');
    
    await _saveUnreadCount(friendId, _unreadCounts[friendId]!);
    notifyListeners();
  }

  /// Clear unread count for a friend (when chat is opened)
  Future<void> clearUnreadCount(String friendId) async {
    if (_unreadCounts.containsKey(friendId)) {
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
        if (key.startsWith('chat_unread_${userId}_')) {
          await _prefs?.remove(key);
        }
      }

      _unreadCounts.clear();
      _totalUnreadCount = 0;
      notifyListeners();
    } catch (e) {
    }
  }
}

