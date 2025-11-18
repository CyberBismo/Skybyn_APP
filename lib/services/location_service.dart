import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';

class LocationService {
  /// Request location permissions
  Future<bool> requestLocationPermission() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // Check location permission status
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      // Request permission
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  /// Get current user location
  Future<Position?> getCurrentLocation() async {
    try {
      // Request permission first
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        return null;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return position;
    } catch (e) {
      return null;
    }
  }

  /// Update user's location on server
  Future<bool> updateUserLocation(String userId, double latitude, double longitude) async {
    try {
      // Format location as "lat,lng"
      final locationString = '$latitude,$longitude';
      
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/update_location.php'),
        body: {
          'userID': userId,
          'location': locationString,
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' || data['success'] == true) {
          return true;
        } else {
          return false;
        }
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Find users nearby based on location
  Future<List<Map<String, dynamic>>> findNearbyUsers(String userId, double latitude, double longitude, {double radiusKm = 10.0}) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/find_nearby_users.php'),
        body: {
          'userID': userId,
          'latitude': latitude.toString(),
          'longitude': longitude.toString(),
          'radius': radiusKm.toString(),
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          // Direct array format
          return data.map((item) => item as Map<String, dynamic>).toList();
        } else if (data is Map) {
          // Wrapped format
          if (data['responseCode'] == '1' && data['users'] is List) {
            return List<Map<String, dynamic>>.from(data['users']);
          } else if (data['data'] != null && data['data']['users'] is List) {
            return List<Map<String, dynamic>>.from(data['data']['users']);
          } else {
            return [];
          }
        } else {
          return [];
        }
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  /// Calculate distance between two coordinates in kilometers
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000; // Convert to km
  }
}

