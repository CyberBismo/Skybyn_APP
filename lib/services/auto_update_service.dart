import 'dart:io';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import '../config/constants.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AutoUpdateService {
  static const String _updateCheckUrl = ApiConstants.appUpdate;

  static Future<UpdateInfo?> checkForUpdates() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String platform = 'unknown';

      if (Platform.isAndroid) {
        await deviceInfo.androidInfo; // Ensures plugin works; not used directly
        platform = 'android';
      } else if (Platform.isIOS) {
        await deviceInfo.iosInfo;
        platform = 'ios';
      }

      // Use the real build number from package info (version code on Android)
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String installedVersionCode =
          packageInfo.buildNumber.isNotEmpty ? packageInfo.buildNumber : '1';

      // Build URL with query parameters: c=platform&v=version
      final uri = Uri.parse(_updateCheckUrl).replace(queryParameters: {
        'c': platform,
        'v': installedVersionCode,
      });

      final response = await http.get(uri);

      // Log response for debugging
      print('📡 [AutoUpdate] Response status: ${response.statusCode}');
      print('📡 [AutoUpdate] Response headers: ${response.headers}');
      print('📡 [AutoUpdate] Response body (first 200 chars): ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');

      if (response.statusCode == 200) {
        // Check if response is JSON
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('application/json') && !contentType.contains('text/json')) {
          print('⚠️ [AutoUpdate] Unexpected content type: $contentType');
          // Try to parse anyway, but log warning
        }

        // Validate response body is not empty and looks like JSON
        final trimmedBody = response.body.trim();
        if (trimmedBody.isEmpty) {
          print('❌ [AutoUpdate] Empty response body');
          throw FormatException('Server returned an empty response. The update check endpoint may not be properly configured.');
        }

        // Check if response starts with HTML tags (common error indicator)
        if (trimmedBody.startsWith('<')) {
          print('❌ [AutoUpdate] Server returned HTML instead of JSON. Response: $trimmedBody');
          throw FormatException(
            'Server returned HTML instead of JSON. The update check endpoint may not be properly configured.',
            trimmedBody,
          );
        }

        try {
          final Map<String, dynamic> data =
              jsonDecode(trimmedBody) as Map<String, dynamic>;

          // Parse new JSON format: responseCode, message, optional url
          final responseCode = data['responseCode'];
          final message = data['message']?.toString() ?? '';

          if (responseCode == 1) {
            // Update available
            final url = data['url']?.toString() ?? '';
            return UpdateInfo(
              version: installedVersionCode, // Use current version as placeholder
              buildNumber: int.tryParse(installedVersionCode) ?? 1,
              downloadUrl: url,
              releaseNotes: message,
              isAvailable: true,
            );
          } else if (responseCode == 0) {
            // No update available
            return UpdateInfo(
              version: installedVersionCode,
              buildNumber: int.tryParse(installedVersionCode) ?? 1,
              downloadUrl: '',
              releaseNotes: message,
              isAvailable: false,
            );
          } else {
            print('⚠️ [AutoUpdate] Unknown responseCode: $responseCode');
            return UpdateInfo(
              version: installedVersionCode,
              buildNumber: int.tryParse(installedVersionCode) ?? 1,
              downloadUrl: '',
              releaseNotes: message,
              isAvailable: false,
            );
          }
        } catch (jsonError) {
          print('❌ [AutoUpdate] JSON decode error: $jsonError');
          print('❌ [AutoUpdate] Response body: ${response.body}');
          rethrow;
        }
      } else {
        print('❌ [AutoUpdate] HTTP error: ${response.statusCode}');
        print('❌ [AutoUpdate] Response body: ${response.body}');
      }
    } catch (e) {
      // Update check failed
      print('❌ [AutoUpdate] Update check failed: $e');
    }
    return null;
  }

  static Future<bool> downloadUpdate(String downloadUrl) async {
    try {
      final http.Response response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode == 200) {
        final Directory directory = await getApplicationDocumentsDirectory();
        final File file = File('${directory.path}/app-update.apk');
        await file.writeAsBytes(response.bodyBytes);
        return true;
      }
    } catch (e) {
      // Download failed
      print('❌ [AutoUpdate] Download failed: $e');
    }
    return false;
  }

  static Future<bool> installUpdate() async {
    try {
      if (Platform.isAndroid) {
        // Request install permission
        final PermissionStatus status =
            await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          return false;
        }

        final Directory directory = await getApplicationDocumentsDirectory();
        final File file = File('${directory.path}/app-update.apk');
        if (await file.exists()) {
          return await _installApk(file.path);
        } else {
          return false;
        }
      } else {
        return false;
      }
    } catch (e) {
      // Installation failed
      print('❌ [AutoUpdate] Installation failed: $e');
      return false;
    }
  }

  static Future<bool> requestInstallPermission() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.request();
        return status.isGranted;
      }
      return false;
    } catch (e) {
      print('❌ [AutoUpdate] Request install permission failed: $e');
      return false;
    }
  }

  static Future<bool> hasInstallPermission() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.status;
        return status.isGranted;
      }
      return false;
    } catch (e) {
      print('❌ [AutoUpdate] Has install permission failed: $e');
      return false;
    }
  }

  static Future<bool> _installApk(String apkPath) async {
    try {
      // For now, we'll just return true as the APK is downloaded
      // In a production app, you would use a package like open_file or
      // implement a platform channel to open the APK file
      // This will prompt the user to install the APK

      // TODO: Implement proper APK opening using open_file package
      // or platform channel to open the APK file

      return true;
    } catch (e) {
      print('❌ [AutoUpdate] Install APK failed: $e');
      return false;
    }
  }
}

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String releaseNotes;
  final bool isAvailable;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isAvailable,
  });
}
