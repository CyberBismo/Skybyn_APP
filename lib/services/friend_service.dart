import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/friend.dart';

class FriendService {
  static const String _cacheKey = 'cached_friends';
  static const String _cacheTimestampKey = 'cached_friends_timestamp';
  static const Duration _cacheExpiry = Duration(hours: 1); // Cache for 1 hour

  Future<List<Friend>> fetchFriendsForUser({required String userId}) async {
    try {
      // Try to load from cache first
      final cachedFriends = await _loadFromCache();
      if (cachedFriends.isNotEmpty) {
        return cachedFriends;
      }

      // If no cache or expired, fetch from API
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
        final dynamic data = json.decode(response.body);
        if (data is List) {
          final List<Map<String, dynamic>> list = data
              .whereType<Map<String, dynamic>>()
              .where((m) => (m['responseCode']?.toString() ?? '1') == '1')
              .toList();
          final friends = list.map(Friend.fromJson).toList();
          
          // Cache the friends list
          await _saveToCache(friends);
          
          return friends;
        }
      }
      return [];
    } catch (e) {
      // If API fails, try to return cached data as fallback
      final cachedFriends = await _loadFromCache();
      return cachedFriends;
    }
  }

  Future<void> _saveToCache(List<Friend> friends) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final friendsJson = friends.map((f) => f.toJson()).toList();
      await prefs.setString(_cacheKey, jsonEncode(friendsJson));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Silently fail if caching fails
    }
  }

  Future<List<Friend>> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);
      
      // Check if cache is expired
      if (timestamp == null || 
          DateTime.now().millisecondsSinceEpoch - timestamp > _cacheExpiry.inMilliseconds) {
        return [];
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
    } catch (e) {
      // Silently fail if clearing fails
    }
  }

  Future<void> refreshFriends({required String userId}) async {
    // Clear cache and fetch fresh data
    await clearCache();
    await fetchFriendsForUser(userId: userId);
  }
}


