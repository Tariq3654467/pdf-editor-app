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

// Import dart:io (guarded with kIsWeb checks for web compatibility)
import 'dart:io' as io;

/// Enhanced PDF Scanner Service with folder grouping and caching
class PDFScannerService {
  static const MethodChannel _pdfScanChannel = MethodChannel('com.example.pdf_editor_app/pdf_scan');
  static bool _isScanning = false;
  
  /// Load PDFs from cache or scan if cache doesn't exist
  /// Returns cached PDFs immediately, then scans in background if needed
  static Future<List<PDFFile>> loadPDFs({bool forceRescan = false}) async {
    // Always check cache first and return immediately
    final cachedPDFs = await PDFCacheService.loadPDFList();
    
    // If we have cache and not forcing rescan, return immediately and refresh in background
    if (cachedPDFs.isNotEmpty && !forceRescan) {
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
    
    // No cache or force rescan - return empty list immediately, scan in background
    print('PDFScannerService: No cache found or force rescan requested, scanning in background...');
    scanAllPDFsInBackground(); // Don't await - run in background
    return cachedPDFs; // Return cached (empty if no cache) immediately
  }
  
  /// Scan all PDFs automatically from device (with caching)
  static Future<List<PDFFile>> scanAllPDFs({bool saveToCache = true}) async {
    try {
      // Load preferences first
      final bookmarks = await PDFPreferencesService.getBookmarks();
      final recentAccess = await PDFPreferencesService.getRecentAccess();
      
      if (!kIsWeb && io.Platform.isAndroid) {
        try {
          // PHASE 4: Call native method to scan PDFs with increased timeout for 400+ PDFs
          print('PDFScannerService: Starting automatic PDF scan...');
          final dynamic result = await _pdfScanChannel.invokeMethod('scanPDFs')
              .timeout(
                const Duration(minutes: 5), // PHASE 4: Increased timeout for large storage
                onTimeout: () {
                  print('PDFScannerService: Scan timeout after 5 minutes');
                  print('PDFScannerService: This may indicate very large storage (>400 PDFs)');
                  return <Map<String, dynamic>>[]; // Return empty on timeout
                },
              )
              .catchError((error) {
                print('PDFScannerService: Method channel error: $error');
                // Return empty list on error to prevent crash
                return <Map<String, dynamic>>[];
              });
        
          if (result == null || result is! List) {
            print('PDFScannerService: Invalid scan result, falling back to app directory scan');
            return await _scanAppDirectory(bookmarks, recentAccess, saveToCache: saveToCache);
          }
          
          // CRITICAL: If MediaStore returns empty, don't clear cache - keep existing cache
          // Only scan app directory for app-managed PDFs, but preserve MediaStore cache
          if (result.isEmpty) {
            print('PDFScannerService: MediaStore scan returned empty - preserving existing cache');
            print('PDFScannerService: Scanning app directory for app-managed PDFs only');
            final appPDFs = await _scanAppDirectory(bookmarks, recentAccess, saveToCache: false);
            
            // Merge with existing cache instead of replacing
            final cachedPDFs = await PDFCacheService.loadPDFList();
            final mergedPDFs = <PDFFile>[];
            final seenPaths = <String>{};
            
            // Add cached PDFs first
            for (var pdf in cachedPDFs) {
              if (pdf.filePath != null && !seenPaths.contains(pdf.filePath!)) {
                seenPaths.add(pdf.filePath!);
                mergedPDFs.add(pdf);
              }
            }
            
            // Add app PDFs (new ones only)
            for (var pdf in appPDFs) {
              if (pdf.filePath != null && !seenPaths.contains(pdf.filePath!)) {
                seenPaths.add(pdf.filePath!);
                mergedPDFs.add(pdf);
              }
            }
            
            // Sort by date
            mergedPDFs.sort((a, b) {
              final aDate = a.dateModified ?? DateTime(1970);
              final bDate = b.dateModified ?? DateTime(1970);
              return bDate.compareTo(aDate);
            });
            
            // Only update cache if we have PDFs to save
            if (saveToCache && mergedPDFs.isNotEmpty) {
              await PDFCacheService.savePDFList(mergedPDFs);
            }
            
            return mergedPDFs;
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
              } else if (!kIsWeb) {
                // For file paths, extract directory (not on web)
                try {
                  final file = io.File(filePath);
                  final dir = file.parent;
                  finalFolderPath = dir.path;
                  // Use '/' or '\' based on path content (works on all platforms)
                  final pathParts = dir.path.split(RegExp(r'[/\\]'));
                  finalFolderName = pathParts.isNotEmpty ? pathParts.last : 'Unknown';
                } catch (e) {
                  // If we can't parse, use default
                  finalFolderPath = null;
                  finalFolderName = 'Unknown';
                }
              } else {
                // On web, extract from path string
                final pathParts = filePath.split(RegExp(r'[/\\]'));
                if (pathParts.length > 1) {
                  finalFolderName = pathParts[pathParts.length - 2];
                  finalFolderPath = pathParts.sublist(0, pathParts.length - 1).join('/');
                } else {
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
            
            // Verify file exists (for file paths) - use sync for speed
            bool fileExists = false;
            int actualFileSize = fileSize;
            DateTime actualModifiedDate = dateModified > 0
                ? DateTime.fromMillisecondsSinceEpoch(dateModified)
                : DateTime.now();
            
            if (isContentUri) {
              // For content URIs, trust the metadata
              fileExists = fileName.isNotEmpty && fileSize > 0;
            } else if (!kIsWeb) {
              try {
                final file = io.File(filePath);
                // Use sync exists check for speed (non-blocking in isolate context)
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
            } else {
              // On web, trust metadata
              fileExists = fileName.isNotEmpty && fileSize > 0;
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
          
          print('PDFScannerService: Scanned ${pdfFiles.length} PDFs from MediaStore');
          
          // CRITICAL: Only save to cache if we have PDFs
          // Never overwrite cache with empty list (preserves existing cache)
          if (saveToCache && pdfFiles.isNotEmpty) {
            await PDFCacheService.savePDFList(pdfFiles);
            print('PDFScannerService: Saved ${pdfFiles.length} PDFs to cache');
          } else if (pdfFiles.isEmpty) {
            print('PDFScannerService: MediaStore returned empty - preserving existing cache');
          }
          
          return pdfFiles;
        } catch (e) {
          print('PDFScannerService: Error scanning PDFs: $e');
          // Fallback to app directory scan if native scan fails
          return await _scanAppDirectory(bookmarks, recentAccess, saveToCache: saveToCache);
        }
      } else if (!kIsWeb && io.Platform.isIOS) {
        // iOS: Scan app directory only (graceful fallback)
        // iOS doesn't allow device-wide scanning, so we only show imported PDFs
        return await _scanAppDirectory(bookmarks, recentAccess, saveToCache: saveToCache);
      } else {
        // Other platforms: scan app directory
        return await _scanAppDirectory(bookmarks, recentAccess, saveToCache: saveToCache);
      }
    } catch (e) {
      print('PDFScannerService: Error scanning PDFs: $e');
      return [];
    }
  }
  
  /// Scan app directory (for non-Android platforms or fallback)
  /// This is used when root access is not available - scans only app's PDF directory
  static Future<List<PDFFile>> _scanAppDirectory(
    Set<String> bookmarks,
    Map<String, String> recentAccess, {
    bool saveToCache = true,
  }) async {
    final List<PDFFile> pdfFiles = [];
    
    // Web doesn't support file system access
    if (kIsWeb) {
      return pdfFiles;
    }
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final pdfDirectory = io.Directory('${directory.path}/PDFs');
      
      // Create directory if it doesn't exist
      if (!await pdfDirectory.exists()) {
        await pdfDirectory.create(recursive: true);
      }
      
      final files = pdfDirectory.listSync();
      
      for (var file in files) {
        if (file is io.File && file.path.toLowerCase().endsWith('.pdf')) {
          try {
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
          } catch (e) {
            print('PDFScannerService: Error processing file ${file.path}: $e');
            // Continue with other files
          }
        }
      }
      
      // Sort by date (newest first)
      pdfFiles.sort((a, b) {
        final aDate = a.dateModified ?? DateTime(1970);
        final bDate = b.dateModified ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });
      
      print('PDFScannerService: Scanned ${pdfFiles.length} PDFs from app directory');
      
      // Save to cache if requested
      if (saveToCache && pdfFiles.isNotEmpty) {
        await PDFCacheService.savePDFList(pdfFiles);
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
  /// NOTE: This app does NOT request storage permissions - uses MediaStore only
  /// This method is kept for compatibility but always returns true
  static Future<bool> requestStoragePermission() async {
    // No permissions needed - MediaStore works without permissions
    print('PDFScannerService: No permission request needed - using MediaStore (permission-less)');
    return true;
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
        } else if (!kIsWeb) {
          try {
            final file = io.File(filePath);
            final dir = file.parent;
            finalFolderPath = dir.path;
            // Use '/' or '\' based on path content (works in isolates)
            final pathParts = dir.path.split(RegExp(r'[/\\]'));
            finalFolderName = pathParts.isNotEmpty ? pathParts.last : 'Unknown';
          } catch (e) {
            finalFolderPath = null;
            finalFolderName = 'Unknown';
          }
        } else {
          // On web, extract from path string
          final pathParts = filePath.split(RegExp(r'[/\\]'));
          if (pathParts.length > 1) {
            finalFolderName = pathParts[pathParts.length - 2];
            finalFolderPath = pathParts.sublist(0, pathParts.length - 1).join('/');
          } else {
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
      } else if (!kIsWeb) {
        try {
          final file = io.File(filePath);
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
      } else {
        // On web, trust metadata
        fileExists = fileName.isNotEmpty && fileSize > 0;
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
  /// CRITICAL: Saves to cache incrementally for reactive UI updates
  /// Returns a Future that completes when scan is done (for UI updates)
  /// Comprehensive error handling to prevent crashes on Samsung devices
  static Future<List<PDFFile>> scanAllPDFsInBackground() async {
    if (_isScanning) {
      print('PDFScannerService: Scan already in progress, skipping...');
      return [];
    }
    
    _isScanning = true;
    try {
      // Add delay to ensure UI thread is free before starting heavy operation
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Scan all PDFs and save to cache (cache is updated incrementally)
      // The cache update happens in scanAllPDFs -> PDFCacheService.savePDFList
      // UI can refresh from cache periodically to get reactive updates
      final result = await scanAllPDFs(saveToCache: true)
          .timeout(
            const Duration(minutes: 5), // Increased timeout for 400+ PDFs
            onTimeout: () {
              print('PDFScannerService: Background scan timeout after 5 minutes');
              print('PDFScannerService: This may indicate very large storage (>400 PDFs)');
              // Return cached PDFs even on timeout
              return PDFCacheService.loadPDFList().catchError((e) {
                print('Error loading cache on timeout: $e');
                return <PDFFile>[];
              });
            },
          )
          .catchError((e, stackTrace) {
            print('PDFScannerService: Background scan error: $e');
            print('Stack trace: $stackTrace');
            // Return cached PDFs on error
            return PDFCacheService.loadPDFList().catchError((e) {
              print('Error loading cache on error: $e');
              return <PDFFile>[];
            });
          });
      
      print('PDFScannerService: Background scan completed with ${result.length} PDFs');
      return result;
    } catch (e, stackTrace) {
      print('PDFScannerService: Unexpected error in scanAllPDFsInBackground: $e');
      print('Stack trace: $stackTrace');
      // Return cached PDFs on unexpected error
      return PDFCacheService.loadPDFList().catchError((e) {
        print('Error loading cache on unexpected error: $e');
        return <PDFFile>[];
      });
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

