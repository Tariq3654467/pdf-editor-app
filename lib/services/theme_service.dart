import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const String _themeModeKey = 'theme_mode';
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
  
  /// Initialize theme mode notifier
  static Future<void> initialize() async {
    final themeMode = await getThemeMode();
    themeModeNotifier.value = themeMode;
  }
  
  /// Get current theme mode from preferences
  static Future<ThemeMode> getThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString(_themeModeKey);
      
      if (themeModeString == null) {
        return ThemeMode.system;
      }
      
      switch (themeModeString) {
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
        case 'system':
        default:
          return ThemeMode.system;
      }
    } catch (e) {
      print('Error getting theme mode: $e');
      return ThemeMode.system;
    }
  }
  
  /// Save theme mode to preferences
  static Future<void> setThemeMode(ThemeMode themeMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String themeModeString;
      
      switch (themeMode) {
        case ThemeMode.light:
          themeModeString = 'light';
          break;
        case ThemeMode.dark:
          themeModeString = 'dark';
          break;
        case ThemeMode.system:
        default:
          themeModeString = 'system';
          break;
      }
      
      await prefs.setString(_themeModeKey, themeModeString);
      // Notify listeners
      themeModeNotifier.value = themeMode;
    } catch (e) {
      print('Error saving theme mode: $e');
    }
  }
  
  /// Check if dark mode is currently active
  static bool isDarkMode(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark;
  }
}

