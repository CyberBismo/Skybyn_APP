import 'dart:convert';
import '../utils/api_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import '../config/constants.dart';
import '../models/friend.dart';

class FriendService {
  static const String _cacheKey = 'cached_friends';
  static const String _cacheTimestampKey = 'cached_friends_timestamp';
  static const String _cacheHashKey = 'cached_friends_hash';
  static const Duration _cacheExpiry = Duration(hours: 24); // Cache for 24 hours (content-based update)

  Future<List<Friend>> fetchFriendsForUser({
    required String userId, 
    bool forceRefresh = false,
    Function(List<Friend>)? onUpdated,
  }) async {
    try {
      // Load cached data immediately for fast display
      final cachedFriends = await _loadFromCache();
      
      // If we have cached data and not forcing refresh, return it immediately
      // Then fetch fresh data in background
      if (cachedFriends.isNotEmpty && !forceRefresh) {
        // Fetch fresh data in background without blocking
        _updateFriendsInBackground(userId, cachedFriends, onUpdated);
        return cachedFriends;
      }

      // If no cache or force refresh, fetch from API
      return await _fetchAndUpdateFriends(userId);
    } catch (e) {
      // If API fails, try to return cached data as fallback
      final cachedFriends = await _loadFromCache();
      return cachedFriends;
    }
  }

  /// Fetch friends from API and update cache if content changed
  Future<List<Friend>> _fetchAndUpdateFriends(String userId) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConstants.friends),
            body: {'userID': userId},
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': 'Skybyn App',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final dynamic data = safeJsonDecode(response);
        if (data is List) {
          final List<Map<String, dynamic>> list = data
              .whereType<Map<String, dynamic>>()
              .where((m) => (m['responseCode']?.toString() ?? '1') == '1')
              .toList();
          final friends = list.map(Friend.fromJson).toList();
          
          // Check if content has changed
          final hasChanged = await _hasContentChanged(friends);
          
          if (hasChanged) {
            // Only update cache if content has changed
            await _saveToCache(friends);
          } else {
          }
          
          return friends;
        }
      }
      
      // If API fails, return cached data if available
      final cachedFriends = await _loadFromCache();
      if (cachedFriends.isNotEmpty) {
        return cachedFriends;
      }
      return [];
    } catch (e) {
      // If API fails, try to return cached data as fallback
      final cachedFriends = await _loadFromCache();
      return cachedFriends;
    }
  }

  /// Check if an exception is a transient network error that should be retried
  bool _isTransientError(dynamic error) {
    if (error is SocketException) return true;
    if (error is HandshakeException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) {
      final message = error.message.toLowerCase();
      return message.contains('connection') || 
             message.contains('timeout') ||
             message.contains('reset');
    }
    return false;
  }

  /// Retry an HTTP request with exponential backoff
  Future<http.Response> _retryHttpRequest(
    Future<http.Response> Function() request, {
    int maxRetries = 2,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    
    while (attempt < maxRetries) {
      try {
        final response = await request();
        if (response.statusCode < 500) {
          return response;
        }
        if (response.statusCode >= 500) {
          throw HttpException('Server error: ${response.statusCode}');
        }
        return response;
      } catch (e) {
        attempt++;
        if (!_isTransientError(e) || attempt >= maxRetries) {
          rethrow;
        }
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * 2).clamp(500, 4000));
      }
    }
    throw Exception('Retry logic error');
  }

  /// Update friends list in background and update cache if content changed
  Future<void> _updateFriendsInBackground(
    String userId, 
    List<Friend> currentCachedFriends,
    Function(List<Friend>)? onUpdated,
  ) async {
    try {
      final response = await _retryHttpRequest(
        () => http
            .post(
              Uri.parse(ApiConstants.friends),
              body: {'userID': userId},
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'User-Agent': 'Skybyn App',
              },
            )
            .timeout(const Duration(seconds: 10)),
        maxRetries: 2,
      );

      if (response.statusCode == 200) {
        final dynamic data = safeJsonDecode(response);
        if (data is List) {
          final List<Map<String, dynamic>> list = data
              .whereType<Map<String, dynamic>>()
              .where((m) => (m['responseCode']?.toString() ?? '1') == '1')
              .toList();
          final friends = list.map(Friend.fromJson).toList();
          
          // Check if content has changed
          final hasChanged = await _hasContentChanged(friends);
          
          if (hasChanged) {
            // Only update cache if content has changed
            await _saveToCache(friends);
            // Notify callback if provided (to update UI)
            if (onUpdated != null) {
              onUpdated(friends);
            }
          } else {
          }
        }
      }
    } catch (e) {
      // Silently fail - we already have cached data showing
    }
  }

  /// Check if the friends list content has changed compared to cache
  Future<bool> _hasContentChanged(List<Friend> newFriends) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedHash = prefs.getString(_cacheHashKey);
      
      // Generate hash for new friends list
      final newHash = _generateFriendsHash(newFriends);
      
      // If no cached hash exists, content has changed
      if (cachedHash == null) {
        return true;
      }
      
      // Compare hashes
      return newHash != cachedHash;
    } catch (e) {
      // If hash comparison fails, assume content changed to be safe
      return true;
    }
  }

  /// Generate a hash of the friends list content for comparison
  String _generateFriendsHash(List<Friend> friends) {
    // Sort friends by ID for consistent hashing
    final sortedFriends = List<Friend>.from(friends)..sort((a, b) => a.id.compareTo(b.id));
    
    // Create a JSON representation of all friend data
    final friendsJson = sortedFriends.map((f) => f.toJson()).toList();
    final jsonString = jsonEncode(friendsJson);
    
    // Generate SHA-256 hash
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    
    return digest.toString();
  }

  Future<void> _saveToCache(List<Friend> friends) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final friendsJson = friends.map((f) => f.toJson()).toList();
      final jsonString = jsonEncode(friendsJson);
      
      // Generate and store hash for content change detection
      final hash = _generateFriendsHash(friends);
      
      await prefs.setString(_cacheKey, jsonString);
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(_cacheHashKey, hash);
    } catch (e) {
    }
  }

  Future<List<Friend>> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);
      
      // Check if cache is expired (but still allow loading if content-based update is working)
      if (timestamp == null) {
        return [];
      }
      
      // Only check expiry if cache is very old (fallback mechanism)
      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (cacheAge > _cacheExpiry.inMilliseconds) {
        // Cache is expired, but we'll still try to load it as fallback
        // The API fetch will update it if needed
      }

      final friendsJson = prefs.getString(_cacheKey);
      if (friendsJson == null) return [];

      final List<dynamic> decoded = jsonDecode(friendsJson);
      return decoded.map((item) => Friend.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      await prefs.remove(_cacheHashKey);
    } catch (e) {
    }
  }

  Future<void> refreshFriends({required String userId}) async {
    // Force refresh by fetching fresh data (will update cache if changed)
    await fetchFriendsForUser(userId: userId, forceRefresh: true);
  }

  /// Update online status for a specific friend in the cache and notify listeners
  Future<void> updateFriendOnlineStatus(String friendId, bool isOnline, {Function(List<Friend>)? onUpdated}) async {
    try {
      final cachedFriends = await _loadFromCache();
      if (cachedFriends.isEmpty) return;

      int index = cachedFriends.indexWhere((f) => f.id == friendId);
      if (index != -1) {
        // Clone the friend with new status
        final friend = cachedFriends[index];
        // Only update if status actually changed
        if (friend.online != isOnline) {
          cachedFriends[index] = friend.copyWith(online: isOnline);
          
          // Save updated list to cache
          await _saveToCache(cachedFriends);
          
          // Notify callback if provided
          if (onUpdated != null) {
            onUpdated(cachedFriends);
          }
        }
      }
    } catch (e) {
      // Silently fail
    }
  }
}


