import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/constants.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_file/open_file.dart';
import 'notification_service.dart';

class AutoUpdateService {
  static const String _updateCheckUrl = ApiConstants.appUpdate;
  static const String _lastShownUpdateVersionKey = 'last_shown_update_version';
  static const String _lastShownUpdateTimestampKey = 'last_shown_update_timestamp';
  static bool _isDialogShowing = false;

  /// Check if update dialog is currently showing
  static bool get isDialogShowing => _isDialogShowing;

  /// Mark dialog as showing
  static void setDialogShowing(bool showing) {
    _isDialogShowing = showing;
  }

  /// Check if we've already shown an update notification/dialog for this version
  static Future<bool> hasShownUpdateForVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastShownVersion = prefs.getString(_lastShownUpdateVersionKey);
      final lastShownTimestamp = prefs.getInt(_lastShownUpdateTimestampKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // If same version was shown in last 24 hours, don't show again
      if (lastShownVersion == version && (now - lastShownTimestamp) < 24 * 60 * 60 * 1000) {
        return true;
      }

      return false;
    } catch (e) {
      print('⚠️ [AutoUpdate] Error checking shown update: $e');
      return false;
    }
  }

  /// Mark that we've shown update for this version
  static Future<void> markUpdateShownForVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastShownUpdateVersionKey, version);
      await prefs.setInt(_lastShownUpdateTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('⚠️ [AutoUpdate] Error marking update shown: $e');
    }
  }

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
      final String installedVersionCode = packageInfo.buildNumber.isNotEmpty ? packageInfo.buildNumber : '1';

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
          throw const FormatException('Server returned an empty response. The update check endpoint may not be properly configured.');
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
          final Map<String, dynamic> data = jsonDecode(trimmedBody) as Map<String, dynamic>;

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

  static Future<bool> downloadUpdate(String downloadUrl, {Function(int progress, String status)? onProgress}) async {
    final notificationService = NotificationService();

    try {
      print('📥 [AutoUpdate] Starting download from: $downloadUrl');

      // Show initial progress notification
      await notificationService.showUpdateProgressNotification(
        title: 'Updating Skybyn',
        status: 'Preparing download...',
        progress: 0,
        indeterminate: true,
      );

      // Validate URL
      if (downloadUrl.isEmpty) {
        print('❌ [AutoUpdate] Download URL is empty');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Download URL is empty',
          progress: 0,
        );
        return false;
      }

      // Use application documents directory for better compatibility with Android 10+
      // This location is always accessible without storage permissions
      final Directory directory = await getApplicationDocumentsDirectory();
      final File file = File('${directory.path}/app-update.apk');

      // Delete old APK if exists
      if (await file.exists()) {
        await file.delete();
        print('🗑️ [AutoUpdate] Deleted old APK file');
      }

      // Update notification
      await notificationService.showUpdateProgressNotification(
        title: 'Updating Skybyn',
        status: 'Connecting to server...',
        progress: 5,
      );

      // Create request
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode == 200) {
        // Get content length for progress tracking
        final contentLength = streamedResponse.contentLength;
        print('📊 [AutoUpdate] Downloading APK (size: ${contentLength ?? 'unknown'} bytes)');

        // Update notification
        await notificationService.showUpdateProgressNotification(
          title: 'Updating Skybyn',
          status: contentLength != null ? 'Downloading... (${_formatBytes(contentLength)})' : 'Downloading...',
          progress: 10,
        );

        // Stream the response to file to handle large files efficiently
        final bytes = <int>[];
        int downloadedBytes = 0;

        await for (var chunk in streamedResponse.stream) {
          bytes.addAll(chunk);
          downloadedBytes += chunk.length;

          // Update progress every 1% or every 100KB, whichever comes first
          if (contentLength != null && contentLength > 0) {
            final progress = ((downloadedBytes / contentLength) * 90).round() + 10; // 10-100%
            if (downloadedBytes % (contentLength ~/ 100) < chunk.length || downloadedBytes % 100000 < chunk.length) {
              await notificationService.showUpdateProgressNotification(
                title: 'Updating Skybyn',
                status: 'Downloading... ${_formatBytes(downloadedBytes)} / ${_formatBytes(contentLength)} (${progress}%)',
                progress: progress.clamp(0, 95),
              );

              // Call progress callback if provided
              onProgress?.call(progress, 'Downloading...');
            }
          } else {
            // Indeterminate progress if content length unknown
            await notificationService.showUpdateProgressNotification(
              title: 'Updating Skybyn',
              status: 'Downloading... ${_formatBytes(downloadedBytes)}',
              progress: 50,
              indeterminate: true,
            );
          }
        }

        // Update notification
        await notificationService.showUpdateProgressNotification(
          title: 'Updating Skybyn',
          status: 'Saving file...',
          progress: 95,
        );

        // Write to file
        await file.writeAsBytes(bytes);
        final fileSize = await file.length();
        print('✅ [AutoUpdate] APK downloaded successfully to: ${file.path}');
        print('📊 [AutoUpdate] APK size: $fileSize bytes');

        // Verify file was written correctly
        if (fileSize == 0) {
          print('❌ [AutoUpdate] Downloaded file is empty');
          await file.delete();
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'Downloaded file is empty',
            progress: 0,
          );
          return false;
        }

        // Show download complete
        await notificationService.showUpdateProgressNotification(
          title: 'Updating Skybyn',
          status: 'Download complete!',
          progress: 100,
        );

        return true;
      } else {
        print('❌ [AutoUpdate] Download failed with status code: ${streamedResponse.statusCode}');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Download failed (HTTP ${streamedResponse.statusCode})',
          progress: 0,
        );
        // Consume the response stream to avoid memory leaks
        try {
          await streamedResponse.stream.drain();
        } catch (_) {
          // Ignore errors
        }
      }
    } catch (e, stackTrace) {
      // Download failed
      print('❌ [AutoUpdate] Download failed: $e');
      print('❌ [AutoUpdate] Stack trace: $stackTrace');
      await notificationService.showUpdateProgressNotification(
        title: 'Update Failed',
        status: 'Error: ${e.toString()}',
        progress: 0,
      );
    }
    return false;
  }

  /// Format bytes to human-readable string
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static Future<bool> installUpdate({Function(int progress, String status)? onProgress}) async {
    final notificationService = NotificationService();

    try {
      if (Platform.isAndroid) {
        // Request install permission first
        print('🔐 [AutoUpdate] Checking install permission...');

        await notificationService.showUpdateProgressNotification(
          title: 'Updating Skybyn',
          status: 'Requesting installation permission...',
          progress: 100,
        );

        final PermissionStatus status = await Permission.requestInstallPackages.request();

        if (!status.isGranted) {
          print('❌ [AutoUpdate] Install permission not granted. Status: $status');
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'Installation permission denied',
            progress: 0,
          );
          return false;
        }

        print('✅ [AutoUpdate] Install permission granted');

        // Use application documents directory (where we downloaded the file)
        final Directory directory = await getApplicationDocumentsDirectory();
        final File file = File('${directory.path}/app-update.apk');

        if (await file.exists()) {
          final fileSize = await file.length();
          print('✅ [AutoUpdate] APK file found at: ${file.path}');
          print('📊 [AutoUpdate] APK file size: $fileSize bytes');

          // Verify file is not empty
          if (fileSize == 0) {
            print('❌ [AutoUpdate] APK file is empty');
            await notificationService.showUpdateProgressNotification(
              title: 'Update Failed',
              status: 'APK file is empty',
              progress: 0,
            );
            return false;
          }

          await notificationService.showUpdateProgressNotification(
            title: 'Updating Skybyn',
            status: 'Opening installer...',
            progress: 100,
          );

          onProgress?.call(100, 'Opening installer...');

          final result = await _installApk(file.path);

          if (result) {
            // Keep notification showing until user installs
            await notificationService.showUpdateProgressNotification(
              title: 'Update Ready',
              status: 'Tap to install in the system dialog',
              progress: 100,
            );
          } else {
            await notificationService.showUpdateProgressNotification(
              title: 'Update Failed',
              status: 'Failed to open installer',
              progress: 0,
            );
          }

          return result;
        } else {
          print('❌ [AutoUpdate] APK file not found at: ${file.path}');

          // Try alternate location as fallback (for backwards compatibility)
          final altDirectory = await getExternalStorageDirectory();
          if (altDirectory != null) {
            final altFile = File('${altDirectory.path}/app-update.apk');
            if (await altFile.exists()) {
              print('✅ [AutoUpdate] APK file found at alternate location: ${altFile.path}');

              await notificationService.showUpdateProgressNotification(
                title: 'Updating Skybyn',
                status: 'Opening installer...',
                progress: 100,
              );

              return await _installApk(altFile.path);
            }
          }

          print('❌ [AutoUpdate] APK file not found in any expected location');
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'APK file not found',
            progress: 0,
          );
          return false;
        }
      } else {
        print('⚠️ [AutoUpdate] Installation not supported on this platform');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation not supported on this platform',
          progress: 0,
        );
        return false;
      }
    } catch (e, stackTrace) {
      // Installation failed
      print('❌ [AutoUpdate] Installation failed: $e');
      print('❌ [AutoUpdate] Stack trace: $stackTrace');
      await notificationService.showUpdateProgressNotification(
        title: 'Update Failed',
        status: 'Error: ${e.toString()}',
        progress: 0,
      );
      return false;
    }
  }

  /// Cancel the update progress notification
  static Future<void> cancelUpdateProgressNotification() async {
    final notificationService = NotificationService();
    await notificationService.cancelUpdateProgressNotification();
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
    final notificationService = NotificationService();
    
    try {
      print('📦 [AutoUpdate] Opening APK for installation: $apkPath');

      // Verify file exists and is readable
      final file = File(apkPath);
      if (!await file.exists()) {
        print('❌ [AutoUpdate] APK file does not exist: $apkPath');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'APK file not found',
          progress: 0,
        );
        return false;
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        print('❌ [AutoUpdate] APK file is empty: $apkPath');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'APK file is empty',
          progress: 0,
        );
        return false;
      }

      print('📊 [AutoUpdate] APK file verified (size: $fileSize bytes)');

      // Try using platform channel first for better error handling
      if (Platform.isAndroid) {
        try {
          const platform = MethodChannel('no.skybyn.app/installer');
          final result = await platform.invokeMethod('installApk', {'apkPath': apkPath});
          if (result == true) {
            print('✅ [AutoUpdate] Installation intent launched successfully');
            await notificationService.showUpdateProgressNotification(
              title: 'Update Ready',
              status: 'Tap "Install" in the system dialog. If you see a package conflict error, the APK must be signed with the same key as the installed app.',
              progress: 100,
            );
            return true;
          }
        } on PlatformException catch (e) {
          print('❌ [AutoUpdate] Platform channel error: ${e.code} - ${e.message}');
          
          String errorMessage = 'Installation failed';
          if (e.code == 'SECURITY_ERROR' || e.code == 'INSTALL_ERROR') {
            errorMessage = e.message ?? 'Installation failed';
            final messageLower = (e.message ?? '').toLowerCase();
            if (messageLower.contains('conflicts') ||
                messageLower.contains('signature') ||
                messageLower.contains('certificate')) {
              errorMessage = 'Package conflict detected: The update APK must be signed with the same certificate as the installed app. Please ensure the server provides an APK signed with the correct key.';
            }
          } else if (e.code == 'FILE_NOT_FOUND') {
            errorMessage = 'APK file not found';
          }
          
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: errorMessage,
            progress: 0,
          );
          await Future.delayed(const Duration(seconds: 5));
          return false;
        } catch (e) {
          print('⚠️ [AutoUpdate] Platform channel failed, falling back to OpenFile: $e');
          // Fall through to OpenFile method
        }
      }

      // Fallback to OpenFile package
      print('🚀 [AutoUpdate] Attempting to open APK file using OpenFile...');
      final result = await OpenFile.open(apkPath);

      print('📋 [AutoUpdate] OpenFile result type: ${result.type}');
      print('📋 [AutoUpdate] OpenFile result message: ${result.message}');

      if (result.type == ResultType.done) {
        print('✅ [AutoUpdate] APK opened successfully, installation dialog should appear');
        print('ℹ️ [AutoUpdate] User will need to tap "Install" in the system dialog');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Ready',
          status: 'Tap "Install" in the system dialog. If you see a package conflict error, the APK must be signed with the same key as the installed app.',
          progress: 100,
        );
        return true;
      } else if (result.type == ResultType.noAppToOpen) {
        print('❌ [AutoUpdate] No app available to open APK file');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'No app available to install APK',
          progress: 0,
        );
        return false;
      } else if (result.type == ResultType.fileNotFound) {
        print('❌ [AutoUpdate] APK file not found: $apkPath');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'APK file not found',
          progress: 0,
        );
        return false;
      } else if (result.type == ResultType.permissionDenied) {
        print('❌ [AutoUpdate] Permission denied to open APK file');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation permission denied',
          progress: 0,
        );
        return false;
      } else {
        print('❌ [AutoUpdate] Failed to open APK: ${result.message}');
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Failed to open installer: ${result.message}',
          progress: 0,
        );
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ [AutoUpdate] Install APK failed: $e');
      print('❌ [AutoUpdate] Stack trace: $stackTrace');
      await notificationService.showUpdateProgressNotification(
        title: 'Update Failed',
        status: 'Installation error: ${e.toString()}',
        progress: 0,
      );
      await Future.delayed(const Duration(seconds: 5));
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
