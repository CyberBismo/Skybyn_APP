import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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

  // On iOS, Keychain (used by FlutterSecureStorage) survives app uninstalls —
  // so a hardware-derived ID written here persists through reinstalls.
  // On Android, EncryptedSharedPreferences survives reinstalls as long as the
  // signing key and user account are the same.
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final deviceInfo = <String, dynamic>{};
    final timestamp = DateTime.now().toIso8601String();

    try {
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
          'androidId': androidInfo.id,
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

      deviceInfo['deviceId'] = deviceId;
      deviceInfo['id'] = deviceId;
      return deviceInfo;
    } catch (e) {
      final deviceId = await getDeviceId();
      return {
        'platform': Platform.isAndroid ? 'Android' : 'iOS',
        'timestamp': timestamp,
        'deviceId': deviceId,
        'id': deviceId,
        'error': e.toString(),
      };
    }
  }

  Future<String> getDeviceId() async {
    try {
      // 1. Check secure storage first — on iOS this survives uninstalls via
      //    Keychain, so a previously computed hardware ID is recovered here.
      final stored = await _secureStorage.read(key: _secureDeviceIdKey);
      if (stored != null && _isValidUuid(stored)) {
        // Keep SharedPreferences in sync for fast access.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_deviceIdKey, stored);
        return stored;
      }

      // 2. Derive a deterministic ID from hardware identifiers.
      //    Same hardware always produces the same UUID — closest to a serial
      //    number without requiring special permissions.
      final hardwareId = await _deriveHardwareId();
      if (hardwareId != null) {
        await _persist(hardwareId);
        return hardwareId;
      }

      // 3. Fallback: check SharedPreferences (migration / partial clear).
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_deviceIdKey);
      if (cached != null && _isValidUuid(cached)) {
        await _secureStorage.write(key: _secureDeviceIdKey, value: cached);
        return cached;
      }

      // 4. Last resort: random UUID (e.g. emulators with no stable hardware IDs).
      final fallback = const Uuid().v4();
      await _persist(fallback);
      return fallback;
    } catch (e) {
      return const Uuid().v4();
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Builds a UUID from stable hardware identifiers using SHA-256.
  ///
  /// Android: ANDROID_ID (stable per user+signing-key+device, resets only on
  ///   factory reset) combined with immutable hardware fields.
  /// iOS: identifierForVendor (stable until ALL vendor apps are removed) plus
  ///   machine model string. Combined with Keychain persistence above, the ID
  ///   survives reinstalls even if identifierForVendor were to change.
  Future<String?> _deriveHardwareId() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      String raw;

      if (Platform.isAndroid) {
        final info = await deviceInfoPlugin.androidInfo;

        // ANDROID_ID is null or '9774d56d682e549c' on some emulators/rooted
        // devices — treat those as unusable.
        final androidId = info.id;
        if (androidId.isEmpty ||
            androidId == '9774d56d682e549c' ||
            !info.isPhysicalDevice) {
          return null;
        }

        raw = [
          androidId,
          info.manufacturer,
          info.model,
          info.brand,
          info.hardware,
        ].join('|');
      } else if (Platform.isIOS) {
        final info = await deviceInfoPlugin.iosInfo;
        final idfv = info.identifierForVendor;
        if (idfv == null || idfv.isEmpty || !info.isPhysicalDevice) {
          return null;
        }
        raw = [idfv, info.utsname.machine, info.systemName].join('|');
      } else {
        return null;
      }

      return _hashToUuid(raw);
    } catch (_) {
      return null;
    }
  }

  /// SHA-256 hash of [input] formatted as a UUID (variant 1, version 8).
  String _hashToUuid(String input) {
    final bytes = sha256.convert(utf8.encode('skybyn:$input')).bytes;

    // Set version (4 bits) = 8 (custom/hash-based) and variant bits.
    final b = List<int>.from(bytes.take(16));
    b[6] = (b[6] & 0x0f) | 0x80; // version 8
    b[8] = (b[8] & 0x3f) | 0x80; // variant 1

    String h(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final hex = b.map(h).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  Future<void> _persist(String id) async {
    await _secureStorage.write(key: _secureDeviceIdKey, value: id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, id);
  }

  bool _isValidUuid(String id) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(id);
  }
}
