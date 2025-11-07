import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import 'device_service.dart';
import 'firebase_messaging_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

class AuthService {
  static String get baseUrl => ApiConstants.apiBase;
  static const String userIdKey = StorageKeys.userId;
  static const String userProfileKey = StorageKeys.userProfile;
  static const String usernameKey = StorageKeys.username;
  SharedPreferences? _prefs;
  // final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;

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
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          // Manually add the userID to the map before creating the User object
          data['id'] = userId.toString(); // Ensure it's a string
          final user = User.fromJson(data);
          // Store user profile locally
          await initPrefs();
          await _prefs?.setString(userProfileKey, json.encode(user.toJson()));
          return user;
        } else {
          print('❌ Profile API did not return responseCode 1');
        }
      } else {
        print('❌ Profile API returned non-200 status: ${response.statusCode}');
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
          return {
            'success': true,
            'message': data['message'] ?? 'Verification code sent successfully',
            'verificationCode': data['verificationCode'], // For testing only
            'status': data['status']?.toString(),
            'alreadyVerified': (data['status']?.toString().toLowerCase() == 'verified'),
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
  }) async {
    try {
      print('Registering new user: $username ($email)');

      // Format date of birth as YYYY-MM-DD for the API
      final dobString = '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

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
          
          // Automatically log the user in after successful registration
          if (userId != null) {
            await _postRegistrationLogin(userId, username);
          }
          
          return {
            'success': true, 
            'message': data['message'] ?? 'Registration successful', 
            'userID': userId, 
            'username': username
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
  Future<void> _postRegistrationLogin(String userId, String username) async {
    try {
      await initPrefs();
      // Store user ID and username (same as login does)
      await _prefs?.setString(userIdKey, userId);
      await _prefs?.setString(usernameKey, username);

      // Try to fetch user profile, but don't fail if it fails
      try {
        await fetchUserProfile(username);
      } catch (e) {
        print('❌ [Registration] Failed to fetch user profile after registration: $e');
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
