import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:developer' as developer;

class ImageUtils {
  /// Compresses an image file for efficient uploading.
  /// Standardizes format to JPEG for maximum compatibility.
  static Future<File> compressImage(File file, {int quality = 70}) async {
    try {
      // Don't compress if it's already small enough (e.g., < 200KB)
      final int sizeInBytes = await file.length();
      if (sizeInBytes < 200 * 1024) {
        return file;
      }

      final String filePath = file.absolute.path;
      final String extension = p.extension(filePath).toLowerCase();
      
      // Only compress common image formats
      if (!['.jpg', '.jpeg', '.png', '.webp', '.heic'].contains(extension)) {
        return file;
      }

      final Directory tempDir = await getTemporaryDirectory();
      final String targetPath = p.join(
        tempDir.path, 
        "${DateTime.now().millisecondsSinceEpoch}_compressed.jpg"
      );

      final XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
        filePath,
        targetPath,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      if (compressedXFile != null) {
        final File compressedFile = File(compressedXFile.path);
        final int compressedSize = await compressedFile.length();
        
        developer.log(
          '📸 Image Compressed: ${(sizeInBytes / 1024).toStringAsFixed(1)}KB -> ${(compressedSize / 1024).toStringAsFixed(1)}KB',
          name: 'ImageUtils'
        );
        
        return compressedFile;
      }
      
      return file;
    } catch (e) {
      developer.log('❌ Image Compression Error: $e', name: 'ImageUtils');
      return file;
    }
  }

  /// Batch compression for a list of files.
  static Future<List<File>> compressImages(List<File> files) async {
    return Future.wait(files.map((file) => compressImage(file)));
  }
}
