import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const String _deviceIdKey = 'device_id';

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final deviceInfo = <String, dynamic>{};
    final timestamp = DateTime.now().toIso8601String();

    try {
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
          'id': androidInfo.id,
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

      // Add device ID
      deviceInfo['deviceId'] = await getDeviceId();
      
      print('Device Info: $deviceInfo'); // Debug log
      return deviceInfo;
    } catch (e) {
      print('Error getting device info: $e');
      // Return basic device info if there's an error
      return {
        'platform': Platform.isAndroid ? 'Android' : 'iOS',
        'timestamp': timestamp,
        'deviceId': await getDeviceId(),
        'error': e.toString(),
      };
    }
  }

  Future<String> getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString(_deviceIdKey);
      
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await prefs.setString(_deviceIdKey, deviceId);
      }
      
      return deviceId;
    } catch (e) {
      print('Error getting device ID: $e');
      return const Uuid().v4(); // Fallback to new UUID if there's an error
    }
  }
} 