import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pdf_file.dart';

/// Service for caching PDF scan results to avoid rescanning on every app launch
class PDFCacheService {
  static const String _cacheKey = 'pdf_cache_list';
  static const String _cacheTimestampKey = 'pdf_cache_timestamp';
  static const String _cacheVersionKey = 'pdf_cache_version';
  static const int _currentCacheVersion = 1; // Increment when cache structure changes

  /// Save PDF list to cache
  static Future<void> savePDFList(List<PDFFile> pdfs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert PDFFile list to JSON
      final jsonList = pdfs.map((pdf) => {
        'name': pdf.name,
        'date': pdf.date,
        'size': pdf.size,
        'isFavorite': pdf.isFavorite,
        'filePath': pdf.filePath,
        'lastAccessed': pdf.lastAccessed?.toIso8601String(),
        'folderPath': pdf.folderPath,
        'folderName': pdf.folderName,
        'dateModified': pdf.dateModified?.toIso8601String(),
        'fileSizeBytes': pdf.fileSizeBytes,
      }).toList();
      
      final jsonString = jsonEncode(jsonList);
      
      // Save to preferences (SharedPreferences can handle large strings)
      await prefs.setString(_cacheKey, jsonString);
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_cacheVersionKey, _currentCacheVersion);
      
      print('PDFCacheService: Saved ${pdfs.length} PDFs to cache');
    } catch (e) {
      print('PDFCacheService: Error saving cache: $e');
    }
  }

  /// Load PDF list from cache
  static Future<List<PDFFile>> loadPDFList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check cache version
      final cacheVersion = prefs.getInt(_cacheVersionKey) ?? 0;
      if (cacheVersion != _currentCacheVersion) {
        print('PDFCacheService: Cache version mismatch, clearing old cache');
        await clearCache();
        return [];
      }
      
      final jsonString = prefs.getString(_cacheKey);
      if (jsonString == null || jsonString.isEmpty) {
        print('PDFCacheService: No cache found');
        return [];
      }
      
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final pdfs = jsonList.map((json) {
        try {
          return PDFFile(
            name: json['name'] as String? ?? 'Unknown',
            date: json['date'] as String? ?? '',
            size: json['size'] as String? ?? '0 B',
            isFavorite: json['isFavorite'] as bool? ?? false,
            filePath: json['filePath'] as String?,
            lastAccessed: json['lastAccessed'] != null
                ? DateTime.tryParse(json['lastAccessed'] as String)
                : null,
            folderPath: json['folderPath'] as String?,
            folderName: json['folderName'] as String?,
            dateModified: json['dateModified'] != null
                ? DateTime.tryParse(json['dateModified'] as String)
                : null,
            fileSizeBytes: json['fileSizeBytes'] as int?,
          );
        } catch (e) {
          print('PDFCacheService: Error parsing PDF from cache: $e');
          return null;
        }
      }).whereType<PDFFile>().toList();
      
      print('PDFCacheService: Loaded ${pdfs.length} PDFs from cache');
      return pdfs;
    } catch (e) {
      print('PDFCacheService: Error loading cache: $e');
      return [];
    }
  }

  /// Check if cache exists and is valid
  static Future<bool> hasCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_cacheKey);
      final cacheVersion = prefs.getInt(_cacheVersionKey) ?? 0;
      
      return jsonString != null && 
             jsonString.isNotEmpty && 
             cacheVersion == _currentCacheVersion;
    } catch (e) {
      return false;
    }
  }

  /// Get cache timestamp
  static Future<DateTime?> getCacheTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      print('PDFCacheService: Error getting cache timestamp: $e');
    }
    return null;
  }

  /// Clear cache
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      await prefs.remove(_cacheVersionKey);
      print('PDFCacheService: Cache cleared');
    } catch (e) {
      print('PDFCacheService: Error clearing cache: $e');
    }
  }

  /// Add a single PDF to cache (for when user imports a new PDF)
  static Future<void> addPDFToCache(PDFFile pdf) async {
    try {
      final existingPDFs = await loadPDFList();
      
      // Check if PDF already exists (by filePath)
      final existingIndex = existingPDFs.indexWhere(
        (p) => p.filePath == pdf.filePath,
      );
      
      if (existingIndex >= 0) {
        // Update existing PDF
        existingPDFs[existingIndex] = pdf;
      } else {
        // Add new PDF
        existingPDFs.add(pdf);
      }
      
      await savePDFList(existingPDFs);
    } catch (e) {
      print('PDFCacheService: Error adding PDF to cache: $e');
    }
  }

  /// Remove a PDF from cache
  static Future<void> removePDFFromCache(String filePath) async {
    try {
      final existingPDFs = await loadPDFList();
      existingPDFs.removeWhere((p) => p.filePath == filePath);
      await savePDFList(existingPDFs);
    } catch (e) {
      print('PDFCacheService: Error removing PDF from cache: $e');
    }
  }

  /// Update a PDF in cache (e.g., when bookmark status changes)
  static Future<void> updatePDFInCache(PDFFile pdf) async {
    try {
      final existingPDFs = await loadPDFList();
      final index = existingPDFs.indexWhere(
        (p) => p.filePath == pdf.filePath,
      );
      
      if (index >= 0) {
        existingPDFs[index] = pdf;
        await savePDFList(existingPDFs);
      }
    } catch (e) {
      print('PDFCacheService: Error updating PDF in cache: $e');
    }
  }
}

