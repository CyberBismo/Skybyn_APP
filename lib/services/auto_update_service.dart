import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
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
    if (!Platform.isAndroid) {
      print('[Update Check] Skipping - not Android platform');
      return null;
    }

    try {
      print('[Update Check] Starting update check...');
      
      // Get current app version/build number first
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String installedVersionCode = packageInfo.buildNumber.isNotEmpty ? packageInfo.buildNumber : '1';
      print('[Update Check] Current installed version: $installedVersionCode');

      // Build URL with query parameters: c=android&v={buildNumber}
      final uri = Uri.parse(_updateCheckUrl).replace(
        queryParameters: {
          'c': 'android',
          'v': installedVersionCode,
        },
      );
      print('[Update Check] Checking update at: $uri');

      final response = await http.get(uri);
      print('[Update Check] Response status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Check if response is JSON
        final contentType = response.headers['content-type'] ?? '';
        print('[Update Check] Response content-type: $contentType');
        
        if (!contentType.contains('application/json') && !contentType.contains('text/json')) {
          print('[Update Check] Warning: Response is not JSON, but will try to parse anyway');
        }

        // Validate response body is not empty and looks like JSON
        final trimmedBody = response.body.trim();
        if (trimmedBody.isEmpty) {
          print('[Update Check] Error: Server returned an empty response');
          throw const FormatException('Server returned an empty response. The update check endpoint may not be properly configured.');
        }

        // Check if response starts with HTML tags (common error indicator)
        if (trimmedBody.startsWith('<')) {
          print('[Update Check] Error: Server returned HTML instead of JSON');
          throw FormatException(
            'Server returned HTML instead of JSON. The update check endpoint may not be properly configured.',
            trimmedBody,
          );
        }

        print('[Update Check] Response body: $trimmedBody');

        try {
          final Map<String, dynamic> data = jsonDecode(trimmedBody) as Map<String, dynamic>;
          
          // Parse response from app_update.php
          // Response format: { responseCode: 1|0, message: string, url: string, currentVersion: string, yourVersion: string }
          final responseCode = data['responseCode'];
          final downloadUrl = data['url']?.toString() ?? '';
          final latestVersion = data['currentVersion']?.toString() ?? installedVersionCode;
          final message = data['message']?.toString() ?? '';

          print('[Update Check] Parsed response:');
          print('  - responseCode: $responseCode');
          print('  - currentVersion: $latestVersion');
          print('  - yourVersion: ${data['yourVersion']}');
          print('  - downloadUrl: $downloadUrl');
          print('  - message: $message');

          // Check if update is available (responseCode == 1 means update available)
          final isUpdateAvailable = responseCode == 1 && downloadUrl.isNotEmpty;

          if (isUpdateAvailable) {
            print('[Update Check] ✓ Update available! Latest version: $latestVersion, Current: $installedVersionCode');
            // Update available
            return UpdateInfo(
              version: latestVersion,
              buildNumber: int.tryParse(latestVersion) ?? int.tryParse(installedVersionCode) ?? 1,
              downloadUrl: downloadUrl,
              releaseNotes: message.isNotEmpty ? message : 'A new version is available.',
              isAvailable: true,
            );
          } else {
            print('[Update Check] ✓ No update available. Current version is up to date.');
            // No update available
            return UpdateInfo(
              version: installedVersionCode,
              buildNumber: int.tryParse(installedVersionCode) ?? 1,
              downloadUrl: '',
              releaseNotes: message.isNotEmpty ? message : 'No new version available.',
              isAvailable: false,
            );
          }
        } catch (jsonError) {
          print('[Update Check] Error parsing JSON: $jsonError');
          rethrow;
        }
      } else {
        print('[Update Check] Error: HTTP ${response.statusCode} - ${response.reasonPhrase}');
      }
    } catch (e, stackTrace) {
      // Update check failed
      print('[Update Check] ✗ Update check failed: $e');
      print('[Update Check] Stack trace: $stackTrace');
    }
    return null;
  }

  static Future<bool> downloadUpdate(String downloadUrl, {Function(int progress, String status)? onProgress}) async {
    final notificationService = NotificationService();
    // Declare client outside try block so it's accessible in catch block
    http.Client? client;

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
      // Use a client with extended timeout for large file downloads (up to 10 minutes)
      client = http.Client();
      http.StreamedResponse? streamedResponse;
      
      try {
        final request = http.Request('GET', Uri.parse(downloadUrl));
        streamedResponse = await client!.send(request).timeout(
          const Duration(minutes: 10),
          onTimeout: () {
            client?.close();
            throw TimeoutException('Download timeout after 10 minutes');
          },
        );
      } catch (e) {
        client?.close();
        rethrow;
      }

      if (streamedResponse!.statusCode == 200) {
        // Get content length for progress tracking from the actual download response
        // The server sets Content-Length dynamically based on the actual file size
        int? contentLength = streamedResponse.contentLength;
        
        // Try to get from Content-Length header if contentLength is null or -1
        if (contentLength == -1) {
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

        // Stream the response directly to file to handle large files efficiently
        // Open file in write mode (append) to stream chunks directly to disk
        final fileSink = file.openWrite();
        int downloadedBytes = 0;

        double lastReportedProgress = -1.0;
        int lastReportedBytes = 0;
        DateTime lastUpdateTime = DateTime.now();
        
        try {
          await for (var chunk in streamedResponse.stream) {
            // Write chunk directly to file instead of buffering in memory
            fileSink.add(chunk);
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
          
          // Close the file stream after all chunks are written
          await fileSink.flush();
          await fileSink.close();
        } catch (e) {
          // Ensure file is closed even if there's an error
          try {
            await fileSink.close();
          } catch (_) {
            // Ignore errors when closing
          }
          // Delete partial file on error
          if (await file.exists()) {
            await file.delete();
          }
          rethrow;
        } finally {
          // Ensure client is closed
          client?.close();
        }

        // Verify file was written correctly
        final fileSize = await file.length();
        
        // Check if file is empty
        if (fileSize == 0) {
          await file.delete();
          await notificationService.showUpdateProgressNotification(
            title: 'Update Failed',
            status: 'Downloaded file is empty',
            progress: 0,
          );
          return false;
        }
        
        // Verify file size matches expected content length (if available)
        if (contentLength != null && contentLength > 0) {
          if (fileSize != contentLength) {
            // File size mismatch - might be incomplete download
            await file.delete();
            await notificationService.showUpdateProgressNotification(
              title: 'Update Failed',
              status: 'File size mismatch. Expected ${_formatBytes(contentLength)}, got ${_formatBytes(fileSize)}',
              progress: 0,
            );
            return false;
          }
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
        client?.close();
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
    } catch (e) {
      // Ensure client is closed on error
      try {
        client?.close();
      } catch (_) {
        // Ignore errors when closing
      }
      
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

  static Future<bool> installUpdate(BuildContext context, {Function(int progress, String status)? onProgress}) async {
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

          final result = await _installApk(context, file.path);

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

              return await _installApk(context, altFile.path);
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

  static Future<bool> _installApk(BuildContext context, String apkPath) async {
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
            
            // Delete the APK file after opening installer to free up space
            // The installer has already read the file, so it's safe to delete
            try {
              final apkFile = File(apkPath);
              if (await apkFile.exists()) {
                await apkFile.delete();
              }
            } catch (e) {
              // Ignore errors when deleting - file will be cleaned up on next update
            }
            
            // Terminate the app immediately when installer is opened
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            if (context.mounted) Phoenix.rebirth(context);
            return true;
          }
        } on PlatformException catch (e) {
          // MethodChannel not implemented or failed - fall through to OpenFile
          print('MethodChannel installApk failed: ${e.code} - ${e.message}');
        } catch (e) {
          // Fall through to OpenFile method
          print('MethodChannel installApk error: $e');
        }
      }

      // Fallback to OpenFile package
      print('Attempting to open APK file: $apkPath');
      
      // Verify file exists and get file info before opening
      // Note: 'file' variable is already declared above, reuse it
      if (!await file.exists()) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'APK file not found at: $apkPath',
          progress: 0,
        );
        return false;
      }
      
      // fileSize is already declared above, just get URI for logging
      final fileUri = file.uri;
      print('APK file exists: ${await file.exists()}, size: $fileSize bytes, URI: $fileUri');
      
      final result = await OpenFile.open(apkPath);
      print('OpenFile result: type=${result.type}, message=${result.message}');
      
      if (result.type == ResultType.done) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Ready',
          status: 'Tap "Install" in the system dialog. If you see a package conflict error, the APK must be signed with the same key as the installed app.',
          progress: 100,
        );
        
        // Delete the APK file after opening installer to free up space
        // The installer has already read the file, so it's safe to delete
        try {
          if (await file.exists()) {
            await file.delete();
            print('APK file deleted after opening installer');
          }
        } catch (e) {
          print('Error deleting APK file: $e');
          // Ignore errors when deleting - file will be cleaned up on next update
        }
        
        // Terminate the app immediately when installer is opened
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (context.mounted) Phoenix.rebirth(context);
        return true;
      } else if (result.type == ResultType.noAppToOpen) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'No app available to install APK. Please enable "Install unknown apps" permission.',
          progress: 0,
        );
        return false;
      } else if (result.type == ResultType.fileNotFound) {
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'APK file not found: $apkPath',
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
        final errorMsg = result.message?.isNotEmpty == true 
            ? result.message! 
            : 'Unknown error (type: ${result.type})';
        await notificationService.showUpdateProgressNotification(
          title: 'Update Failed',
          status: 'Failed to open installer: $errorMsg',
          progress: 0,
        );
        return false;
      }
      return true;
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
