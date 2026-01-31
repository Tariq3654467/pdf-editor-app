import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../models/pdf_file.dart';
import 'pdf_service.dart';
import 'pdf_preferences_service.dart';
import 'pdf_cache_service.dart';

/// Service for managing all PDFs in app-specific storage
/// This ensures all files are managed internally, no external file manager dependency
class PDFStorageService {
  static const MethodChannel _fileChannel = MethodChannel('com.example.pdf_editor_app/file_intent');
  /// Get app's PDF directory (where all PDFs are stored)
  static Future<Directory> getAppPDFDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory('${directory.path}/PDFs');
    
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }
    
    return pdfDirectory;
  }
  
  /// Copy content URI to app storage
  static Future<String?> _copyContentUriToAppStorage(String contentUri) async {
    try {
      if (kIsWeb) return null;
      
      print('PDFStorageService: Copying content URI: $contentUri');
      final String? tempPath = await _fileChannel.invokeMethod('copyContentUriToCache', contentUri)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              print('PDFStorageService: Content URI copy timeout');
              return null;
            },
          )
          .catchError((e) {
            print('PDFStorageService: Error copying content URI: $e');
            return null;
          });
      
      if (tempPath == null) {
        print('PDFStorageService: Failed to copy content URI');
        return null;
      }
      
      // Now copy from temp cache to app PDF directory
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        print('PDFStorageService: Copied file does not exist: $tempPath');
        return null;
      }
      
      final pdfDirectory = await getAppPDFDirectory();
      final fileName = path.basename(tempPath);
      
      // Handle duplicate names
      var targetPath = path.join(pdfDirectory.path, fileName);
      var targetFile = File(targetPath);
      int counter = 1;
      
      while (await targetFile.exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        final newFileName = '${nameWithoutExt}_$counter$ext';
        targetPath = path.join(pdfDirectory.path, newFileName);
        targetFile = File(targetPath);
        counter++;
      }
      
      // Copy from temp to app storage
      await tempFile.copy(targetPath);
      
      // Create PDFFile object and add to cache
      final stat = await targetFile.stat();
      final pdfFile = PDFFile(
        name: path.basename(targetPath),
        date: PDFService.formatDate(stat.modified),
        size: PDFService.formatFileSize(stat.size),
        isFavorite: false,
        filePath: targetPath,
        lastAccessed: DateTime.now(),
        folderPath: pdfDirectory.path,
        folderName: 'App Files',
        dateModified: stat.modified,
        fileSizeBytes: stat.size,
      );
      
      // Verify file exists before updating cache
      if (!await targetFile.exists()) {
        print('PDFStorageService: ERROR - File was not copied: $targetPath');
        return null;
      }
      
      final actualFileSize = await targetFile.length();
      if (actualFileSize == 0) {
        print('PDFStorageService: ERROR - Copied file is empty: $targetPath');
        return null;
      }
      
      print('PDFStorageService: Verified copied file exists: $targetPath (${actualFileSize} bytes)');
      
      // Update cache with verified file
      await PDFCacheService.addPDFToCache(pdfFile);
      await PDFPreferencesService.setLastAccessed(targetPath);
      
      print('PDFStorageService: Copied content URI to app storage: $targetPath');
      return targetPath;
    } catch (e) {
      print('PDFStorageService: Error copying content URI to app storage: $e');
      return null;
    }
  }

  /// Copy external PDF to app storage
  /// Returns the new path in app storage
  static Future<String?> copyToAppStorage(String sourcePath) async {
    try {
      // Handle content URIs FIRST - before any File operations
      if (sourcePath.startsWith('content://')) {
        print('PDFStorageService: Detected content URI, copying: $sourcePath');
        final result = await _copyContentUriToAppStorage(sourcePath);
        if (result != null) {
          print('PDFStorageService: Successfully copied content URI to: $result');
          return result;
        } else {
          print('PDFStorageService: Failed to copy content URI: $sourcePath');
          return null;
        }
      }
      
      // For regular file paths, check if file exists
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        print('PDFStorageService: Source file does not exist: $sourcePath');
        return null;
      }
      
      final pdfDirectory = await getAppPDFDirectory();
      final fileName = path.basename(sourcePath);
      
      // Handle duplicate names
      var targetPath = path.join(pdfDirectory.path, fileName);
      var targetFile = File(targetPath);
      int counter = 1;
      
      while (await targetFile.exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        final newFileName = '${nameWithoutExt}_$counter$ext';
        targetPath = path.join(pdfDirectory.path, newFileName);
        targetFile = File(targetPath);
        counter++;
      }
      
      // Copy file to app storage
      await sourceFile.copy(targetPath);
      
      // Create PDFFile object and add to cache
      final stat = await targetFile.stat();
      final pdfFile = PDFFile(
        name: path.basename(targetPath),
        date: PDFService.formatDate(stat.modified),
        size: PDFService.formatFileSize(stat.size),
        isFavorite: false,
        filePath: targetPath,
        lastAccessed: DateTime.now(), // Mark as recently accessed
        folderPath: pdfDirectory.path,
        folderName: 'App Files',
        dateModified: stat.modified,
        fileSizeBytes: stat.size,
      );
      
      // PHASE 2: Verify file exists before updating cache
      if (!await targetFile.exists()) {
        print('PDFStorageService: ERROR - File was not copied: $targetPath');
        return null;
      }
      
      final actualFileSize = await targetFile.length();
      if (actualFileSize == 0) {
        print('PDFStorageService: ERROR - Copied file is empty: $targetPath');
        return null;
      }
      
      print('PDFStorageService: Verified copied file exists: $targetPath (${actualFileSize} bytes)');
      
      // PHASE 2: Update cache with verified file
      await PDFCacheService.addPDFToCache(pdfFile);
      
      // Mark as recently accessed
      await PDFPreferencesService.setLastAccessed(targetPath);
      
      print('PDFStorageService: Copied PDF to app storage: $targetPath');
      return targetPath;
    } catch (e) {
      print('PDFStorageService: Error copying to app storage: $e');
      return null;
    }
  }
  
  /// Save PDF bytes to app storage
  /// Returns the path where PDF was saved
  static Future<String?> savePDFBytes(
    List<int> bytes,
    String fileName,
  ) async {
    try {
      final pdfDirectory = await getAppPDFDirectory();
      
      // Handle duplicate names
      var targetPath = path.join(pdfDirectory.path, fileName);
      var targetFile = File(targetPath);
      int counter = 1;
      
      while (await targetFile.exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        final newFileName = '${nameWithoutExt}_$counter$ext';
        targetPath = path.join(pdfDirectory.path, newFileName);
        targetFile = File(targetPath);
        counter++;
      }
      
      // Write bytes to file
      await targetFile.writeAsBytes(bytes);
      
      // Create PDFFile object and add to cache
      final stat = await targetFile.stat();
      final pdfFile = PDFFile(
        name: path.basename(targetPath),
        date: PDFService.formatDate(stat.modified),
        size: PDFService.formatFileSize(stat.size),
        isFavorite: false,
        filePath: targetPath,
        lastAccessed: DateTime.now(), // Mark as recently accessed
        folderPath: pdfDirectory.path,
        folderName: 'App Files',
        dateModified: stat.modified,
        fileSizeBytes: stat.size,
      );
      
      // PHASE 2: Verify file exists before updating cache
      if (!await targetFile.exists()) {
        print('PDFStorageService: ERROR - File was not saved: $targetPath');
        throw Exception('Failed to save PDF file');
      }
      
      final actualFileSize = await targetFile.length();
      if (actualFileSize == 0) {
        print('PDFStorageService: ERROR - File is empty: $targetPath');
        throw Exception('Saved PDF file is empty');
      }
      
      print('PDFStorageService: Verified file exists: $targetPath (${actualFileSize} bytes)');
      
      // PHASE 2: Update cache with verified file - CRITICAL: Must complete before returning
      await PDFCacheService.addPDFToCache(pdfFile);
      print('PDFStorageService: Added PDF to cache: ${pdfFile.name}');
      
      // Mark as recently accessed
      await PDFPreferencesService.setLastAccessed(targetPath);
      print('PDFStorageService: Marked as recently accessed: $targetPath');
      
      // PHASE 2: App-storage-only - removed external storage saving
      // All files are managed internally in app storage
      
      print('PDFStorageService: Saved PDF to app storage: $targetPath');
      return targetPath;
    } catch (e) {
      print('PDFStorageService: Error saving PDF bytes: $e');
      return null;
    }
  }
  
  /// Check if a PDF is in app storage
  static Future<bool> isInAppStorage(String filePath) async {
    try {
      final pdfDirectory = await getAppPDFDirectory();
      return filePath.startsWith(pdfDirectory.path);
    } catch (e) {
      return false;
    }
  }
  
  /// Ensure PDF is in app storage (copy if not)
  static Future<String> ensureInAppStorage(String filePath) async {
    try {
      print('PDFStorageService: ensureInAppStorage called with: $filePath');
      
      // For content URIs, always copy to app storage (don't check isInAppStorage)
      if (filePath.startsWith('content://')) {
        print('PDFStorageService: Content URI detected, copying to app storage');
        final newPath = await copyToAppStorage(filePath);
        if (newPath != null && newPath.isNotEmpty) {
          print('PDFStorageService: Content URI copied successfully: $newPath');
          return newPath;
        } else {
          print('PDFStorageService: WARNING - Failed to copy content URI, returning original');
          // Don't return content URI as fallback - it won't work for file operations
          throw Exception('Failed to copy content URI to app storage');
        }
      }
      
      // Check if already in app storage (for regular file paths)
      if (await isInAppStorage(filePath)) {
        print('PDFStorageService: File already in app storage: $filePath');
        return filePath;
      }
      
      // Copy to app storage for regular file paths
      print('PDFStorageService: Copying regular file path to app storage');
      final newPath = await copyToAppStorage(filePath);
      if (newPath != null && newPath.isNotEmpty) {
        print('PDFStorageService: File copied successfully: $newPath');
        return newPath;
      }
      
      // If copy failed, return original path (fallback)
      print('PDFStorageService: Copy failed, returning original path: $filePath');
      return filePath;
    } catch (e, stackTrace) {
      print('PDFStorageService: Error ensuring in app storage: $e');
      print('PDFStorageService: Stack trace: $stackTrace');
      rethrow; // Re-throw so callers can handle the error
    }
  }
  
  /// Save PDF to external storage (Downloads folder) so it's visible in file manager
  /// This is a convenience method - files are always saved in app storage first
  static Future<void> _saveToExternalStorage(String sourcePath, String fileName) async {
    try {
      // Try to get external storage directory
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) return;
      
      // Navigate to Downloads folder
      // On Android, external storage is typically at /storage/emulated/0/Android/data/package/files
      // We'll try to save to a "PDFs" folder in external storage
      final downloadsPath = '${externalDir.path}/PDFs';
      final downloadsDir = Directory(downloadsPath);
      
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      
      // Copy file to external storage
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        final targetPath = path.join(downloadsPath, fileName);
        final targetFile = File(targetPath);
        
        // Handle duplicates
        var finalTargetPath = targetPath;
        var finalTargetFile = targetFile;
        int counter = 1;
        while (await finalTargetFile.exists()) {
          final nameWithoutExt = path.basenameWithoutExtension(fileName);
          final ext = path.extension(fileName);
          final newFileName = '${nameWithoutExt}_$counter$ext';
          finalTargetPath = path.join(downloadsPath, newFileName);
          finalTargetFile = File(finalTargetPath);
          counter++;
        }
        
        await sourceFile.copy(finalTargetPath);
        print('PDFStorageService: Also saved to external storage: $finalTargetPath');
      }
    } catch (e) {
      // Silently fail - external storage is optional
      print('PDFStorageService: Error saving to external storage: $e');
    }
  }
}

