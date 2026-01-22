import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/pdf_file.dart';
import 'pdf_service.dart';
import 'pdf_preferences_service.dart';
import 'pdf_cache_service.dart';

/// Enhanced PDF Scanner Service with folder grouping and caching
class PDFScannerService {
  static const MethodChannel _pdfScanChannel = MethodChannel('com.example.pdf_editor_app/pdf_scan');
  static bool _isScanning = false;
  
  /// Load PDFs from cache or scan if cache doesn't exist
  /// Returns cached PDFs immediately, then scans in background if needed
  static Future<List<PDFFile>> loadPDFs({bool forceRescan = false}) async {
    // Check cache first (unless forcing rescan)
    if (!forceRescan) {
      final cachedPDFs = await PDFCacheService.loadPDFList();
      if (cachedPDFs.isNotEmpty) {
        print('PDFScannerService: Loaded ${cachedPDFs.length} PDFs from cache');
        // Trigger background refresh if cache is old (> 1 day)
        final cacheTimestamp = await PDFCacheService.getCacheTimestamp();
        if (cacheTimestamp != null) {
          final age = DateTime.now().difference(cacheTimestamp);
          if (age.inDays > 1) {
            print('PDFScannerService: Cache is ${age.inDays} days old, refreshing in background...');
            scanAllPDFsInBackground(); // Don't await - run in background
          }
        }
        return cachedPDFs;
      }
    }
    
    // No cache or force rescan - scan now
    print('PDFScannerService: No cache found or force rescan requested, scanning...');
    return await scanAllPDFs();
  }
  
  /// Scan all PDFs automatically from device (with caching)
  static Future<List<PDFFile>> scanAllPDFs({bool saveToCache = true}) async {
    try {
      // Load preferences first
      final bookmarks = await PDFPreferencesService.getBookmarks();
      final recentAccess = await PDFPreferencesService.getRecentAccess();
      
      if (Platform.isAndroid) {
        try {
          // Call native method to scan PDFs (native code handles async operations)
          print('PDFScannerService: Starting automatic PDF scan...');
          final dynamic result = await _pdfScanChannel.invokeMethod('scanPDFs');
        
          if (result == null || result is! List) {
            print('PDFScannerService: Invalid scan result');
            return await _scanAppDirectory(bookmarks, recentAccess);
          }
          
          final List<PDFFile> pdfFiles = [];
          final seenPaths = <String>{};
          
          for (var pdfData in result) {
            if (pdfData is! Map) continue;
            
            final filePath = pdfData['path'] as String?;
            final fileName = pdfData['name'] as String? ?? 'Unknown';
            final fileSize = pdfData['size'] as int? ?? 0;
            final dateModified = pdfData['dateModified'] as int? ?? 0;
            final isContentUri = pdfData['isContentUri'] as bool? ?? false;
            final folderPath = pdfData['folderPath'] as String?;
            final folderName = pdfData['folderName'] as String?;
            
            if (filePath == null || seenPaths.contains(filePath)) continue;
            seenPaths.add(filePath);
            
            // Use folder info from native if available, otherwise extract
            String? finalFolderPath = folderPath;
            String? finalFolderName = folderName;
            
            if (finalFolderPath == null || finalFolderName == null) {
              if (isContentUri) {
                // For content URIs, try to extract folder from path
                final uriPath = filePath;
                if (uriPath.contains('/')) {
                  final parts = uriPath.split('/');
                  if (parts.length > 1) {
                    finalFolderName = parts[parts.length - 2];
                    finalFolderPath = parts.sublist(0, parts.length - 1).join('/');
                  }
                }
              } else {
                // For file paths, extract directory
                try {
                  final file = File(filePath);
                  final dir = file.parent;
                  finalFolderPath = dir.path;
                  finalFolderName = dir.path.split(Platform.pathSeparator).last;
                } catch (e) {
                  // If we can't parse, use default
                  finalFolderPath = null;
                  finalFolderName = 'Unknown';
                }
              }
            }
            
            // Make folder name more readable
            if (finalFolderName != null) {
              final lowerName = finalFolderName.toLowerCase();
              if (finalFolderName.isEmpty || finalFolderName == '/') {
                finalFolderName = 'Root';
              } else if (lowerName.contains('emulated')) {
                finalFolderName = 'Internal Storage';
              } else if (lowerName.contains('download')) {
                finalFolderName = 'Downloads';
              } else if (lowerName.contains('document')) {
                finalFolderName = 'Documents';
              }
            }
            
            // Verify file exists (for file paths)
            bool fileExists = false;
            int actualFileSize = fileSize;
            DateTime actualModifiedDate = dateModified > 0
                ? DateTime.fromMillisecondsSinceEpoch(dateModified)
                : DateTime.now();
            
            if (isContentUri) {
              // For content URIs, trust the metadata
              fileExists = fileName.isNotEmpty && fileSize > 0;
            } else {
              try {
                final file = File(filePath);
                if (await file.exists()) {
                  fileExists = true;
                  final stat = await file.stat();
                  actualFileSize = fileSize > 0 ? fileSize : stat.size;
                  actualModifiedDate = dateModified > 0
                      ? DateTime.fromMillisecondsSinceEpoch(dateModified)
                      : stat.modified;
                }
              } catch (e) {
                continue; // Skip if file doesn't exist
              }
            }
            
            if (!fileExists) continue;
            
            // Format display name
            final displayName = fileName.length > 25
                ? '${fileName.substring(0, 22)}...'
                : fileName;
            
            // Get bookmark and last accessed
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
                date: PDFService.formatDate(actualModifiedDate),
                size: PDFService.formatFileSize(actualFileSize),
                isFavorite: isBookmarked,
                filePath: filePath,
                lastAccessed: lastAccessed,
                folderPath: finalFolderPath,
                folderName: finalFolderName ?? 'Unknown',
                dateModified: actualModifiedDate,
                fileSizeBytes: actualFileSize,
              ),
            );
          }
          
          // Sort by date (newest first)
          pdfFiles.sort((a, b) {
            final aDate = a.dateModified ?? DateTime(1970);
            final bDate = b.dateModified ?? DateTime(1970);
            return bDate.compareTo(aDate);
          });
          
          print('PDFScannerService: Scanned ${pdfFiles.length} PDFs');
          
          // Save to cache
          if (saveToCache) {
            await PDFCacheService.savePDFList(pdfFiles);
          }
          
          return pdfFiles;
        } catch (e) {
          print('PDFScannerService: Error scanning PDFs: $e');
          // Fallback to app directory scan if native scan fails
          return await _scanAppDirectory(bookmarks, recentAccess);
        }
      } else if (Platform.isIOS) {
        // iOS: Scan app directory only (graceful fallback)
        // iOS doesn't allow device-wide scanning, so we only show imported PDFs
        return await _scanAppDirectory(bookmarks, recentAccess);
      } else {
        // Other platforms: scan app directory
        return await _scanAppDirectory(bookmarks, recentAccess);
      }
    } catch (e) {
      print('PDFScannerService: Error scanning PDFs: $e');
      return [];
    }
  }
  
  /// Scan app directory (for non-Android platforms or fallback)
  static Future<List<PDFFile>> _scanAppDirectory(
    Set<String> bookmarks,
    Map<String, String> recentAccess,
  ) async {
    final List<PDFFile> pdfFiles = [];
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final pdfDirectory = Directory('${directory.path}/PDFs');
      
      if (await pdfDirectory.exists()) {
        final files = pdfDirectory.listSync();
        
        for (var file in files) {
          if (file is File && file.path.toLowerCase().endsWith('.pdf')) {
            final stat = await file.stat();
            final fileName = path.basename(file.path);
            
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
                date: PDFService.formatDate(stat.modified),
                size: PDFService.formatFileSize(stat.size),
                isFavorite: isBookmarked,
                filePath: file.path,
                lastAccessed: lastAccessed,
                folderPath: pdfDirectory.path,
                folderName: 'App Files',
                dateModified: stat.modified,
                fileSizeBytes: stat.size,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('PDFScannerService: Error scanning app directory: $e');
    }
    
    return pdfFiles;
  }
  
  /// Group PDFs by folder
  static List<PDFFolder> groupPDFsByFolder(List<PDFFile> pdfs) {
    final Map<String, PDFFolder> folderMap = {};
    
    for (var pdf in pdfs) {
      final folderPath = pdf.folderPath ?? 'Unknown';
      final folderName = pdf.folderName ?? 'Unknown';
      
      if (!folderMap.containsKey(folderPath)) {
        folderMap[folderPath] = PDFFolder(
          folderPath: folderPath,
          folderName: folderName,
          pdfs: [],
        );
      }
      
      final folder = folderMap[folderPath]!;
      folder.pdfs.add(pdf);
      folder.totalSize += pdf.fileSizeBytes ?? 0;
      
      // Update last modified
      if (pdf.dateModified != null) {
        if (folder.lastModified == null ||
            pdf.dateModified!.isAfter(folder.lastModified!)) {
          folder.lastModified = pdf.dateModified;
        }
      }
    }
    
    // Sort folders by last modified (newest first)
    final folders = folderMap.values.toList();
    folders.sort((a, b) {
      if (a.lastModified == null && b.lastModified == null) return 0;
      if (a.lastModified == null) return 1;
      if (b.lastModified == null) return -1;
      return b.lastModified!.compareTo(a.lastModified!);
    });
    
    // Sort PDFs within each folder by date
    for (var folder in folders) {
      folder.pdfs.sort((a, b) {
        final aDate = a.dateModified ?? DateTime(1970);
        final bDate = b.dateModified ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });
    }
    
    return folders;
  }
  
  /// Request storage permission (Android)
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = deviceInfo.version.sdkInt;
      
      // Android 11+ (API 30+) - Try MANAGE_EXTERNAL_STORAGE for root-level access
      if (sdkInt >= 30) {
        // First try MANAGE_EXTERNAL_STORAGE for full root access
        if (await Permission.manageExternalStorage.isGranted) {
          print('PDFScannerService: MANAGE_EXTERNAL_STORAGE already granted');
          return true;
        }
        
        // Request MANAGE_EXTERNAL_STORAGE (requires user to go to Settings)
        final manageStorageStatus = await Permission.manageExternalStorage.status;
        if (manageStorageStatus.isDenied || manageStorageStatus.isPermanentlyDenied) {
          print('PDFScannerService: Requesting MANAGE_EXTERNAL_STORAGE...');
          final result = await Permission.manageExternalStorage.request();
          if (result.isGranted) {
            print('PDFScannerService: MANAGE_EXTERNAL_STORAGE granted - full root access enabled');
            return true;
          } else if (result.isPermanentlyDenied) {
            // Open Settings for user to manually enable
            print('PDFScannerService: Opening Settings for MANAGE_EXTERNAL_STORAGE...');
            await openAppSettings();
            return false; // Will be granted after user enables in Settings
          } else {
            print('PDFScannerService: MANAGE_EXTERNAL_STORAGE denied, falling back to SAF');
          }
        }
        
        // Fallback to SAF access for Android 13+
        if (sdkInt >= 33) {
          final hasSAF = await PDFService.hasStorageAccess();
          if (!hasSAF) {
            return await PDFService.requestStorageAccess();
          }
          return true;
        }
      } else {
        // Android 12 and below
        if (await Permission.storage.isGranted) {
          return true;
        }
        final result = await Permission.storage.request();
        return result.isGranted;
      }
    } catch (e) {
      print('PDFScannerService: Error requesting permission: $e');
      return false;
    }
    
    return false;
  }
  
  /// Process scan results in background isolate (for heavy processing)
  static Future<List<PDFFile>> _processScanResultsInIsolate(
    List<dynamic> rawResults,
    Set<String> bookmarks,
    Map<String, String> recentAccess,
  ) async {
    return await compute(_processPDFData, {
      'results': rawResults,
      'bookmarks': bookmarks.toList(),
      'recentAccess': recentAccess,
    });
  }
  
  /// Static function for isolate processing
  static List<PDFFile> _processPDFData(Map<String, dynamic> data) {
    final rawResults = data['results'] as List<dynamic>;
    final bookmarks = (data['bookmarks'] as List<dynamic>).cast<String>().toSet();
    final recentAccess = (data['recentAccess'] as Map<String, dynamic>).cast<String, String>();
    
    final List<PDFFile> pdfFiles = [];
    final seenPaths = <String>{};
    
    for (var pdfData in rawResults) {
      if (pdfData is! Map) continue;
      
      final filePath = pdfData['path'] as String?;
      final fileName = pdfData['name'] as String? ?? 'Unknown';
      final fileSize = pdfData['size'] as int? ?? 0;
      final dateModified = pdfData['dateModified'] as int? ?? 0;
      final isContentUri = pdfData['isContentUri'] as bool? ?? false;
      final folderPath = pdfData['folderPath'] as String?;
      final folderName = pdfData['folderName'] as String?;
      
      if (filePath == null || seenPaths.contains(filePath)) continue;
      seenPaths.add(filePath);
      
      // Use folder info from native if available
      String? finalFolderPath = folderPath;
      String? finalFolderName = folderName;
      
      if (finalFolderPath == null || finalFolderName == null) {
        if (isContentUri) {
          final uriPath = filePath;
          if (uriPath.contains('/')) {
            final parts = uriPath.split('/');
            if (parts.length > 1) {
              finalFolderName = parts[parts.length - 2];
              finalFolderPath = parts.sublist(0, parts.length - 1).join('/');
            }
          }
        } else {
          try {
            final file = File(filePath);
            final dir = file.parent;
            finalFolderPath = dir.path;
            finalFolderName = dir.path.split(Platform.pathSeparator).last;
          } catch (e) {
            finalFolderPath = null;
            finalFolderName = 'Unknown';
          }
        }
      }
      
      // Make folder name more readable
      if (finalFolderName != null) {
        final lowerName = finalFolderName.toLowerCase();
        if (finalFolderName.isEmpty || finalFolderName == '/') {
          finalFolderName = 'Root';
        } else if (lowerName.contains('emulated')) {
          finalFolderName = 'Internal Storage';
        } else if (lowerName.contains('download')) {
          finalFolderName = 'Downloads';
        } else if (lowerName.contains('document')) {
          finalFolderName = 'Documents';
        }
      }
      
      // For content URIs, trust metadata; for file paths, verify exists
      bool fileExists = false;
      int actualFileSize = fileSize;
      DateTime actualModifiedDate = dateModified > 0
          ? DateTime.fromMillisecondsSinceEpoch(dateModified)
          : DateTime.now();
      
      if (isContentUri) {
        fileExists = fileName.isNotEmpty && fileSize > 0;
      } else {
        try {
          final file = File(filePath);
          if (file.existsSync()) {
            fileExists = true;
            final stat = file.statSync();
            actualFileSize = fileSize > 0 ? fileSize : stat.size;
            actualModifiedDate = dateModified > 0
                ? DateTime.fromMillisecondsSinceEpoch(dateModified)
                : stat.modified;
          }
        } catch (e) {
          continue; // Skip if file doesn't exist
        }
      }
      
      if (!fileExists) continue;
      
      // Format display name
      final displayName = fileName.length > 25
          ? '${fileName.substring(0, 22)}...'
          : fileName;
      
      // Get bookmark and last accessed
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
          date: PDFService.formatDate(actualModifiedDate),
          size: PDFService.formatFileSize(actualFileSize),
          isFavorite: isBookmarked,
          filePath: filePath,
          lastAccessed: lastAccessed,
          folderPath: finalFolderPath,
          folderName: finalFolderName ?? 'Unknown',
          dateModified: actualModifiedDate,
          fileSizeBytes: actualFileSize,
        ),
      );
    }
    
    // Sort by date (newest first)
    pdfFiles.sort((a, b) {
      final aDate = a.dateModified ?? DateTime(1970);
      final bDate = b.dateModified ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    
    return pdfFiles;
  }
  
  /// Scan PDFs in background (non-blocking)
  static Future<void> scanAllPDFsInBackground() async {
    if (_isScanning) {
      print('PDFScannerService: Scan already in progress, skipping...');
      return;
    }
    
    _isScanning = true;
    try {
      // Run scan in background
      await scanAllPDFs();
      print('PDFScannerService: Background scan completed');
    } catch (e) {
      print('PDFScannerService: Background scan error: $e');
    } finally {
      _isScanning = false;
    }
  }
  
  /// Clear cache and rescan
  static Future<List<PDFFile>> clearCacheAndRescan() async {
    await PDFCacheService.clearCache();
    return await scanAllPDFs();
  }
}

