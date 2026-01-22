import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import '../models/pdf_file.dart';
import 'pdf_preferences_service.dart';

class PDFService {
  static const MethodChannel _pdfScanChannel = MethodChannel('com.example.pdf_editor_app/pdf_scan');

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
          final List<dynamic>? scannedPDFs = await _pdfScanChannel.invokeMethod<List<dynamic>>('scanPDFs');
          if (scannedPDFs != null) {
            for (var pdfData in scannedPDFs) {
              if (pdfData is Map) {
                final filePath = pdfData['path'] as String?;
                final fileName = pdfData['name'] as String? ?? 'Unknown';
                final fileSize = pdfData['size'] as int? ?? 0;
                final dateModified = pdfData['dateModified'] as int? ?? 0;

                if (filePath != null && !seenPaths.contains(filePath)) {
                  seenPaths.add(filePath);
                  
                  // Verify file exists
                  final file = File(filePath);
                  if (await file.exists()) {
                    final stat = await file.stat();
                    final displayName = fileName.length > 25
                        ? '${fileName.substring(0, 22)}...'
                        : fileName;
                    final formattedSize = formatFileSize(fileSize > 0 ? fileSize : stat.size);
                    final modifiedDate = dateModified > 0
                        ? DateTime.fromMillisecondsSinceEpoch(dateModified)
                        : stat.modified;

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
                        date: formatDate(modifiedDate),
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
          }
        } catch (e) {
          print('Error scanning PDFs from device: $e');
          // Fallback to directory scanning
        }
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
    } catch (e) {
      print('Error loading PDFs: $e');
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
        // Copy file to app's PDF directory
        final sourceFile = File(result.files.single.path!);
        final directory = await getApplicationDocumentsDirectory();
        final pdfDirectory = Directory('${directory.path}/PDFs');

        if (!await pdfDirectory.exists()) {
          await pdfDirectory.create(recursive: true);
        }

        final fileName = path.basename(sourceFile.path);
        final destFile = File('${pdfDirectory.path}/$fileName');

        // Copy file
        await sourceFile.copy(destFile.path);

        return destFile.path;
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

