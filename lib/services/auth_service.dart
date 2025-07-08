import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'device_service.dart';
import 'notification_service.dart';
// import 'dart:io' show Platform;
// import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String baseUrl = 'https://api.skybyn.no';
  static const String userIdKey = 'user_id';
  static const String userProfileKey = 'user_profile';
  static const String usernameKey = 'username';
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
        Uri.parse('$baseUrl/login.php'),
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
          await _prefs?.setString(userIdKey, data['userID']);
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
      print('Fetching user profile for username: ' + username);
      final userId = await getStoredUserId();
      final requestBody = {'userID': userId};
      print('Profile API request body:');
      print(requestBody);
      final response = await http.post(
        Uri.parse('$baseUrl/profile.php'),
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
          data['id'] = userId; 
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
      final storage = FlutterSecureStorage();
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
        Uri.parse('$baseUrl/profile.php'),
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
} 