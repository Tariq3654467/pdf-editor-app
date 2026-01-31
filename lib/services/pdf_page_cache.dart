import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Cache for rendered PDF pages to prevent re-rendering
/// Critical for Samsung S23 Ultra performance - avoids ANR from repeated rendering
class PDFPageCache {
  static final PDFPageCache _instance = PDFPageCache._internal();
  factory PDFPageCache() => _instance;
  PDFPageCache._internal();

  // In-memory cache: filePath -> pageIndex -> image bytes
  final Map<String, Map<int, Uint8List>> _memoryCache = {};
  
  // Maximum cache size (in pages)
  static const int _maxCacheSize = 50;
  
  // Cache directory for disk cache
  Directory? _cacheDir;

  /// Initialize cache directory
  Future<void> initialize() async {
    if (_cacheDir != null) return;
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory(path.join(appDir.path, 'pdf_page_cache'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Error initializing PDF page cache: $e');
    }
  }

  /// Get cached page image
  Future<Uint8List?> getCachedPage(String filePath, int pageIndex) async {
    // Check memory cache first
    if (_memoryCache.containsKey(filePath)) {
      final pageCache = _memoryCache[filePath];
      if (pageCache != null && pageCache.containsKey(pageIndex)) {
        return pageCache[pageIndex];
      }
    }

    // Check disk cache
    if (_cacheDir != null) {
      try {
        final cacheKey = _getCacheKey(filePath, pageIndex);
        final cacheFile = File(path.join(_cacheDir!.path, cacheKey));
        
        if (await cacheFile.exists()) {
          final bytes = await cacheFile.readAsBytes();
          
          // Store in memory cache
          _memoryCache.putIfAbsent(filePath, () => {})[pageIndex] = bytes;
          
          return bytes;
        }
      } catch (e) {
        debugPrint('Error reading from disk cache: $e');
      }
    }

    return null;
  }

  /// Cache page image
  Future<void> cachePage(
    String filePath,
    int pageIndex,
    Uint8List imageBytes,
  ) async {
    // Store in memory cache
    _memoryCache.putIfAbsent(filePath, () => {})[pageIndex] = imageBytes;
    
    // Limit memory cache size
    _limitMemoryCacheSize();

    // Store in disk cache
    if (_cacheDir != null) {
      try {
        final cacheKey = _getCacheKey(filePath, pageIndex);
        final cacheFile = File(path.join(_cacheDir!.path, cacheKey));
        await cacheFile.writeAsBytes(imageBytes);
      } catch (e) {
        debugPrint('Error writing to disk cache: $e');
      }
    }
  }

  /// Clear cache for a specific file
  void clearFileCache(String filePath) {
    _memoryCache.remove(filePath);
    
    if (_cacheDir != null) {
      // Clear disk cache for this file
      _cacheDir!.list().listen(
        (file) {
          if (file.path.contains(_getFileHash(filePath))) {
            file.delete().catchError((e) {
              debugPrint('Error deleting cache file: $e');
            });
          }
        },
        onError: (e) {
          debugPrint('Error clearing disk cache: $e');
        },
      );
    }
  }

  /// Clear all cache
  void clearAll() {
    _memoryCache.clear();
    
    if (_cacheDir != null) {
      _cacheDir!.list().listen(
        (file) {
          file.delete().catchError((e) {
            debugPrint('Error deleting cache file: $e');
          });
        },
        onError: (e) {
          debugPrint('Error clearing disk cache: $e');
        },
      );
    }
  }

  /// Limit memory cache size to prevent OOM
  void _limitMemoryCacheSize() {
    int totalPages = 0;
    for (var pageCache in _memoryCache.values) {
      totalPages += pageCache.length;
    }

    if (totalPages > _maxCacheSize) {
      // Remove oldest entries (simple FIFO)
      final entries = _memoryCache.entries.toList();
      final toRemove = totalPages - _maxCacheSize;
      int removed = 0;

      for (var entry in entries) {
        if (removed >= toRemove) break;
        
        final pageCache = entry.value;
        if (pageCache.isNotEmpty) {
          final firstKey = pageCache.keys.first;
          pageCache.remove(firstKey);
          removed++;
        }

        if (pageCache.isEmpty) {
          _memoryCache.remove(entry.key);
        }
      }
    }
  }

  /// Generate cache key from file path and page index
  String _getCacheKey(String filePath, int pageIndex) {
    final fileHash = _getFileHash(filePath);
    return '${fileHash}_page_$pageIndex.png';
  }

  /// Generate hash from file path
  String _getFileHash(String filePath) {
    // Simple hash - in production, use proper hashing
    return filePath.hashCode.toString();
  }
}

