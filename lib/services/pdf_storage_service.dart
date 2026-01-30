import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/pdf_file.dart';
import 'pdf_service.dart';
import 'pdf_preferences_service.dart';
import 'pdf_cache_service.dart';

/// Service for managing all PDFs in app-specific storage
/// This ensures all files are managed internally, no external file manager dependency
class PDFStorageService {
  /// Get app's PDF directory (where all PDFs are stored)
  static Future<Directory> getAppPDFDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory('${directory.path}/PDFs');
    
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }
    
    return pdfDirectory;
  }
  
  /// Copy external PDF to app storage
  /// Returns the new path in app storage
  static Future<String?> copyToAppStorage(String sourcePath) async {
    try {
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
      
      // Add to cache
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
      
      // Add to cache - CRITICAL: This must complete before returning
      await PDFCacheService.addPDFToCache(pdfFile);
      print('PDFStorageService: Added PDF to cache: ${pdfFile.name}');
      
      // Mark as recently accessed
      await PDFPreferencesService.setLastAccessed(targetPath);
      print('PDFStorageService: Marked as recently accessed: $targetPath');
      
      // Also save to external storage (Downloads) so it's visible in file manager
      // This is optional - files are already in app storage
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await _saveToExternalStorage(targetPath, fileName);
        } catch (e) {
          print('PDFStorageService: Could not save to external storage: $e');
          // Continue - file is already saved in app storage
        }
      }
      
      print('PDFStorageService: Saved PDF to app storage: $targetPath');
      print('PDFStorageService: File exists: ${await targetFile.exists()}');
      print('PDFStorageService: File size: ${await targetFile.length()} bytes');
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
      // Check if already in app storage
      if (await isInAppStorage(filePath)) {
        return filePath;
      }
      
      // Copy to app storage
      final newPath = await copyToAppStorage(filePath);
      if (newPath != null) {
        return newPath;
      }
      
      // If copy failed, return original path (fallback)
      return filePath;
    } catch (e) {
      print('PDFStorageService: Error ensuring in app storage: $e');
      return filePath;
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

