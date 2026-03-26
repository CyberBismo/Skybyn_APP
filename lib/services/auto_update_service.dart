import 'dart:io';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import '../config/constants.dart';
import 'package:http/http.dart' as http;
import '../utils/http_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_file/open_file.dart';
import 'notification_service.dart';
import 'auth_service.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'dart:isolate';
import 'dart:ui';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  if (kDebugMode) debugPrint('[AutoUpdateService] Callback: task=$id, status=$status, progress=$progress');
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  if (send == null) {
    if (kDebugMode) debugPrint('[AutoUpdateService] Error: Could not find downloader_send_port');
  }
  send?.send([id, status, progress]);
}

class AutoUpdateService {
  static String get _updateCheckUrl => ApiConstants.appUpdate;
  static const String _lastShownUpdateVersionKey = 'last_shown_update_version';
  static const String _lastShownUpdateTimestampKey = 'last_shown_update_timestamp';
  static const String _downloadedUpdateVersionKey = 'downloaded_update_version';
  static bool _isDialogShowing = false;
  static bool _isBackgroundDownload = false; // Flag to track if running in background

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
    }
  }

  static Future<UpdateInfo?> checkForUpdates() async {
    if (!Platform.isAndroid) {
      if (kDebugMode) debugPrint('[Update Check] Skipping - not Android platform');
      return null;
    }

    try {
      if (kDebugMode) debugPrint('[Update Check] Starting update check...');

      // Get current app version (semantic version "1.0.0") instead of build number
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String installedVersion = packageInfo.version;
      if (kDebugMode) debugPrint('[Update Check] Current installed version: $installedVersion');

      // Get stored User ID for staged rollout logic
      final String? userId = await AuthService().getStoredUserId();
      
      // Build URL with query parameters: c=android&v={version}&uid={userId}
      final uri = Uri.parse(_updateCheckUrl).replace(
        queryParameters: {
          'c': 'android',
          'v': installedVersion,
          'uid': userId ?? '0',
        },
      );
      if (kDebugMode) debugPrint('[Update Check] Checking update at: $uri');

      final response = await globalAuthClient.get(uri);
      if (kDebugMode) debugPrint('[Update Check] Response status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Check if response is JSON
        final contentType = response.headers['content-type'] ?? '';
        if (kDebugMode) debugPrint('[Update Check] Response content-type: $contentType');

        if (!contentType.contains('application/json') && !contentType.contains('text/json')) {
          if (kDebugMode) debugPrint('[Update Check] Warning: Response is not JSON, but will try to parse anyway');
        }

        // Validate response body is not empty and looks like JSON
        final trimmedBody = response.body.trim();
        if (trimmedBody.isEmpty) {
          if (kDebugMode) debugPrint('[Update Check] Error: Server returned an empty response');
          throw const FormatException('Server returned an empty response. The update check endpoint may not be properly configured.');
        }

        // Check if response starts with HTML tags (common error indicator)
        if (trimmedBody.startsWith('<')) {
          if (kDebugMode) debugPrint('[Update Check] Error: Server returned HTML instead of JSON');
          throw FormatException(
            'Server returned HTML instead of JSON. The update check endpoint may not be properly configured.',
            trimmedBody,
          );
        }

        if (kDebugMode) debugPrint('[Update Check] Response body: $trimmedBody');

        try {
          final Map<String, dynamic> data = jsonDecode(trimmedBody) as Map<String, dynamic>;
          
          // Parse response from app_update.php
          // Response format: { responseCode: 1|0, message: string, url: string, currentVersion: string, yourVersion: string }
          final responseCode = int.tryParse(data['responseCode']?.toString() ?? '0');
          final downloadUrl = data['url']?.toString() ?? '';
          final latestVersion = data['currentVersion']?.toString() ?? installedVersion;
          final message = data['message']?.toString() ?? '';

          if (kDebugMode) {
            debugPrint('[Update Check] Parsed response:');
            debugPrint('  - responseCode: $responseCode');
            debugPrint('  - currentVersion: $latestVersion');
            debugPrint('  - yourVersion: ${data['yourVersion']}');
            debugPrint('  - downloadUrl: $downloadUrl');
            debugPrint('  - message: $message');
          }

          // Check if update is available (responseCode == 1 means update available)
          final isUpdateAvailable = responseCode == 1 && downloadUrl.isNotEmpty;

          if (isUpdateAvailable) {
            if (kDebugMode) debugPrint('[Update Check] ✓ Update available! Latest version: $latestVersion, Current: $installedVersion');
            // Update available
            return UpdateInfo(
              version: latestVersion,
              buildNumber: int.tryParse(latestVersion.replaceAll('.', '')) ?? 0, // Semantic placeholder
              downloadUrl: downloadUrl,
              releaseNotes: message.isNotEmpty ? message : 'A new version is available.',
              isAvailable: true,
            );
          } else {
            if (kDebugMode) debugPrint('[Update Check] ✓ No update available. Current version is up to date.');
            // No update available
            return UpdateInfo(
              version: installedVersion,
              buildNumber: int.tryParse(installedVersion.replaceAll('.', '')) ?? 0,
              downloadUrl: '',
              releaseNotes: message.isNotEmpty ? message : 'No new version available.',
              isAvailable: false,
            );
          }
        } catch (jsonError) {
          if (kDebugMode) debugPrint('[Update Check] Error parsing JSON: $jsonError');
          rethrow;
        }
      } else {
        if (kDebugMode) debugPrint('[Update Check] Error: HTTP ${response.statusCode} - ${response.reasonPhrase}');
        if (kDebugMode) debugPrint('[Update Check] Response Body: ${response.body}');
      }
    } catch (e, stackTrace) {
      // Update check failed
      if (kDebugMode) debugPrint('[Update Check] ✗ Update check failed: $e');
      if (kDebugMode) debugPrint('[Update Check] Stack trace: $stackTrace');
    }
    return null;
  }

  static Future<bool> downloadUpdate(String downloadUrl, {String? version, Function(int progress, String status)? onProgress}) async {
    final notificationService = NotificationService();

    // 1. Prepare for download tracking
    final ReceivePort port = ReceivePort();
    // Use a unique suffix if possible or be very sure about cleanup
    const portName = 'downloader_send_port';
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(port.sendPort, portName);
    
    final Completer<bool> downloadCompleter = Completer<bool>();

    try {
      // Cleanup old APK if exists
      await deleteDownloadedApk();

      // Show initial notification
      await notificationService.showUpdateProgressNotification(
        title: 'Updating Skybyn...',
        status: 'Downloading update...',
        progress: 0,
      );

      port.listen((dynamic data) async {
        // [id, status, progress]
        final String taskId = data[0] as String;
        final int statusInt = data[1] as int;
        final int progress = data[2] as int;
        
        if (kDebugMode) debugPrint('[AutoUpdateService] Listener: task=$taskId, status=$statusInt, progress=$progress');
        
        // Convert int to enum for safer comparison in 1.12.0+
        final DownloadTaskStatus status = DownloadTaskStatus.values[statusInt];

        if (status == DownloadTaskStatus.running) {
          onProgress?.call(progress, 'Downloading... $progress%');
          // Update system notification in real-time
          notificationService.showUpdateProgressNotification(
            title: 'Update in progress',
            status: 'Downloading update... $progress%',
            progress: progress,
          );
        } else if (status == DownloadTaskStatus.complete) {
          IsolateNameServer.removePortNameMapping('downloader_send_port');
          port.close();
          
          await notificationService.cancelUpdateProgressNotification();
          
          if (version != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_downloadedUpdateVersionKey, version);
            
            // Show "Ready to Install" notification
            await notificationService.showUpdateReadyNotification(version);
          }
          
          downloadCompleter.complete(true);
        } else if (status == DownloadTaskStatus.failed || status == DownloadTaskStatus.canceled) {
          IsolateNameServer.removePortNameMapping('downloader_send_port');
          port.close();
          await notificationService.cancelUpdateProgressNotification();
          downloadCompleter.complete(false);
        }
      });

      // 2. Start the download using flutter_downloader
      final Directory? directory = await getExternalStorageDirectory();
      if (directory == null) {
        IsolateNameServer.removePortNameMapping('downloader_send_port');
        port.close();
        return false;
      }

      await FlutterDownloader.registerCallback(downloadCallback);

      final taskId = await FlutterDownloader.enqueue(
        url: downloadUrl,
        savedDir: directory.path,
        fileName: 'app-update.apk',
        showNotification: false, // Unified notification handled by NotificationService
        openFileFromNotification: false,
        requiresStorageNotLow: true,
      );

      if (!_isBackgroundDownload) {
        return await downloadCompleter.future;
      } else {
        // Even for background downloads, we MUST wait for completion
        // so the WorkManager worker doesn't finish and kill this isolate (and its port listener)
        developer.log('App Update: Waiting for background download to complete...', name: 'AutoUpdateService');
        return await downloadCompleter.future;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoUpdateService] Error downloading update: $e');
      IsolateNameServer.removePortNameMapping('downloader_send_port');
      port.close();
      return false;
    }
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
        await notificationService.showUpdateProgressNotification(
          title: 'Updating Skybyn',
          status: 'Requesting installation permission...',
          progress: 100,
        );

        final PermissionStatus status = await Permission.requestInstallPackages.request();

        if (!status.isGranted) {
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'Installation permission denied',
            progress: 0,
          );
          return false;
        }
        // Use external storage directory (where we downloaded the file)
        final Directory? directory = await getExternalStorageDirectory();
        if (directory == null) {
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'Could not access storage directory',
            progress: 0,
          );
          return false;
        }
        final File file = File('${directory.path}/app-update.apk');

        if (await file.exists()) {
          final fileSize = await file.length();
          // Verify file is not empty
          if (fileSize == 0) {
            await notificationService.showUpdateProgressNotification(
              title: 'Update Failed',
              status: 'Installation file is empty',
              progress: 0,
            );
            return false;
          }

          // If coming from background download, we just notify and proceed with the intent
          // We no longer require a BuildContext.
          
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
              title: 'App Update Available',
              status: 'Tap to install',
              progress: 100,
            );
            
            // Notification remains showing until user installs or dismisses
            // Deletion is now handled by validateAndCleanupApk() on next startup
          } else {
            await notificationService.showUpdateProgressNotification(
              title: 'Update Failed',
              status: 'Failed to open installer',
              progress: 0,
            );
          }

          return result;
        } else {
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'Installation file not found',
            progress: 0,
          );
          return false;
        }
      } else {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation not supported on this platform',
          progress: 0,
        );
        return false;
      }
    } catch (e) {
      // Installation failed
      await notificationService.showUpdateProgressNotification(
        title: 'Update Failed',
        status: 'Error: ${e.toString()}',
        progress: 0,
      );
      return false;
    }
  }

  /// Trigger background update (download and notify)
  /// This is called from WorkManager or background service
  static Future<void> triggerBackgroundUpdate() async {
    _isBackgroundDownload = true;
    final notificationService = NotificationService();
    
    try {
      // 1. Check for update
      final updateInfo = await checkForUpdates();
      
      if (updateInfo != null && updateInfo.isAvailable && updateInfo.downloadUrl.isNotEmpty) {
        // 2. Download update
        // downloadUpdate now internally triggers showUpdateReadyNotification on completion
        await downloadUpdate(updateInfo.downloadUrl, version: updateInfo.version);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoUpdateService] Background update failed: $e');
      await notificationService.cancelUpdateProgressNotification();
    } finally {
      _isBackgroundDownload = false;
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
      return false;
    }
  }

  /// Check if an update has already been downloaded and is ready to install
  static Future<bool> isUpdateDownloaded({String? version}) async {
    try {
      if (!Platform.isAndroid) return false;
      final Directory? directory = await getExternalStorageDirectory();
      if (directory == null) return false;
      
      final File file = File('${directory.path}/app-update.apk');
      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize == 0) return false;

        // If version provided, verify it
        if (version != null) {
          final downloadedVersion = await getDownloadedVersion();
          if (downloadedVersion != version) {
            if (kDebugMode) debugPrint('[AutoUpdateService] Local APK version ($downloadedVersion) mismatch with requested ($version). Cleaning up.');
            await deleteDownloadedApk();
            return false;
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoUpdateService] Error checking downloaded update: $e');
      return false;
    }
  }

  /// Get the version of the downloaded APK from SharedPreferences
  static Future<String?> getDownloadedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_downloadedUpdateVersionKey);
    } catch (e) {
      return null;
    }
  }

  /// Delete the downloaded APK and clear the stored version
  static Future<void> deleteDownloadedApk() async {
    try {
      final Directory? directory = await getExternalStorageDirectory();
      if (directory != null) {
        final File file = File('${directory.path}/app-update.apk');
        if (await file.exists()) {
          await file.delete();
          if (kDebugMode) debugPrint('[AutoUpdateService] Deleted downloaded APK');
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_downloadedUpdateVersionKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoUpdateService] Error deleting APK: $e');
    }
  }

  /// Validate the downloaded APK against current installed version and cleanup if stale
  static Future<void> validateAndCleanupApk() async {
    try {
      if (!Platform.isAndroid) return;

      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String installedVersion = packageInfo.version;
      final String? downloadedVersion = await getDownloadedVersion();

      if (downloadedVersion != null) {
        // Simplified version comparison for purge logic
        // If versions are same, or installed is newer, the APK is stale
        if (_isVersionGreaterOrEqual(installedVersion, downloadedVersion)) {
          if (kDebugMode) debugPrint('[AutoUpdateService] Cleanup: Installed version ($installedVersion) >= Downloaded version ($downloadedVersion). Deleting APK.');
          await deleteDownloadedApk();
        }
      } else {
        // If no version recorded but file exists, delete it to be safe
        final Directory? directory = await getExternalStorageDirectory();
        if (directory != null) {
          final File file = File('${directory.path}/app-update.apk');
          if (await file.exists()) {
            if (kDebugMode) debugPrint('[AutoUpdateService] Cleanup: No version record for existing APK. Deleting.');
            await deleteDownloadedApk();
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoUpdateService] Error during cleanup: $e');
    }
  }

  /// Helper to compare semantic versions (e.g., "1.0.1" vs "1.0.0")
  static bool _isVersionGreaterOrEqual(String v1, String v2) {
    try {
      final parts1 = v1.split('.').map(int.parse).toList();
      final parts2 = v2.split('.').map(int.parse).toList();

      for (var i = 0; i < parts1.length && i < parts2.length; i++) {
        if (parts1[i] > parts2[i]) return true;
        if (parts1[i] < parts2[i]) return false;
      }
      return parts1.length >= parts2.length;
    } catch (e) {
      return v1 == v2; // Fallback to string comparison
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
      return false;
    }
  }

  static Future<bool> _installApk(String apkPath) async {
    final notificationService = NotificationService();
    
    try {
      // Verify file exists and is readable
      final file = File(apkPath);
      if (!await file.exists()) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation file not found',
          progress: 0,
        );
        return false;
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation file is empty',
          progress: 0,
        );
        return false;
      }


      // Try using platform channel first for better error handling
      if (Platform.isAndroid) {
        try {
          const platform = MethodChannel('no.skybyn.app/installer');
          final result = await platform.invokeMethod('installApk', {'apkPath': apkPath});
          if (result == true) {
            return true;
          }
        } on PlatformException catch (e) {
          // MethodChannel not implemented or failed - fall through to OpenFile
          if (kDebugMode) debugPrint('MethodChannel installApk failed: ${e.code} - ${e.message}');
        } catch (e) {
          // Fall through to OpenFile method
          if (kDebugMode) debugPrint('MethodChannel installApk error: $e');
        }
      }

      // Fallback to OpenFile package
      if (kDebugMode) debugPrint('Attempting to open APK file: $apkPath');
      
      // Verify file exists and get file info before opening
      // Note: 'file' variable is already declared above, reuse it
      if (!await file.exists()) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation file not found at: $apkPath',
          progress: 0,
        );
        return false;
      }
      
      // fileSize is already declared above, just get URI for logging
      final fileUri = file.uri;
      if (kDebugMode) debugPrint('APK file exists: ${await file.exists()}, size: $fileSize bytes, URI: $fileUri');

      final result = await OpenFile.open(apkPath);
      if (kDebugMode) debugPrint('OpenFile result: type=${result.type}, message=${result.message}');
      
      if (result.type == ResultType.done) {
        return true;
      } else if (result.type == ResultType.noAppToOpen) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'No app available to install. Please enable "Install unknown apps" permission.',
          progress: 0,
        );
        return false;
      } else if (result.type == ResultType.fileNotFound) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation file not found: $apkPath',
          progress: 0,
        );
        return false;
      } else if (result.type == ResultType.permissionDenied) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation permission denied. Please grant "Install unknown apps" permission in settings.',
          progress: 0,
        );
        return false;
      } else {
        final errorMsg = result.message.isNotEmpty
            ? result.message
            : 'Unknown error (type: ${result.type})';
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Failed to open installer: $errorMsg',
          progress: 0,
        );
        return false;
      }
    } catch (e) {
      await notificationService.showUpdateProgressNotification(
        title: 'Update Failed',
        status: 'Installation error: ${e.toString()}',
        progress: 0,
      );
      await Future.delayed(const Duration(seconds: 5));
      return false;
    }
  }

  /// Manually trigger an update check and show dialog if available
  /// Useful for debugging and forcing the check from UI or background tasks
  static Future<void> manualTriggerUpdateCheck() async {
    if (kDebugMode) debugPrint('[AutoUpdateService] Manual update check triggered');
    final info = await checkForUpdates();
    if (info != null && info.isAvailable) {
      if (kDebugMode) debugPrint('[AutoUpdateService] Manual check found update: ${info.version}');
      // We don't show the dialog here because this might be called from background,
      // but we log it. The UI should use checkForUpdates() directly.
    } else {
      if (kDebugMode) debugPrint('[AutoUpdateService] Manual check: No update available or check failed');
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
