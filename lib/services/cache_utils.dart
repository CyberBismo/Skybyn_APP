import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:developer' as developer;
import 'skybyn_cache_manager.dart';

class CacheUtils {
  /// Calculates the total size of the app's cache in bytes.
  static Future<int> getCacheSize() async {
    int totalSize = 0;
    try {
      // 1. Check temporary directory
      final tempDir = await getTemporaryDirectory();
      totalSize += await _getDirectorySize(tempDir);

      // 2. Check application cache directory (if distinct)
      // Note: On some platforms this is handled by DefaultCacheManager
      
      return totalSize;
    } catch (e) {
      developer.log('Error calculating cache size: $e', name: 'CacheUtils');
      return 0;
    }
  }

  /// Formats bytes into a human-readable string (e.g., "1.2 MB").
  static String formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes > 0) ? (bytes.toString().length - 1) ~/ 3 : 0;
    return '${(bytes / (1024 * (i > 0 ? i : 0 + 1) == 0 ? 1 : math.pow(1024, i))).toStringAsFixed(decimals)} ${suffixes[i]}';
  }
  
  // Custom manual format to avoid dependency on dart:math if possible or just use it
  static String formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Clears the app's internal cache and temporary files.
  static Future<bool> clearCache() async {
    try {
      // 1. Clear image caches
      await DefaultCacheManager().emptyCache();
      await SkybynCacheManager().emptyCache();

      // 2. Delete temporary directory contents
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        final List<FileSystemEntity> children = tempDir.listSync();
        for (final child in children) {
          try {
            await child.delete(recursive: true);
          } catch (e) {
            // Some files might be in use, skip them
          }
        }
      }

      developer.log('App cache cleared successfully', name: 'CacheUtils');
      return true;
    } catch (e) {
      developer.log('Error clearing cache: $e', name: 'CacheUtils');
      return false;
    }
  }

  static Future<int> _getDirectorySize(Directory directory) async {
    int totalSize = 0;
    try {
      if (await directory.exists()) {
        await for (final FileSystemEntity entity in directory.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      // Ignore directory list errors
    }
    return totalSize;
  }
}
