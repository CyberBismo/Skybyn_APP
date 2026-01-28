import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/constants.dart';
import 'auth_service.dart';
import 'device_service.dart';

class ErrorReportingService {
  static final ErrorReportingService _instance = ErrorReportingService._internal();
  factory ErrorReportingService() => _instance;
  ErrorReportingService._internal();

  /// Report an error to the server
  Future<void> reportError(dynamic error, StackTrace? stackTrace) async {
    try {
      // Don't report errors in debug mode unless you really want to test it
      if (kDebugMode && !kReleaseMode) {
        debugPrint('⚠️ [ErrorReporting] Skipped checking in debug mode: $error');
        // Uncomment next line to test in debug mode
        // return; 
      }

      // 1. Get User Info
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      final userId = user?.id ?? 'Guest';

      // 2. Get Device Info
      final deviceService = DeviceService();
      final deviceInfoMap = await deviceService.getDeviceInfo();
      final platform = deviceInfoMap['platform'] ?? 'Unknown';
      final model = deviceInfoMap['model'] ?? 'Unknown';
      final osVersion = deviceInfoMap['version'] ?? deviceInfoMap['systemVersion'] ?? 'Unknown';
      final deviceInfoStr = '$platform $osVersion ($model)';

      // 3. Get App Version
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      // 4. Prepare Payload
      final payload = {
        'user_id': userId,
        'error': error.toString(),
        'stack_trace': stackTrace?.toString() ?? 'No stack trace',
        'device_info': deviceInfoStr,
        'app_version': appVersion,
      };

      // 5. Send to Server
      final response = await http.post(
        Uri.parse(ApiConstants.reportError),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ [ErrorReporting] Error reported successfully.');
      } else {
        debugPrint('⚠️ [ErrorReporting] Failed to report error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ [ErrorReporting] Failed to send error report: $e');
    }
  }
}
