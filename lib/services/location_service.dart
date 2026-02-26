import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../utils/api_utils.dart';
import 'dart:convert';
import 'dart:async';
import '../config/constants.dart';

class LocationService {
  StreamSubscription<Position>? _positionStreamSubscription;
  String? _currentUserId;
  Timer? _locationUpdateTimer;
  bool _isLiveTracking = false;
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

  /// Check if location permission is granted (without requesting)
  Future<bool> hasLocationPermission() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // Check location permission status
    LocationPermission permission = await Geolocator.checkPermission();
    
    return permission == LocationPermission.whileInUse || 
           permission == LocationPermission.always;
  }

  /// Get current user location (only if permission is already granted)
  /// Use requestLocationPermission() first if you need to request permission
  Future<Position?> getCurrentLocation() async {
    try {
      // Check permission without requesting
      final hasPermission = await hasLocationPermission();
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
        final data = safeJsonDecode(response);
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
        final data = safeJsonDecode(response);
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

  /// Start live location tracking
  /// Updates location to server periodically when user has live location sharing enabled
  Future<void> startLiveLocationTracking(String userId) async {
    if (_isLiveTracking) {
      return; // Already tracking
    }

    final hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      return;
    }

    _currentUserId = userId;
    _isLiveTracking = true;

    // Update location every 30 seconds when tracking live
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isLiveTracking) {
        timer.cancel();
        return;
      }

      try {
        final position = await getCurrentLocation();
        if (position != null) {
          await updateUserLocation(userId, position.latitude, position.longitude);
        }
      } catch (e) {
        // Silently handle errors
      }
    });

    // Also listen to position stream for more frequent updates
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // Update every 50 meters
      ),
    ).listen(
      (Position position) async {
        if (_isLiveTracking && _currentUserId != null) {
          await updateUserLocation(_currentUserId!, position.latitude, position.longitude);
        }
      },
      onError: (error) {
        // Silently handle errors
      },
    );
  }

  /// Stop live location tracking
  void stopLiveLocationTracking() {
    _isLiveTracking = false;
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _currentUserId = null;
  }

  /// Check if live location tracking is active
  bool get isLiveTracking => _isLiveTracking;

  /// Dispose resources
  void dispose() {
    stopLiveLocationTracking();
  }
}

