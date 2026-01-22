import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PDFPreferencesService {
  static const String _bookmarksKey = 'pdf_bookmarks';
  static const String _recentAccessKey = 'pdf_recent_access';
  static const String _toolsHistoryKey = 'pdf_tools_history';
  static const String _permissionDialogShownKey = 'permission_dialog_shown';

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

  // Tools History
  static Future<void> addToolsHistory(String operation, String filePath, {String? resultPath}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getToolsHistory();
    
    final historyItem = {
      'operation': operation,
      'filePath': filePath,
      'resultPath': resultPath,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    history.insert(0, historyItem);
    
    // Keep only last 50 history items
    if (history.length > 50) {
      history.removeRange(50, history.length);
    }
    
    await prefs.setString(_toolsHistoryKey, jsonEncode(history));
  }

  static Future<List<Map<String, dynamic>>> getToolsHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_toolsHistoryKey);
    
    if (historyJson == null) {
      return [];
    }
    
    try {
      final decoded = jsonDecode(historyJson) as List<dynamic>;
      return decoded.map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> clearToolsHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_toolsHistoryKey);
  }

  // Track if permission dialog has been shown
  static Future<bool> hasPermissionDialogBeenShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_permissionDialogShownKey) ?? false;
  }

  static Future<void> setPermissionDialogShown(bool shown) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionDialogShownKey, shown);
  }
}

