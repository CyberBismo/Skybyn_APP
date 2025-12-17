import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  
  // Use a consistent storage key prefix that doesn't depend on application ID
  // This ensures the same device ID is used in both debug and release builds
  static String _getStorageKey(String key) => 'skybyn_device_$key';

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
          'androidId': androidInfo.id, // Android ID - stable hardware identifier
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
      // Step 1: Try to get from secure storage first (persists across app reinstalls on iOS)
      // Use consistent key prefix to ensure same storage in debug and release builds
      String? deviceId = await _secureStorage.read(key: _getStorageKey(_secureDeviceIdKey));
      if (deviceId != null && deviceId.isNotEmpty) {
        // Note: We don't cache in SharedPreferences anymore - secure storage is fast enough
        // and caching creates unnecessary duplication. Secure storage is the source of truth.
        return deviceId;
      }
      
      // Step 2: Check SharedPreferences (for backward compatibility)
      final prefs = await SharedPreferences.getInstance();
      deviceId = prefs.getString(_deviceIdKey);
      if (deviceId != null && deviceId.isNotEmpty) {
        // Migrate to secure storage for future reinstalls
        await _secureStorage.write(key: _getStorageKey(_secureDeviceIdKey), value: deviceId);
        return deviceId;
      }
      
      // Step 3: Generate from hardware ID (persists across reinstalls and factory resets)
      final deviceInfoPlugin = DeviceInfoPlugin();
      String? hardwareId;
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        
        // Use Android ID as hardware identifier
        // Android ID is a stable hardware identifier that:
        // - Persists across app reinstalls
        // - Is unique per device
        // - Only changes on factory reset (which is acceptable)
        // - Doesn't require special permissions
        // Note: Serial number and IMEI are not available in device_info_plus without special permissions
        hardwareId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        // identifierForVendor is the most stable identifier on iOS
        // It persists across app reinstalls and only changes if all apps from vendor are uninstalled
        hardwareId = iosInfo.identifierForVendor;
      }
      
      // If we have a hardware ID, use it (with platform prefix for uniqueness)
      if (hardwareId != null && hardwareId.isNotEmpty && hardwareId != 'unknown') {
        deviceId = Platform.isAndroid 
            ? 'android_$hardwareId' 
            : 'ios_$hardwareId';
        
        // Store in secure storage (survives reinstall) - this is the source of truth
        await _secureStorage.write(key: _getStorageKey(_secureDeviceIdKey), value: deviceId);
        
        return deviceId;
      }
      
      // Step 4: Last resort - Generate new UUID (should rarely happen)
      // This should only occur if hardware identifiers are unavailable
      deviceId = const Uuid().v4();
      await _secureStorage.write(key: _getStorageKey(_secureDeviceIdKey), value: deviceId);
      return deviceId;
    } catch (e) {
      // Final fallback if everything fails
      return const Uuid().v4();
    }
  }
}