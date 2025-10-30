import 'dart:io';
import 'dart:convert';
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

  static String _composeDownloadUrl(String platform, String version) {
    final uri = Uri.parse(_updateDownloadUrl).replace(queryParameters: {
      'platform': platform,
      'version': version,
    });
    return uri.toString();
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
