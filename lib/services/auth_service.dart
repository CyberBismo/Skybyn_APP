import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'device_service.dart';
// import 'dart:io' show Platform;
// import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

class AuthService {
  static const String baseUrl = ApiConstants.apiBase;
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
        print('Error initializing SharedPreferences: $e');
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      print('Attempting login for user: $username');

      final deviceService = DeviceService();
      final deviceInfo = await deviceService.getDeviceInfo();
      print('Device info retrieved successfully');

      final response = await http.post(
        Uri.parse(ApiConstants.login),
        body: {
          'user': username,
          'password': password,
          'deviceInfo': json.encode(deviceInfo),
        },
      );

      print('Login response status: ${response.statusCode}');
      print('Login response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['responseCode'] == '1') {
          print('Login successful, storing user data');
          await initPrefs();
          // Convert userID to string to avoid type mismatch
          await _prefs?.setString(userIdKey, data['userID'].toString());
          await _prefs?.setString(usernameKey, username);
          await fetchUserProfile(username);
          return data;
        }

        print('Login failed with response: $data');
        return data;
      } else {
        print('Server error with status: ${response.statusCode}');
        return {
          'responseCode': '0',
          'message': 'Server error occurred (Status: ${response.statusCode})',
        };
      }
    } catch (e) {
      print('Login exception: $e');
      return {
        'responseCode': '0',
        'message': 'Connection error occurred: ${e.toString()}',
      };
    }
  }

  Future<User?> fetchUserProfile(String username) async {
    try {
      print('Fetching user profile for username: $username');
      final userId = await getStoredUserId();
      final requestBody = {'userID': userId};
      print('Profile API request body:');
      print(requestBody);
      final response = await http.post(
        Uri.parse(ApiConstants.profile),
        body: requestBody,
      );
      print('Profile API response status: ${response.statusCode}');
      print('Profile API response body: ${response.body}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Parsed profile API data:');
        print(data);
        if (data['responseCode'] == '1') {
          // Manually add the userID to the map before creating the User object
          data['id'] = userId.toString(); // Ensure it's a string
          final user = User.fromJson(data);
          print('User object created from profile API:');
          print(user);
          // Store user profile locally
          await initPrefs();
          await _prefs?.setString(userProfileKey, json.encode(user.toJson()));
          return user;
        } else {
          print('Profile API did not return responseCode 1');
        }
      } else {
        print('Profile API returned non-200 status');
      }
      return null;
    } catch (e) {
      print('Error fetching user profile: ${e.toString()}');
      return null;
    }
  }

  Future<String?> getStoredUserId() async {
    await initPrefs();
    return _prefs?.getString(userIdKey);
  }

  Future<String?> getStoredUsername() async {
    await initPrefs();
    return _prefs?.getString(usernameKey);
  }

  Future<User?> getStoredUserProfile() async {
    await initPrefs();
    final profileJson = _prefs?.getString(userProfileKey);
    if (profileJson != null) {
      try {
        return User.fromJson(json.decode(profileJson));
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> logout() async {
    await initPrefs();
    await _prefs?.remove(userIdKey);
    await _prefs?.remove(userProfileKey);
  }

  Future<void> updateUserProfile(User updatedUser) async {
    try {
      // TODO: Implement API call to update user profile
      // For now, we'll just update the local storage
      const storage = FlutterSecureStorage();
      await storage.write(
        key: 'user_profile',
        value: jsonEncode(updatedUser.toJson()),
      );
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
      final response = await http.post(
        Uri.parse(ApiConstants.profile),
        body: requestBody,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          return User.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      print('Error fetching any user profile: ${e.toString()}');
      return null;
    }
  }

  /// Sends a verification code to the specified email address
  /// Returns the verification code that was sent (for testing purposes)
  /// In production, this should not return the code
  Future<Map<String, dynamic>> sendEmailVerification(String email) async {
    try {
      print('Sending verification code to email: $email');

      final response = await http.post(
        Uri.parse(ApiConstants.sendEmailVerification),
        body: {
          'email': email,
          'action': 'register',
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      );
      print(
          'Send verification POST URL: ${ApiConstants.sendEmailVerification}');
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
            'alreadyVerified':
                (data['status']?.toString().toLowerCase() == 'verified'),
          };
        } else {
          print('Failed to send verification code: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to send verification code',
          };
        }
      } else {
        print('Server error with status: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Server error occurred (Status: ${response.statusCode})',
        };
      }
    } catch (e) {
      print('Send verification exception: $e');
      return {
        'success': false,
        'message': 'Connection error occurred: ${e.toString()}',
      };
    }
  }

  /// Verifies the email verification code
  Future<Map<String, dynamic>> verifyEmailCode(
      String email, String code) async {
    try {
      print('Verifying code for email: $email');

      print('Verify email POST URL: ${ApiConstants.verifyEmail}');
      print(
          'Verify email POST Body: {email: $email, code: [REDACTED], action: register}');
      http.Response response = await http.post(
        Uri.parse(ApiConstants.verifyEmail),
        body: {
          'email': email,
          'code': code,
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      );

      // No fallback; verify_email.php is the only endpoint

      print('Verify email response status: ${response.statusCode}');
      print('Verify email response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);

        if (data['responseCode'] == '1') {
          print('Email verification successful');
          return {
            'success': true,
            'message': data['message'] ?? 'Email verified successfully',
          };
        } else {
          print('Email verification failed: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Email verification failed',
          };
        }
      } else {
        print('Server error with status: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Server error occurred (Status: ${response.statusCode})',
        };
      }
    } catch (e) {
      print('Verify email exception: $e');
      return {
        'success': false,
        'message': 'Connection error occurred: ${e.toString()}',
      };
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
      return {
        'responseCode': '0',
        'message': body.length > 200 ? body.substring(0, 200) : body,
      };
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
  }) async {
    try {
      print('Registering new user: $username ($email)');

      final response = await http.post(
        Uri.parse(ApiConstants.register),
        body: {
          'email': email,
          'username': username,
          'password': password,
          'firstName': firstName,
          'middleName': middleName ?? '',
          'lastName': lastName,
          'dateOfBirth': dateOfBirth.toIso8601String(),
        },
      );

      print('Registration response status: ${response.statusCode}');
      print('Registration response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['responseCode'] == '1') {
          print('User registration successful');
          return {
            'success': true,
            'message': data['message'] ?? 'Registration successful',
            'userID': data['userID'],
            'username': username,
          };
        } else {
          print('Registration failed: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Registration failed',
          };
        }
      } else {
        print('Server error with status: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Server error occurred (Status: ${response.statusCode})',
        };
      }
    } catch (e) {
      print('Registration exception: $e');
      return {
        'success': false,
        'message': 'Connection error occurred: ${e.toString()}',
      };
    }
  }
}
