import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/pdf_file.dart';
import 'pdf_preferences_service.dart';
import 'pdf_storage_service.dart';

class PDFService {
  static const MethodChannel _pdfScanChannel = MethodChannel('com.example.pdf_editor_app/pdf_scan');
  
  static Future<bool> hasStorageAccess() async {
    if (Platform.isAndroid) {
      try {
        final result = await _pdfScanChannel.invokeMethod<bool>('hasStorageAccess');
        return result ?? false;
      } catch (e) {
        print('PDFService: Error checking storage access: $e');
        return false;
      }
    }
    return false;
  }
  
  static Future<bool> requestStorageAccess() async {
    if (Platform.isAndroid) {
      try {
        final result = await _pdfScanChannel.invokeMethod<bool>('requestStorageAccess');
        return result ?? false;
      } catch (e) {
        print('PDFService: Error requesting storage access: $e');
        return false;
      }
    }
    return false;
  }

  static Future<List<PDFFile>> loadPDFsFromDevice() async {
    List<PDFFile> pdfFiles = [];
    Set<String> seenPaths = {}; // To avoid duplicates

    try {
      // Load bookmarks and recent access from preferences
      final bookmarks = await PDFPreferencesService.getBookmarks();
      final recentAccess = await PDFPreferencesService.getRecentAccess();

      // First, scan all PDFs from device using platform channel (Android)
      if (Platform.isAndroid) {
        try {
          // For Android 13+, READ_EXTERNAL_STORAGE is not effective
          // We rely on MediaStore API which doesn't require special permissions
          // For older Android versions, request storage permission
          final deviceInfo = DeviceInfoPlugin();
          final androidInfo = await deviceInfo.androidInfo;
          final sdkInt = androidInfo.version.sdkInt;
          
          if (sdkInt < 33) { // Android 12 and below
            if (await Permission.storage.isDenied) {
              print('PDFService: Requesting storage permission for Android < 13...');
              final status = await Permission.storage.request();
              if (status.isDenied) {
                print('PDFService: Storage permission denied, scanning may be limited');
              }
            }
          } else {
            print('PDFService: Android 13+ detected - using MediaStore API (no special permissions needed)');
          }
          
          print('PDFService: Starting device scan...');
          final dynamic result = await _pdfScanChannel.invokeMethod('scanPDFs');
          print('PDFService: Scan result type: ${result.runtimeType}');
          
          if (result == null) {
            print('PDFService: Scan returned null - method channel may have failed');
          } else if (result is List) {
            print('PDFService: Found ${result.length} PDFs from device scan');
            final List<dynamic> scannedPDFs = result;
            for (var pdfData in scannedPDFs) {
              if (pdfData is Map) {
                final filePath = pdfData['path'] as String?;
                final fileName = pdfData['name'] as String? ?? 'Unknown';
                final fileSize = pdfData['size'] as int? ?? 0;
                final dateModified = pdfData['dateModified'] as int? ?? 0;
                final isContentUri = pdfData['isContentUri'] as bool? ?? false;

                if (filePath != null && !seenPaths.contains(filePath)) {
                  seenPaths.add(filePath);
                  
                  // Handle both file paths and content URIs
                  bool fileExists = false;
                  int actualFileSize = fileSize;
                  DateTime actualModifiedDate = dateModified > 0
                      ? DateTime.fromMillisecondsSinceEpoch(dateModified)
                      : DateTime.now();
                  
                  if (isContentUri) {
                    // For content URIs, we can't check file.exists() directly
                    // Accept it if we have valid metadata - content URIs are valid
                    fileExists = fileName.isNotEmpty && fileName != 'Unknown';
                    // Use provided metadata for content URIs
                    if (fileSize > 0) {
                      actualFileSize = fileSize;
                    }
                    if (dateModified > 0) {
                      actualModifiedDate = DateTime.fromMillisecondsSinceEpoch(dateModified);
                    }
                  } else {
                    // For file paths, verify file exists
                    try {
                      final file = File(filePath);
                      if (await file.exists()) {
                        fileExists = true;
                        try {
                          final stat = await file.stat();
                          actualFileSize = fileSize > 0 ? fileSize : stat.size;
                          actualModifiedDate = dateModified > 0
                              ? DateTime.fromMillisecondsSinceEpoch(dateModified)
                              : stat.modified;
                        } catch (e) {
                          // Can't read stat, but file exists - use provided metadata
                          print('PDFService: Could not read file stat for $filePath: $e');
                        }
                      }
                    } catch (e) {
                      // File might not be accessible, skip it
                      print('PDFService: Error accessing file $filePath: $e');
                      continue;
                    }
                  }
                  
                  if (fileExists) {
                    final displayName = fileName.length > 25
                        ? '${fileName.substring(0, 22)}...'
                        : fileName;
                    final formattedSize = formatFileSize(actualFileSize);

                    // Get bookmark status and last accessed time
                    final isBookmarked = bookmarks.contains(filePath);
                    final lastAccessedStr = recentAccess[filePath];
                    DateTime? lastAccessed;
                    if (lastAccessedStr != null) {
                      try {
                        lastAccessed = DateTime.parse(lastAccessedStr);
                      } catch (e) {
                        lastAccessed = null;
                      }
                    }

                    pdfFiles.add(
                      PDFFile(
                        name: displayName,
                        date: formatDate(actualModifiedDate),
                        size: formattedSize,
                        isFavorite: isBookmarked,
                        filePath: filePath,
                        lastAccessed: lastAccessed,
                      ),
                    );
                  }
                }
              }
            }
          } else {
            print('PDFService: Unexpected result type: ${result.runtimeType}');
          }
        } catch (e, stackTrace) {
          print('PDFService: Error scanning PDFs from device: $e');
          print('PDFService: Stack trace: $stackTrace');
          // Continue with app directory scanning
        }
      } else {
        print('PDFService: Not Android platform, skipping device scan');
      }

      // Also scan app's PDF directory (for files copied/moved to app)
      try {
        final directory = await getApplicationDocumentsDirectory();
        final pdfDirectory = Directory('${directory.path}/PDFs');

        // Create directory if it doesn't exist
        if (!await pdfDirectory.exists()) {
          await pdfDirectory.create(recursive: true);
        }

        // Scan for PDF files in app directory
        final files = pdfDirectory.listSync();
        for (var file in files) {
          if (file is File && file.path.toLowerCase().endsWith('.pdf')) {
            if (!seenPaths.contains(file.path)) {
              seenPaths.add(file.path);
              
              final stat = await file.stat();
              final fileName = path.basename(file.path);
              final fileSize = formatFileSize(stat.size);
              final modifiedDate = stat.modified;

              // Get bookmark status and last accessed time
              final isBookmarked = bookmarks.contains(file.path);
              final lastAccessedStr = recentAccess[file.path];
              DateTime? lastAccessed;
              if (lastAccessedStr != null) {
                try {
                  lastAccessed = DateTime.parse(lastAccessedStr);
                } catch (e) {
                  lastAccessed = null;
                }
              }

              pdfFiles.add(
                PDFFile(
                  name: fileName.length > 25
                      ? '${fileName.substring(0, 22)}...'
                      : fileName,
                  date: formatDate(modifiedDate),
                  size: fileSize,
                  isFavorite: isBookmarked,
                  filePath: file.path,
                  lastAccessed: lastAccessed,
                ),
              );
            }
          }
        }
      } catch (e) {
        print('Error loading PDFs from app directory: $e');
      }

      // Sort by date (newest first)
      pdfFiles.sort((a, b) => b.date.compareTo(a.date));
      
      print('PDFService: Total PDFs loaded: ${pdfFiles.length}');
    } catch (e, stackTrace) {
      print('PDFService: Error loading PDFs: $e');
      print('PDFService: Stack trace: $stackTrace');
    }

    return pdfFiles;
  }

  static Future<String?> pickPDFFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        // Copy file to app storage using storage service
        final sourcePath = result.files.single.path!;
        final copiedPath = await PDFStorageService.copyToAppStorage(sourcePath);
        return copiedPath;
      }
    } catch (e) {
      print('Error picking PDF: $e');
    }

    return null;
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  static String formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }
}

