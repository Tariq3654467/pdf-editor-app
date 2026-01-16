import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PDFPreferencesService {
  static const String _bookmarksKey = 'pdf_bookmarks';
  static const String _recentAccessKey = 'pdf_recent_access';

  // Save bookmark status for a PDF file
  static Future<void> setBookmark(String filePath, bool isBookmarked) async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = await getBookmarks();
    
    if (isBookmarked) {
      bookmarks.add(filePath);
    } else {
      bookmarks.remove(filePath);
    }
    
    await prefs.setStringList(_bookmarksKey, bookmarks.toList());
  }

  // Get all bookmarked file paths
  static Future<Set<String>> getBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarksList = prefs.getStringList(_bookmarksKey) ?? [];
    return bookmarksList.toSet();
  }

  // Check if a PDF is bookmarked
  static Future<bool> isBookmarked(String filePath) async {
    final bookmarks = await getBookmarks();
    return bookmarks.contains(filePath);
  }

  // Save last accessed time for a PDF file
  static Future<void> setLastAccessed(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final recentAccess = await getRecentAccess();
    
    recentAccess[filePath] = DateTime.now().toIso8601String();
    
    // Keep only last 100 recent files
    if (recentAccess.length > 100) {
      final sortedEntries = recentAccess.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      recentAccess.clear();
      for (var entry in sortedEntries.take(100)) {
        recentAccess[entry.key] = entry.value;
      }
    }
    
    await prefs.setString(_recentAccessKey, jsonEncode(recentAccess));
  }

  // Get all recent access times
  static Future<Map<String, String>> getRecentAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final recentAccessJson = prefs.getString(_recentAccessKey);
    
    if (recentAccessJson == null) {
      return {};
    }
    
    try {
      final decoded = jsonDecode(recentAccessJson) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      return {};
    }
  }

  // Get last accessed time for a specific PDF
  static Future<DateTime?> getLastAccessed(String filePath) async {
    final recentAccess = await getRecentAccess();
    final lastAccessedStr = recentAccess[filePath];
    
    if (lastAccessedStr == null) {
      return null;
    }
    
    try {
      return DateTime.parse(lastAccessedStr);
    } catch (e) {
      return null;
    }
  }
}

