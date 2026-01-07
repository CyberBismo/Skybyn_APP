import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  static const String _deviceIdKey = 'device_id';
  static const String _secureDeviceIdKey = 'secure_device_id';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final deviceInfo = <String, dynamic>{};
    final timestamp = DateTime.now().toIso8601String();

    try {
      // Get consistent device ID (UUID) first
      final deviceId = await getDeviceId();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo.addAll({
          'platform': 'Android',
          'timestamp': timestamp,
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'version': androidInfo.version.release,
          'sdkInt': androidInfo.version.sdkInt,
          'device': androidInfo.device,
          'brand': androidInfo.brand,
          'hardware': androidInfo.hardware,
          'product': androidInfo.product,
          'androidId': androidInfo.id, // Keep Android ID separate
          'isPhysicalDevice': androidInfo.isPhysicalDevice,
        });
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo.addAll({
          'platform': 'iOS',
          'timestamp': timestamp,
          'model': iosInfo.utsname.machine,
          'name': iosInfo.name,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'localizedModel': iosInfo.localizedModel,
          'identifierForVendor': iosInfo.identifierForVendor,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
        });
      }

      // Add device ID - use consistent UUID for both 'deviceId' and 'id' (API expects 'id')
      deviceInfo['deviceId'] = deviceId;
      deviceInfo['id'] = deviceId; // API expects 'id' field for device identifier
      
      return deviceInfo;
    } catch (e) {
      // Return basic device info if there's an error
      final deviceId = await getDeviceId();
      return {
        'platform': Platform.isAndroid ? 'Android' : 'iOS',
        'timestamp': timestamp,
        'deviceId': deviceId,
        'id': deviceId, // API expects 'id' field
        'error': e.toString(),
      };
    }
  }

  Future<String> getDeviceId() async {
    try {
      // Step 1: Try to get from secure storage first
      String? deviceId = await _secureStorage.read(key: _secureDeviceIdKey);
      
      // Step 2: Validate if it's a proper UUID
      if (deviceId != null && _isValidUuid(deviceId)) {
        // Cache in SharedPreferences for faster access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_deviceIdKey, deviceId);
        return deviceId;
      }
      
      // Step 3: Check SharedPreferences (fallback)
      final prefs = await SharedPreferences.getInstance();
      deviceId = prefs.getString(_deviceIdKey);
      
      if (deviceId != null && _isValidUuid(deviceId)) {
        // Migrate to secure storage
        await _secureStorage.write(key: _secureDeviceIdKey, value: deviceId);
        return deviceId;
      }
      
      // Step 4: Generate new UUID (Always use UUID v4 for uniqueness)
      // We previously used hardware IDs but they proved non-unique on some android builds
      deviceId = const Uuid().v4();
      
      // Store in both secure storage and SharedPreferences
      await _secureStorage.write(key: _secureDeviceIdKey, value: deviceId);
      await prefs.setString(_deviceIdKey, deviceId);
      
      return deviceId;
    } catch (e) {
      return const Uuid().v4(); // Fallback
    }
  }

  bool _isValidUuid(String id) {
    return RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(id);
  }
}