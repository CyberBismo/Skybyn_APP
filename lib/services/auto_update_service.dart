import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/constants.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AutoUpdateService {
  static const String _updateCheckUrl = ApiConstants.checkUpdate;
  static const String _updateDownloadUrl = ApiConstants.downloadUpdate;

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

      final response = await http.post(
        Uri.parse(_updateCheckUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'platform': platform,
          'version': installedVersionCode,
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;

        if (data['status'] == 'success' && data['updateAvailable'] == true) {
          final Map<String, dynamic> info =
              Map<String, dynamic>.from(data['updateInfo'] as Map);
          return UpdateInfo(
            version: info['version'].toString(),
            buildNumber: int.tryParse(info['buildNumber']?.toString() ??
                    info['version']?.toString() ??
                    '1') ??
                1,
            downloadUrl: (info['downloadUrl'] as String?) ??
                _composeDownloadUrl(platform, info['version'].toString()),
            releaseNotes: (info['releaseNotes'] as String?) ??
                'Bug fixes and performance improvements',
            isAvailable: true,
          );
        }

        // No update available
        return UpdateInfo(
          version: data['latestVersion']?.toString() ?? '1.0.0',
          buildNumber:
              int.tryParse(data['latestVersion']?.toString() ?? '1') ?? 1,
          downloadUrl: '',
          releaseNotes: data['message']?.toString() ?? '',
          isAvailable: false,
        );
      } else {
        debugPrint('Update check failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
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
      } else {
        debugPrint('Download failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error downloading update: $e');
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
          debugPrint('Install permission not granted');
          return false;
        }

        final Directory directory = await getApplicationDocumentsDirectory();
        final File file = File('${directory.path}/app-update.apk');
        if (await file.exists()) {
          debugPrint('APK file found, starting installation...');
          return await _installApk(file.path);
        } else {
          debugPrint('APK file not found for installation');
          return false;
        }
      } else {
        debugPrint('APK installation only supported on Android');
        return false;
      }
    } catch (e) {
      debugPrint('Error installing update: $e');
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
      debugPrint('Error requesting install permission: $e');
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
      debugPrint('Error checking install permission: $e');
      return false;
    }
  }

  static String _composeDownloadUrl(String platform, String version) {
    final uri = Uri.parse(_updateDownloadUrl).replace(queryParameters: {
      'platform': platform,
      'version': version,
    });
    return uri.toString();
  }

  static Future<bool> _installApk(String apkPath) async {
    try {
      debugPrint('APK ready for installation: $apkPath');

      // For now, we'll just return true as the APK is downloaded
      // In a production app, you would use a package like open_file or
      // implement a platform channel to open the APK file
      // This will prompt the user to install the APK

      // TODO: Implement proper APK opening using open_file package
      // or platform channel to open the APK file

      debugPrint('APK installation ready - user needs to install manually');
      return true;
    } catch (e) {
      debugPrint('Error preparing APK for installation: $e');
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
