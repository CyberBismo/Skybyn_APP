import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/user.dart';
import 'device_service.dart';
import 'firebase_messaging_service.dart';
import 'translation_service.dart';
import 'websocket_service.dart';
// import 'background_activity_service.dart';
import 'navigation_service.dart';
import 'chat_message_count_service.dart';
import 'post_service.dart';
import 'friend_service.dart';
import 'chat_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

class AuthService {
  static String get baseUrl => ApiConstants.apiBase;
  static const String userIdKey = StorageKeys.userId;
  static const String userProfileKey = StorageKeys.userProfile;
  static const String usernameKey = StorageKeys.username;
  SharedPreferences? _prefs;
  
  // HTTP client with standard SSL validation
  static http.Client? _httpClient;
  static http.Client get _client {
    _httpClient ??= _createHttpClient();
    return _httpClient!;
  }
  
  static http.Client _createHttpClient() {
    // Use default HttpClient with standard behavior
    final httpClient = HttpClient();
    
    // Set user agent and timeouts
    httpClient.userAgent = 'Skybyn-App/1.0';
    httpClient.connectionTimeout = const Duration(seconds: 30);
    httpClient.idleTimeout = const Duration(seconds: 30);
    
    // Set auto-uncompress to handle compressed responses
    httpClient.autoUncompress = true;
    return IOClient(httpClient);
  }
  // final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;
  
  // Track last known online status to prevent duplicate updates
  static bool? _lastKnownOnlineStatus;

  Future<void> initPrefs() async {
    if (_prefs == null) {
      try {
        _prefs = await SharedPreferences.getInstance();
      } catch (e) {
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      // Ensure HTTP client is initialized
      _httpClient ??= _createHttpClient();
      
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();

      // Get FCM token if available and add it to deviceInfo
      try {
        final firebaseService = FirebaseMessagingService();
        if (firebaseService.isInitialized && firebaseService.fcmToken != null) {
          deviceInfo['fcmToken'] = firebaseService.fcmToken!;
        } else {
        }
      } catch (e) {
        debugPrint('AuthService: Failed to get FCM token during login: $e');
      }

      // Get the client (should already be initialized above)
      final client = _client;
      final loginUrl = ApiConstants.login;
      
      // Make the HTTP request
      http.Response response;
      try {
        response = await client.post(
          Uri.parse(loginUrl), 
          body: {
            'user': username, 
            'password': password, 
            'deviceInfo': json.encode(deviceInfo)
          }
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Login request timed out after 30 seconds');
          },
        );
      } on HandshakeException {
        // Re-throw to be caught by outer catch block with more context
        rethrow;
      } on TimeoutException {
        rethrow;
      }

      // Parse response regardless of status code to get actual API message
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        if (data['responseCode'] == '1') {
          await initPrefs();
          // Convert userID to string to avoid type mismatch
          await _prefs?.setString(userIdKey, data['userID'].toString());
          await _prefs?.setString(usernameKey, username);

          // Try to fetch user profile, but don't fail login if it fails
          try {
            await fetchUserProfile(username);
          } catch (e) {
            debugPrint('AuthService: Failed to fetch user profile after login: $e');
          }

          // Subscribe to user-specific topics after successful login
          try {
            final firebaseService = FirebaseMessagingService();
            await firebaseService.subscribeToUserTopics();
          } catch (e) {
            debugPrint('AuthService: Failed to subscribe to user topics after login: $e');
          }

          // Register/update FCM token with user ID after successful login
          try {
            final firebaseService = FirebaseMessagingService();
            if (firebaseService.isInitialized) {
              print('📱 [Auth] Registering FCM token after login...');
              await firebaseService.sendFCMTokenToServer();
              print('📱 [Auth] FCM token registration completed');
            } else {
              print('⚠️ [Auth] FCM service not initialized, cannot register token');
            }
          } catch (e) {
            print('❌ [Auth] Failed to register FCM token after login: $e');
            // Don't fail login if FCM registration fails, but log the error
          }

          // Update online status to true after successful login
          // Online status is now calculated from last_active, no need to update

          return data;
        }
        return data;
      } else {
        // Return the actual API response even for error status codes
        return data;
      }
    } catch (e) {
      // Return error response
      String errorMessage = 'Connection error: ${e.toString()}';
      return {
        'responseCode': '0', 
        'message': errorMessage
      };
    }
  }

  Future<User?> fetchUserProfile(String username) async {
    try {
      final userId = await getStoredUserId();
      final requestBody = <String, String>{'userID': userId!};

      // Get FCM token if available
      try {
        final firebaseService = FirebaseMessagingService();
        if (firebaseService.isInitialized && firebaseService.fcmToken != null) {
          requestBody['fcmToken'] = firebaseService.fcmToken!;

          // Get device ID
          final deviceService = DeviceService();
          final deviceInfo = await deviceService.getDeviceInfo();
          requestBody['deviceId'] = deviceInfo['id'] ?? '';
        }
      } catch (e) {
      }

      final response = await _retryHttpRequest(
        () => _client.post(Uri.parse(ApiConstants.profile), body: requestBody),
        operationName: 'fetchUserProfile',
      );
      
      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);
        if (data['responseCode'] == '1') {
          // Manually add the userID to the map before creating the User object
          data['id'] = userId.toString(); // Ensure it's a string
          final user = User.fromJson(data);
          
          // Initialize cached online status from user profile
          if (user.online.isNotEmpty) {
            _lastKnownOnlineStatus = user.online == '1' || user.online.toLowerCase() == 'true';
          }
          
          // Store user profile locally
          await initPrefs();
          await _prefs?.setString(userProfileKey, json.encode(user.toJson()));
          return user;
        } else {
          final message = data['message'] ?? 'Unknown error';
          // If user not found or account not active, automatically log out
          if (message.contains('not found') || message.contains('not active') || 
              message.contains('banned') || message.contains('deactivated')) {
            await logout();
          }
        }
      } else {
        // If 400 or 404, user might not exist - log out
        if (response.statusCode == 400 || response.statusCode == 404) {
          try {
            final data = _safeJsonDecode(response.body);
            final message = data['message'] ?? '';
            if (message.contains('not found') || message.contains('not active')) {
              await logout();
            }
          } catch (e) {
            // Ignore parse errors
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> getStoredUserId() async {
    await initPrefs();
    final userId = _prefs?.getString(userIdKey);
    return userId;
  }

  Future<String?> getStoredUsername() async {
    await initPrefs();
    final username = _prefs?.getString(usernameKey);
    return username;
  }

  Future<User?> getStoredUserProfile() async {
    await initPrefs();
    final profileJson = _prefs?.getString(userProfileKey);
    if (profileJson != null) {
      try {
        final user = User.fromJson(json.decode(profileJson));
        return user;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> logout() async {
    // Background activity service removed
    /*
    try {
      await BackgroundActivityService.cancel();
    } catch (e) {
      // Silently fail
    }
    */
    
    // Reset cached online status on logout
    _lastKnownOnlineStatus = null;
    
    // Online status is now calculated from last_active, no need to update

    // Disconnect WebSocket connection on logout
    try {
      final webSocketService = WebSocketService();
      if (webSocketService.isConnected) {
        webSocketService.disconnect();
      }
    } catch (e) {
      // Ignore errors during WebSocket disconnection
    }

    // Clear all caches on logout
    try {
      // Clear chat message counts
      final chatMessageCountService = ChatMessageCountService();
      await chatMessageCountService.clearAllUnreadCounts();
    } catch (e) {
      // Silently fail
    }

    try {
      // Clear posts/timeline cache
      final postService = PostService();
      await postService.clearTimelineCache();
    } catch (e) {
      // Silently fail
    }

    try {
      // Clear friends cache
      final friendService = FriendService();
      await friendService.clearCache();
    } catch (e) {
      // Silently fail
    }

    try {
      // Clear all chat message caches
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        // Clear chat cache keys (chat_messages_* and chat_timestamp_*)
        if (key.startsWith('chat_messages_') || key.startsWith('chat_timestamp_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      // Silently fail
    }

    try {
      // Clear translations cache
      final translationService = TranslationService();
      await translationService.clearCache();
    } catch (e) {
      // Silently fail
    }

    try {
      // Clear image cache (CachedNetworkImage uses flutter_cache_manager)
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      // Silently fail
    }

    // Clear all SharedPreferences data (user-specific)
    await initPrefs();
    final keys = _prefs?.getKeys() ?? {};
    
    // Clear all keys except system-level preferences
    // Keep only theme and language preferences (these are device-level, not user-specific)
    final keysToKeep = {'theme_mode', 'language'};
    for (final key in keys) {
      if (!keysToKeep.contains(key)) {
        await _prefs?.remove(key);
      }
    }
    
    // Also explicitly remove user-specific keys (in case they weren't caught above)
    await _prefs?.remove(userIdKey);
    await _prefs?.remove(userProfileKey);
    await _prefs?.remove(usernameKey);

    // Also clear any data stored in FlutterSecureStorage
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'user_profile');
    await storage.delete(key: userIdKey);
    await storage.delete(key: userProfileKey);
    await storage.delete(key: usernameKey);

    // Clear last navigation route on logout
    try {
      await NavigationService.clearLastRoute();
    } catch (e) {
      // Silently fail
    }

    // Unsubscribe from user-specific topics on logout
    try {
      final firebaseService = FirebaseMessagingService();
      final userTopics = firebaseService.subscribedTopics.where((topic) => topic.startsWith('user_') || topic.startsWith('rank_') || topic.startsWith('status_')).toList();

      for (final topic in userTopics) {
        await firebaseService.unsubscribeFromTopic(topic);
      }
    } catch (e) {
    }
  }

  Future<void> updateUserProfile(User updatedUser) async {
    try {
      // TODO: Implement API call to update user profile
      // For now, we'll just update the local storage
      await initPrefs();
      await _prefs?.setString(userProfileKey, jsonEncode(updatedUser.toJson()));
    } catch (e) {
      throw Exception('Failed to update profile');
    }
  }

  Future<User?> fetchAnyUserProfile({String? username, String? userId}) async {
    try {
      final requestBody = <String, String>{};
      String? targetUserId = userId;
      if (userId != null) {
        requestBody['userID'] = userId;
      } else if (username != null) {
        requestBody['username'] = username;
      } else {
        throw Exception('Must provide either username or userId');
      }
      final response = await _retryHttpRequest(
        () => _client.post(Uri.parse(ApiConstants.profile), body: requestBody),
        operationName: 'fetchAnyUserProfile',
      );
      
      // Log HTTP response details
      // print('[SKYBYN] 📡 [Profile API] HTTP Response received');
      // print('[SKYBYN]    Status Code: ${response.statusCode}');
      // print('[SKYBYN]    Response Body Length: ${response.body.length}');
      // print('[SKYBYN]    Response Body (first 500 chars): ${response.body.length > 500 ? response.body.substring(0, 500) + "..." : response.body}');
      
      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          // print('[SKYBYN]    Parsed JSON: responseCode=${data['responseCode']}, message=${data['message'] ?? 'N/A'}');
          
          if (data['responseCode'] == '1') {
            // Ensure the user ID is set in the response data
            // The API might return it as 'userID' or 'id', but User.fromJson expects it
            if (targetUserId != null) {
              data['id'] = targetUserId.toString();
              data['userID'] = targetUserId.toString(); // Also set userID for compatibility
            } else if (data['userID'] != null) {
              // If we used username, extract userID from response
              data['id'] = data['userID'].toString();
            } else if (data['id'] != null) {
              // If id exists, also set userID for compatibility
              data['userID'] = data['id'].toString();
            }
            
            // print('[SKYBYN]    ✅ [Profile API] Successfully parsed profile data');
            return User.fromJson(data);
          } else {
            print('[SKYBYN]    ❌ [Profile API] responseCode is not "1": ${data['responseCode']}');
            print('[SKYBYN]    ❌ [Profile API] Error message: ${data['message'] ?? 'No message'}');
          }
        } catch (e) {
          print('[SKYBYN]    ❌ [Profile API] JSON decode error: $e');
          print('[SKYBYN]    ❌ [Profile API] Raw response: ${response.body}');
        }
      } else {
        print('[SKYBYN]    ❌ [Profile API] HTTP status code is not 200: ${response.statusCode}');
        print('[SKYBYN]    ❌ [Profile API] Response body: ${response.body}');
      }
      return null;
    } catch (e, stackTrace) {
      print('[SKYBYN]    ❌ [Profile API] Exception: $e');
      print('[SKYBYN]    ❌ [Profile API] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Sends a verification code to the specified email address
  /// Returns the verification code that was sent (for testing purposes)
  /// In production, this should not return the code
  Future<Map<String, dynamic>> sendEmailVerification(String email) async {
    try {
      final response = await _client.post(Uri.parse(ApiConstants.sendEmailVerification), body: {'email': email, 'action': 'register'}, headers: {'Content-Type': 'application/x-www-form-urlencoded'});
      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);

        if (data['responseCode'] == '1') {
          // Check if email is already verified (same logic as web version)
          final status = data['status']?.toString().toLowerCase();
          final alreadyVerified = (status == 'verified');
          
          return {
            'success': true,
            'message': data['message'] ?? 'Verification code sent successfully',
            'verificationCode': data['verificationCode'], // For testing only
            'status': data['status']?.toString(),
            'alreadyVerified': alreadyVerified,
          };
        } else {
          return {'success': false, 'message': data['message'] ?? 'Failed to send verification code'};
        }
      } else {
        return {'success': false, 'message': 'Server error occurred (Status: ${response.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error occurred: ${e.toString()}'};
    }
  }

  /// Verifies the email verification code
  Future<Map<String, dynamic>> verifyEmailCode(String email, String code) async {
    try {
      http.Response response = await _client.post(Uri.parse(ApiConstants.verifyEmail), body: {'email': email, 'code': code}, headers: {'Content-Type': 'application/x-www-form-urlencoded'});

      // No fallback; verify_email.php is the only endpoint
      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);

        if (data['responseCode'] == '1') {
          return {'success': true, 'message': data['message'] ?? 'Email verified successfully'};
        } else {
          return {'success': false, 'message': data['message'] ?? 'Email verification failed'};
        }
      } else {
        return {'success': false, 'message': 'Server error occurred (Status: ${response.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error occurred: ${e.toString()}'};
    }
  }

  dynamic _safeJsonDecode(String body) {
    try {
      return json.decode(body);
    } catch (_) {
      // Try to extract JSON if there is HTML or other noise around it
      final int objStart = body.indexOf('{');
      final int arrStart = body.indexOf('[');
      int start = -1;
      if (objStart != -1 && arrStart != -1) {
        start = objStart < arrStart ? objStart : arrStart;
      } else if (objStart != -1) {
        start = objStart;
      } else if (arrStart != -1) {
        start = arrStart;
      }
      if (start != -1) {
        final String trimmed = body.substring(start).trim();
        try {
          return json.decode(trimmed);
        } catch (e) {
        }
      }
      // As a last resort, return a map with raw message so UI can show something meaningful
      return {'responseCode': '0', 'message': body.length > 200 ? body.substring(0, 200) : body};
    }
  }

  /// Check if an exception is a transient network error that should be retried
  bool _isTransientError(dynamic error) {
    if (error is SocketException) return true;
    if (error is HandshakeException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) {
      // Retry on connection-related HTTP exceptions
      final message = error.message.toLowerCase();
      return message.contains('connection') || 
             message.contains('timeout') ||
             message.contains('reset');
    }
    return false;
  }

  /// Retry an HTTP request with exponential backoff
  /// Returns the response if successful, throws the last exception if all retries fail
  Future<http.Response> _retryHttpRequest(
    Future<http.Response> Function() request, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
    String? operationName,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        // Execute the HTTP request
        final response = await request();
        if (kDebugMode) {
          // print('API Response ($operationName): ${response.statusCode}');
          // print('Response Body: ${response.body}');
        }

        // Don't retry on successful responses (2xx) or client errors (4xx)
        if (response.statusCode < 500) {
          return response;
        }
        // Retry on server errors (5xx)
        if (response.statusCode >= 500) {
          throw HttpException('Server error: ${response.statusCode}');
        }
        return response;
      } catch (e) {
        attempt++;
        
        // Don't retry if it's not a transient error
        if (!_isTransientError(e)) {
          rethrow;
        }
        
        // Don't retry if we've exhausted all attempts
        if (attempt >= maxRetries) {
          rethrow;
        }
        
        // Wait before retrying with exponential backoff
        await Future.delayed(delay);
        
        // Exponential backoff: double the delay for next retry
        delay = Duration(milliseconds: (delay.inMilliseconds * 2).clamp(500, 8000));
      }
    }
    
    // This should never be reached, but just in case
    throw Exception('Retry logic error');
  }

  /// Update user online status
  /// Update user activity timestamp (for online status tracking)
  // updateActivity removed - replaced by WebSocket presence

  Future<void> updateOnlineStatus(bool isOnline) async {
    try {
      final userId = await getStoredUserId();
      if (userId == null) {
        return;
      }

      // Initialize _lastKnownOnlineStatus from stored profile if not set
      if (_lastKnownOnlineStatus == null) {
        try {
          final storedProfile = await getStoredUserProfile();
          if (storedProfile != null && storedProfile.online.isNotEmpty) {
            _lastKnownOnlineStatus = storedProfile.online == '1' || storedProfile.online.toLowerCase() == 'true';
          }
        } catch (e) {
          // Silently fail - will default to null
        }
      }

      // Skip update if status hasn't changed
      if (_lastKnownOnlineStatus == isOnline) {
        return;
      }

      final requestBody = <String, String>{
        'userID': userId,
        'online': isOnline ? '1' : '0',
      };

      final response = await _retryHttpRequest(
        () => _client.post(
          Uri.parse(ApiConstants.profile),
          body: requestBody,
        ),
        operationName: 'updateOnlineStatus',
        maxRetries: 2, // Fewer retries for online status (less critical)
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          _lastKnownOnlineStatus = isOnline; // Update cached status
        } else {
        }
      } else {
      }
    } catch (e) {
      // Silently fail - online status update is not critical
    }
  }

  /// Registers a new user account
  Future<Map<String, dynamic>> registerUser({
    required String email, 
    required String username, 
    required String password, 
    required String firstName, 
    required String? middleName, 
    required String lastName, 
    required DateTime dateOfBirth,
    bool isPrivate = false,
    bool isVisible = true,
    String? language,
  }) async {
    try {

      // Format date of birth as YYYY-MM-DD for the API
      final dobString = '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

      // Get device language if not provided
      String deviceLanguage = language ?? 'en';
      if (language == null) {
        try {
          final locale = Platform.localeName;
          final languageCode = locale.split('_').first.toLowerCase();
          // Map to supported languages
          final supportedLanguages = ['en', 'no', 'dk', 'se', 'de', 'fr', 'pl', 'es', 'it', 'pt', 'nl', 'fi'];
          if (supportedLanguages.contains(languageCode)) {
            deviceLanguage = languageCode;
          } else {
            // Try country code mapping
            final countryCode = locale.split('_').last.toUpperCase();
            final countryToLanguageMap = {
              'US': 'en', 'GB': 'en', 'AU': 'en', 'CA': 'en', 'NO': 'no', 'DK': 'dk', 'SE': 'se',
              'DE': 'de', 'FR': 'fr', 'PL': 'pl', 'ES': 'es', 'IT': 'it', 'PT': 'pt', 'NL': 'nl', 'FI': 'fi',
            };
            deviceLanguage = countryToLanguageMap[countryCode] ?? 'en';
          }
        } catch (e) {
          deviceLanguage = 'en'; // Fallback to English
        }
      }

      final response = await _client.post(
        Uri.parse(ApiConstants.register), 
        body: {
          'email': email, 
          'username': username, 
          'password': password, 
          'fname': firstName, 
          'mname': middleName ?? '', 
          'lname': lastName, 
          'dob': dobString,
          'private': isPrivate ? '1' : '0',
          'visible': isVisible ? '1' : '0',
          'language': deviceLanguage,
        },
        headers: {'Content-Type': 'application/x-www-form-urlencoded'}
      );
      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);

        if (data['responseCode'] == '1' || data['success'] == true) {
          String? userId = data['userID']?.toString() ?? data['data']?['userID']?.toString();
          if (userId == null) {
            userId = data['id']?.toString() ?? data['data']?['id']?.toString();
          }
          if (userId == null) {
            userId = data['userid']?.toString() ?? data['data']?['userid']?.toString();
          }
          
          final token = data['token']?.toString() ?? data['data']?['token']?.toString();
          
          // Automatically log the user in after successful registration
          // Token verification is not needed here since the token comes directly from the successful registration response
          // (Same logic as web version - web version verifies token when it comes from URL, but we get it from API response)
          if (userId != null) {
            await _postRegistrationLogin(userId, username, token ?? '');
          }
          
          return {
            'success': true, 
            'message': data['message'] ?? 'Registration successful', 
            'userID': userId, 
            'username': username,
            'token': token
          };
        } else {
          return {'success': false, 'message': data['message'] ?? 'Registration failed'};
        }
      } else {
        // Try to parse error response
        try {
          final errorData = _safeJsonDecode(response.body);
          return {'success': false, 'message': errorData['message'] ?? 'Server error occurred'};
        } catch (e) {
          return {'success': false, 'message': 'Server error occurred (Status: ${response.statusCode})'};
        }
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error occurred: ${e.toString()}'};
    }
  }

  /// Handles post-registration login (stores user data, fetches profile, etc.)
  /// Same logic as web version: sets session (stores userID/username), then redirects to home
  /// Note: Token verification is not needed here since the token comes directly from successful registration
  Future<void> _postRegistrationLogin(String userId, String username, String token) async {
    try {
      await initPrefs();
      // Store user ID and username (same as login does)
      await _prefs?.setString(userIdKey, userId);
      await _prefs?.setString(usernameKey, username);

      // Try to fetch user profile, but don't fail if it fails
      // Wait a moment for the database to be fully committed
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final user = await fetchUserProfile(username);
        // Update translation service with user's language preference if available
        if (user != null && user.language != null) {
          try {
            final translationService = TranslationService();
            await translationService.setLanguage(user.language!);
          } catch (e) {
          }
        }
      } catch (e) {
        // If profile fetch fails, we can still proceed - the user is logged in with userID and username
        // The profile can be fetched later when needed
      }

      // Subscribe to user-specific topics after successful registration
      try {
        final firebaseService = FirebaseMessagingService();
        await firebaseService.subscribeToUserTopics();
      } catch (e) {
      }

      // Online status is now calculated from last_active, no need to update
    } catch (e) {
      // Don't throw - registration was successful, login setup is optional
    }
  }
}
