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
  static String get _updateCheckUrl => ApiConstants.appUpdate;
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

      if (response.statusCode == 200) {
        // Check if response is JSON
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('application/json') && !contentType.contains('text/json')) {
          // Try to parse anyway, but log warning
        }

        // Validate response body is not empty and looks like JSON
        final trimmedBody = response.body.trim();
        if (trimmedBody.isEmpty) {
          throw const FormatException('Server returned an empty response. The update check endpoint may not be properly configured.');
        }

        // Check if response starts with HTML tags (common error indicator)
        if (trimmedBody.startsWith('<')) {
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
            return UpdateInfo(
              version: installedVersionCode,
              buildNumber: int.tryParse(installedVersionCode) ?? 1,
              downloadUrl: '',
              releaseNotes: message,
              isAvailable: false,
            );
          }
        } catch (jsonError) {
          rethrow;
        }
      } else {
      }
    } catch (e) {
      // Update check failed
    }
    return null;
  }

  static Future<bool> downloadUpdate(String downloadUrl, {Function(int progress, String status)? onProgress}) async {
    final notificationService = NotificationService();

    try {
      // Show initial progress notification
      await notificationService.showUpdateProgressNotification(
        title: 'Updating Skybyn',
        status: 'Preparing download...',
        progress: 0,
        indeterminate: true,
      );

      // Validate URL
      if (downloadUrl.isEmpty) {
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
      }

      // Update notification
      await notificationService.showUpdateProgressNotification(
        title: 'Updating Skybyn',
        status: 'Connecting to server...',
        progress: 5,
      );

      // Create GET request for actual download
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode == 200) {
        // Get content length for progress tracking from the actual download response
        // The server sets Content-Length dynamically based on the actual file size
        int? contentLength = streamedResponse.contentLength;
        
        // Try to get from Content-Length header if contentLength is null or -1
        if (contentLength == null || contentLength == -1) {
          final contentLengthHeader = streamedResponse.headers['content-length'];
          if (contentLengthHeader != null && contentLengthHeader.isNotEmpty) {
            contentLength = int.tryParse(contentLengthHeader.trim());
            if (contentLength != null && contentLength <= 0) {
              contentLength = null; // Invalid size, treat as unknown
            }
          }
        }
        
        // Also check for Content-Range header (for partial downloads/resumable downloads)
        if ((contentLength == null || contentLength == -1) && streamedResponse.headers.containsKey('content-range')) {
          final contentRange = streamedResponse.headers['content-range'];
          if (contentRange != null && contentRange.isNotEmpty) {
            // Parse "bytes 0-12345/67890" format
            final match = RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
            if (match != null) {
              final totalSize = match.group(1);
              if (totalSize != null && totalSize.isNotEmpty) {
                contentLength = int.tryParse(totalSize.trim());
                if (contentLength != null && contentLength <= 0) {
                  contentLength = null; // Invalid size, treat as unknown
                }
              }
            }
          }
        }
        
        // Log the detected file size for debugging
        if (contentLength != null && contentLength > 0) {
        } else {
        }

        // Update notification with initial progress
        await notificationService.showUpdateProgressNotification(
          title: 'Updating Skybyn',
          status: contentLength != null ? 'Downloading... (${_formatBytes(contentLength)})' : 'Downloading...',
          progress: 0,
        );
        
        // Report initial progress to callback
        if (contentLength != null && contentLength > 0) {
          onProgress?.call(0, 'Downloading... 0 / ${_formatBytes(contentLength)} (0%)');
        } else {
          onProgress?.call(0, 'Downloading... 0 bytes');
        }

        // Stream the response to file to handle large files efficiently
        final bytes = <int>[];
        int downloadedBytes = 0;

        double lastReportedProgress = -1.0;
        int lastReportedBytes = 0;
        DateTime lastUpdateTime = DateTime.now();
        await for (var chunk in streamedResponse.stream) {
          bytes.addAll(chunk);
          downloadedBytes += chunk.length;

          // Update progress based on actual download progress (0-100%)
          if (contentLength != null && contentLength > 0) {
            // Calculate progress with decimal precision for smoother updates
            final progressDouble = (downloadedBytes / contentLength) * 100;
            final progress = progressDouble.round().clamp(0, 100);
            
            // Update progress callback more frequently for real-time feedback:
            // - Every 0.1% change (for smooth progress bar)
            // - Every 10KB downloaded (for small files)
            // - At least every 100ms (for UI responsiveness)
            final bytesSinceLastUpdate = downloadedBytes - lastReportedBytes;
            final timeSinceLastUpdate = DateTime.now().difference(lastUpdateTime);
            final progressChange = (progressDouble - lastReportedProgress).abs();
            
            if (progressChange >= 0.1 || bytesSinceLastUpdate >= 10000 || timeSinceLastUpdate.inMilliseconds >= 100) {
              lastReportedProgress = progressDouble;
              lastReportedBytes = downloadedBytes;
              lastUpdateTime = DateTime.now();
              
              // Format progress with one decimal place for more precision
              final progressFormatted = progressDouble.toStringAsFixed(1);
              
              await notificationService.showUpdateProgressNotification(
                title: 'Updating Skybyn',
                status: 'Downloading... ${_formatBytes(downloadedBytes)} / ${_formatBytes(contentLength)} ($progressFormatted%)',
                progress: progress,
              );

              // Call progress callback with precise percentage and detailed status
              final statusText = 'Downloading... ${_formatBytes(downloadedBytes)} / ${_formatBytes(contentLength)} ($progressFormatted%)';
              onProgress?.call(progress, statusText);
            }
          } else {
            // Content length is unknown - we can't calculate accurate percentage
            // Show indeterminate progress and update based on downloaded bytes only
            final bytesSinceLastUpdate = downloadedBytes - lastReportedBytes;
            final timeSinceLastUpdate = DateTime.now().difference(lastUpdateTime);
            
            // Update every 10KB downloaded or every 100ms, whichever comes first
            if (bytesSinceLastUpdate >= 10000 || timeSinceLastUpdate.inMilliseconds >= 100) {
              lastReportedBytes = downloadedBytes;
              lastUpdateTime = DateTime.now();
              
              // Show indeterminate progress (no percentage, just bytes downloaded)
              await notificationService.showUpdateProgressNotification(
                title: 'Updating Skybyn',
                status: 'Downloading... ${_formatBytes(downloadedBytes)}',
                progress: 0, // 0 means indeterminate
                indeterminate: true,
              );
              
              // Call progress callback with 0 (indeterminate)
              onProgress?.call(0, 'Downloading... ${_formatBytes(downloadedBytes)}');
            }
          }
        }

        // Update notification - only show 95% when we're actually saving
        // If content length was unknown, we might have been at 85%, so jump to 95% here
        final finalProgressBeforeSave = contentLength != null && contentLength > 0 ? 95 : 90;
        await notificationService.showUpdateProgressNotification(
          title: 'Updating Skybyn',
          status: 'Saving file...',
          progress: finalProgressBeforeSave,
        );

        // Write to file
        await file.writeAsBytes(bytes);
        final fileSize = await file.length();
        // Verify file was written correctly
        if (fileSize == 0) {
          await file.delete();
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'Downloaded file is empty',
            progress: 0,
          );
          return false;
        }

        // Show download complete - ensure 100% progress
        await notificationService.showUpdateProgressNotification(
          title: 'Updating Skybyn',
          status: 'Download complete!',
          progress: 100,
        );

        // Call progress callback to notify download is complete
        onProgress?.call(100, 'Downloaded');

        return true;
      } else {
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
        // Use application documents directory (where we downloaded the file)
        final Directory directory = await getApplicationDocumentsDirectory();
        final File file = File('${directory.path}/app-update.apk');

        if (await file.exists()) {
          final fileSize = await file.length();
          // Verify file is not empty
          if (fileSize == 0) {
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
          // Try alternate location as fallback (for backwards compatibility)
          final altDirectory = await getExternalStorageDirectory();
          if (altDirectory != null) {
            final altFile = File('${altDirectory.path}/app-update.apk');
            if (await altFile.exists()) {
              await notificationService.showUpdateProgressNotification(
                title: 'Updating Skybyn',
                status: 'Opening installer...',
                progress: 100,
              );

              return await _installApk(altFile.path);
            }
          }
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'APK file not found',
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
    } catch (e, stackTrace) {
      // Installation failed
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
          status: 'APK file not found',
          progress: 0,
        );
        return false;
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'APK file is empty',
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
            await notificationService.showUpdateProgressNotification(
              title: 'Update Ready',
              status: 'Tap "Install" in the system dialog. If you see a package conflict error, the APK must be signed with the same key as the installed app.',
              progress: 100,
            );
            return true;
          }
        } on PlatformException catch (e) {
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
          // Fall through to OpenFile method
        }
      }

      // Fallback to OpenFile package
      final result = await OpenFile.open(apkPath);
      if (result.type == ResultType.done) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Ready',
          status: 'Tap "Install" in the system dialog. If you see a package conflict error, the APK must be signed with the same key as the installed app.',
          progress: 100,
        );
        return true;
      } else if (result.type == ResultType.noAppToOpen) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'No app available to install APK',
          progress: 0,
        );
        return false;
      } else if (result.type == ResultType.fileNotFound) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'APK file not found',
          progress: 0,
        );
        return false;
      } else if (result.type == ResultType.permissionDenied) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Installation permission denied',
          progress: 0,
        );
        return false;
      } else {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Failed to open installer: ${result.message}',
          progress: 0,
        );
        return false;
      }
    } catch (e, stackTrace) {
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
