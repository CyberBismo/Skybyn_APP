import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import 'device_service.dart';
import 'firebase_messaging_service.dart';
import 'translation_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

class AuthService {
  static String get baseUrl => ApiConstants.apiBase;
  static const String userIdKey = StorageKeys.userId;
  static const String userProfileKey = StorageKeys.userProfile;
  static const String usernameKey = StorageKeys.username;
  SharedPreferences? _prefs;
  // final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;
  
  // Track last known online status to prevent duplicate updates
  static bool? _lastKnownOnlineStatus;

  Future<void> initPrefs() async {
    if (_prefs == null) {
      try {
        _prefs = await SharedPreferences.getInstance();
      } catch (e) {
        print('❌ Error initializing SharedPreferences: $e');
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();

      // Get FCM token if available and add it to deviceInfo
      try {
        final firebaseService = FirebaseMessagingService();
        if (firebaseService.isInitialized && firebaseService.fcmToken != null) {
          deviceInfo['fcmToken'] = firebaseService.fcmToken!;
          print('✅ [Login] FCM token included in deviceInfo');
        } else {
          print('⚠️ [Login] FCM token not available yet (service not initialized or token not ready)');
        }
      } catch (e) {
        print('⚠️ [Login] Could not get FCM token: $e');
      }

      final response = await http.post(Uri.parse(ApiConstants.login), body: {'user': username, 'password': password, 'deviceInfo': json.encode(deviceInfo)});

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
            print('❌ [Login] Failed to fetch user profile during login: $e');
          }

          // Subscribe to user-specific topics after successful login
          try {
            final firebaseService = FirebaseMessagingService();
            await firebaseService.subscribeToUserTopics();
          } catch (e) {
            print('❌ [Login] Failed to subscribe to user topics: $e');
          }

          // Register/update FCM token with user ID after successful login
          try {
            final firebaseService = FirebaseMessagingService();
            if (firebaseService.isInitialized) {
              await firebaseService.sendFCMTokenToServer();
            }
          } catch (e) {
            print('⚠️ [Login] Failed to register FCM token: $e');
          }

          // Update online status to true after successful login
          try {
            await updateOnlineStatus(true);
          } catch (e) {
            print('⚠️ [Login] Failed to update online status: $e');
          }

          return data;
        }

        print('❌ Login failed with response: $data');
        return data;
      } else {
        print('❌ Server error with status: ${response.statusCode}, response: $data');
        // Return the actual API response even for error status codes
        return data;
      }
    } catch (e) {
      print('❌ Login exception: $e');
      return {'responseCode': '0', 'message': 'Connection error occurred: ${e.toString()}'};
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
        print('❌ [Profile] Could not get FCM token: $e');
      }

      final response = await http.post(Uri.parse(ApiConstants.profile), body: requestBody);
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
          print('❌ Profile API did not return responseCode 1: $message');
          
          // If user not found or account not active, automatically log out
          if (message.contains('not found') || message.contains('not active') || 
              message.contains('banned') || message.contains('deactivated')) {
            print('⚠️ [Profile] User account no longer valid, logging out...');
            await logout();
          }
        }
      } else {
        print('❌ Profile API returned non-200 status: ${response.statusCode}');
        print('❌ Profile API response body: ${response.body}');
        
        // If 400 or 404, user might not exist - log out
        if (response.statusCode == 400 || response.statusCode == 404) {
          try {
            final data = _safeJsonDecode(response.body);
            final message = data['message'] ?? '';
            if (message.contains('not found') || message.contains('not active')) {
              print('⚠️ [Profile] User account no longer valid, logging out...');
              await logout();
            }
          } catch (e) {
            // Ignore parse errors
          }
        }
      }
      return null;
    } catch (e) {
      print('❌ Error fetching user profile: ${e.toString()}');
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
        print('❌ [Auth] getStoredUserProfile() failed to parse user: $e');
        return null;
      }
    }
    return null;
  }

  Future<void> logout() async {
    // Reset cached online status on logout
      _lastKnownOnlineStatus = null;
      
      // Update online status to false before logging out
      try {
        await updateOnlineStatus(false);
      } catch (e) {
        print('⚠️ [Logout] Failed to update online status: $e');
      }

    await initPrefs();
    await _prefs?.remove(userIdKey);
    await _prefs?.remove(userProfileKey);
    await _prefs?.remove(usernameKey);

    // Also clear any data stored in FlutterSecureStorage
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'user_profile');
    await storage.delete(key: userIdKey);
    await storage.delete(key: userProfileKey);
    await storage.delete(key: usernameKey);

    // Unsubscribe from user-specific topics on logout
    try {
      final firebaseService = FirebaseMessagingService();
      final userTopics = firebaseService.subscribedTopics.where((topic) => topic.startsWith('user_') || topic.startsWith('rank_') || topic.startsWith('status_')).toList();

      for (final topic in userTopics) {
        await firebaseService.unsubscribeFromTopic(topic);
      }
    } catch (e) {
      print('❌ [Logout] Failed to unsubscribe from user topics: $e');
    }
  }

  Future<void> updateUserProfile(User updatedUser) async {
    try {
      // TODO: Implement API call to update user profile
      // For now, we'll just update the local storage
      await initPrefs();
      await _prefs?.setString(userProfileKey, jsonEncode(updatedUser.toJson()));
    } catch (e) {
      print('Error updating user profile: $e');
      throw Exception('Failed to update profile');
    }
  }

  Future<User?> fetchAnyUserProfile({String? username, String? userId}) async {
    try {
      final requestBody = <String, String>{};
      if (userId != null) {
        requestBody['userID'] = userId;
      } else if (username != null) {
        requestBody['username'] = username;
      } else {
        throw Exception('Must provide either username or userId');
      }
      final response = await http.post(Uri.parse(ApiConstants.profile), body: requestBody);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          return User.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      print('❌ Error fetching any user profile: ${e.toString()}');
      return null;
    }
  }

  /// Sends a verification code to the specified email address
  /// Returns the verification code that was sent (for testing purposes)
  /// In production, this should not return the code
  Future<Map<String, dynamic>> sendEmailVerification(String email) async {
    try {
      print('Sending verification code to email: $email');

      final response = await http.post(Uri.parse(ApiConstants.sendEmailVerification), body: {'email': email, 'action': 'register'}, headers: {'Content-Type': 'application/x-www-form-urlencoded'});
      print('Send verification POST URL: ${ApiConstants.sendEmailVerification}');
      print('Send verification POST Body: {email: $email, action: register}');

      print('Send verification response status: ${response.statusCode}');
      print('Send verification response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);

        if (data['responseCode'] == '1') {
          print('Verification code sent successfully');
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
          print('Failed to send verification code: ${data['message']}');
          return {'success': false, 'message': data['message'] ?? 'Failed to send verification code'};
        }
      } else {
        print('Server error with status: ${response.statusCode}');
        return {'success': false, 'message': 'Server error occurred (Status: ${response.statusCode})'};
      }
    } catch (e) {
      print('Send verification exception: $e');
      return {'success': false, 'message': 'Connection error occurred: ${e.toString()}'};
    }
  }

  /// Verifies the email verification code
  Future<Map<String, dynamic>> verifyEmailCode(String email, String code) async {
    try {
      print('Verifying code for email: $email');

      print('Verify email POST URL: ${ApiConstants.verifyEmail}');
      print('Verify email POST Body: {email: $email, code: [REDACTED], action: register}');
      http.Response response = await http.post(Uri.parse(ApiConstants.verifyEmail), body: {'email': email, 'code': code}, headers: {'Content-Type': 'application/x-www-form-urlencoded'});

      // No fallback; verify_email.php is the only endpoint

      print('Verify email response status: ${response.statusCode}');
      print('Verify email response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);

        if (data['responseCode'] == '1') {
          print('Email verification successful');
          return {'success': true, 'message': data['message'] ?? 'Email verified successfully'};
        } else {
          print('Email verification failed: ${data['message']}');
          return {'success': false, 'message': data['message'] ?? 'Email verification failed'};
        }
      } else {
        print('Server error with status: ${response.statusCode}');
        return {'success': false, 'message': 'Server error occurred (Status: ${response.statusCode})'};
      }
    } catch (e) {
      print('Verify email exception: $e');
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
          print('Failed to decode trimmed JSON: $e');
        }
      }
      // As a last resort, return a map with raw message so UI can show something meaningful
      return {'responseCode': '0', 'message': body.length > 200 ? body.substring(0, 200) : body};
    }
  }

  /// Update user online status
  /// Update user activity timestamp (for online status tracking)
  Future<void> updateActivity() async {
    try {
      final userId = await getStoredUserId();
      if (userId == null) {
        return; // User not logged in, silently fail
      }

      final requestBody = <String, String>{
        'userID': userId,
      };

      final response = await http.post(
        Uri.parse(ApiConstants.updateActivity),
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          // Activity updated successfully
          return;
        }
      }
    } catch (e) {
      // Silently fail - activity updates are not critical
      // Only log in debug mode
      if (kDebugMode) {
        print('⚠️ [Auth] Failed to update activity: $e');
      }
    }
  }

  Future<void> updateOnlineStatus(bool isOnline) async {
    try {
      // Skip update if status hasn't changed
      if (_lastKnownOnlineStatus == isOnline) {
        return;
      }

      final userId = await getStoredUserId();
      if (userId == null) {
        print('⚠️ [Auth] Cannot update online status - no user logged in');
        return;
      }

      final requestBody = <String, String>{
        'userID': userId,
        'online': isOnline ? '1' : '0',
      };

      final response = await http.post(
        Uri.parse(ApiConstants.profile),
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          _lastKnownOnlineStatus = isOnline; // Update cached status
          print('✅ [Auth] Online status updated to: ${isOnline ? "online" : "offline"}');
        } else {
          print('⚠️ [Auth] Failed to update online status: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        print('⚠️ [Auth] Failed to update online status - server returned status: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ [Auth] Error updating online status: $e');
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
      print('Registering new user: $username ($email)');

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
          print('⚠️ Could not detect device language: $e');
          deviceLanguage = 'en'; // Fallback to English
        }
      }

      final response = await http.post(
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

      print('Registration response status: ${response.statusCode}');
      print('Registration response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);

        if (data['responseCode'] == '1' || data['success'] == true) {
          print('User registration successful');
          final userId = data['userID']?.toString() ?? data['data']?['userID']?.toString();
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
          print('Registration failed: ${data['message']}');
          return {'success': false, 'message': data['message'] ?? 'Registration failed'};
        }
      } else {
        // Try to parse error response
        try {
          final errorData = _safeJsonDecode(response.body);
          return {'success': false, 'message': errorData['message'] ?? 'Server error occurred'};
        } catch (e) {
          print('Server error with status: ${response.statusCode}');
          return {'success': false, 'message': 'Server error occurred (Status: ${response.statusCode})'};
        }
      }
    } catch (e) {
      print('Registration exception: $e');
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
            print('✅ [Registration] Language set to: ${user.language}');
          } catch (e) {
            print('⚠️ [Registration] Failed to set language: $e');
          }
        }
      } catch (e) {
        print('❌ [Registration] Failed to fetch user profile after registration: $e');
        // If profile fetch fails, we can still proceed - the user is logged in with userID and username
        // The profile can be fetched later when needed
      }

      // Subscribe to user-specific topics after successful registration
      try {
        final firebaseService = FirebaseMessagingService();
        await firebaseService.subscribeToUserTopics();
      } catch (e) {
        print('❌ [Registration] Failed to subscribe to user topics: $e');
      }

      // Update online status to true after successful registration
      try {
        await updateOnlineStatus(true);
      } catch (e) {
        print('⚠️ [Registration] Failed to update online status: $e');
      }

      print('✅ [Registration] User automatically logged in after registration');
    } catch (e) {
      print('❌ [Registration] Error during post-registration login: $e');
      // Don't throw - registration was successful, login setup is optional
    }
  }
}
