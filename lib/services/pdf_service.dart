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
  
  /// Check if we have SAF access (stored SAF URIs)
  static Future<bool> hasSAFAccess() async {
    if (Platform.isAndroid) {
      try {
        final result = await _pdfScanChannel.invokeMethod<bool>('hasSAFAccess');
        return result ?? false;
      } catch (e) {
        print('PDFService: Error checking SAF access: $e');
        return false;
      }
    }
    return false;
  }
  
  /// Request SAF access - user selects PDF or folder
  static Future<bool> requestSAFAccess() async {
    if (Platform.isAndroid) {
      try {
        final result = await _pdfScanChannel.invokeMethod<bool>('requestSAFAccess');
        return result ?? false;
      } catch (e) {
        print('PDFService: Error requesting SAF access: $e');
        return false;
      }
    }
    return false;
  }
  
  /// Get count of stored SAF URIs
  static Future<int> getStoredSAFUriCount() async {
    if (Platform.isAndroid) {
      try {
        final result = await _pdfScanChannel.invokeMethod<int>('getStoredSAFUriCount');
        return result ?? 0;
      } catch (e) {
        print('PDFService: Error getting SAF URI count: $e');
        return 0;
      }
    }
    return 0;
  }
  
  /// Add a SAF URI to the index (from user selection)
  static Future<bool> addSAFUri(String uriString) async {
    if (Platform.isAndroid) {
      try {
        final result = await _pdfScanChannel.invokeMethod<bool>('addSAFUri', uriString);
        return result ?? false;
      } catch (e) {
        print('PDFService: Error adding SAF URI: $e');
        return false;
      }
    }
    return false;
  }
  
  // Legacy methods - kept for compatibility
  static Future<bool> hasStorageAccess() async {
    return hasSAFAccess();
  }
  
  static Future<bool> requestStorageAccess() async {
    return requestSAFAccess();
  }
  
  /// Request root-level storage access (MANAGE_EXTERNAL_STORAGE)
  /// This opens Android Settings for the user to grant permission
  static Future<bool> requestRootStorageAccess() async {
    if (Platform.isAndroid) {
      try {
        final result = await _pdfScanChannel.invokeMethod<bool>('requestRootStorageAccess');
        return result ?? false;
      } catch (e) {
        print('PDFService: Error requesting root storage access: $e');
        return false;
      }
    }
    return false;
  }
  
  /// Check if we have root-level storage access (MANAGE_EXTERNAL_STORAGE)
  static Future<bool> hasRootStorageAccess() async {
    if (Platform.isAndroid) {
      try {
        final result = await _pdfScanChannel.invokeMethod<bool>('hasRootStorageAccess');
        return result ?? false;
      } catch (e) {
        print('PDFService: Error checking root storage access: $e');
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
          // MediaStore API works on ALL Android versions without any permissions
          // No permission requests needed - this is permission-less access
          print('PDFService: Starting device scan (permission-less MediaStore)...');
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

    // Format: MM/DD/YYYY HH:MM to match image design
    return '$month/$day/$year $hour:$minute';
  }
}

