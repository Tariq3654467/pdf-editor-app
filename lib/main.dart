import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'screens/splash_screen.dart';
import 'screens/pdf_viewer_screen.dart';
import 'services/theme_service.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const platform = MethodChannel('com.example.pdf_editor_app/file_intent');
  String? _initialFilePath;
  // Default to light mode - user must manually enable dark mode
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    // Initialize theme service and load theme mode
    ThemeService.initialize().then((_) {
      if (mounted) {
        setState(() {
          _themeMode = ThemeService.themeModeNotifier.value;
        });
      }
    });
    
    // Listen to theme changes
    ThemeService.themeModeNotifier.addListener(_onThemeChanged);
    
    // Use post-frame callback to avoid crashes during initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getInitialFileIntent();
    });
  }
  
  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        _themeMode = ThemeService.themeModeNotifier.value;
      });
    }
  }
  
  @override
  void dispose() {
    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _getInitialFileIntent() async {
    try {
      final String? filePath = await platform.invokeMethod('getInitialFileIntent')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('Timeout getting initial file intent');
              return null;
            },
          );
      if (filePath != null && mounted) {
        // The native code should have already handled content:// URIs and returned a file path
        try {
          final file = File(filePath);
          if (file.existsSync()) {
            if (mounted) {
              setState(() {
                _initialFilePath = filePath;
              });
            }
          } else {
            // If it's still a URI string, try to parse it
            try {
              final uri = Uri.parse(filePath);
              if (uri.scheme == 'file') {
                final path = uri.path;
                if (File(path).existsSync() && mounted) {
                  setState(() {
                    _initialFilePath = path;
                  });
                }
              }
            } catch (e) {
              print('Error parsing URI: $e');
            }
          }
        } catch (e) {
          print('Error checking file existence: $e');
        }
      }
    } catch (e, stackTrace) {
      print('Error getting initial file intent: $e');
      print('Stack trace: $stackTrace');
      // Don't crash the app, just continue without initial file
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
        ),
        scaffoldBackgroundColor: Colors.white,
        dialogBackgroundColor: Colors.white,
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: Color(0xFF121212),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        dialogBackgroundColor: const Color(0xFF1E1E1E),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1E1E1E),
        ),
        cardColor: const Color(0xFF1E1E1E),
        dividerColor: Colors.white24,
      ),
      themeMode: _themeMode,
      home: _initialFilePath != null && File(_initialFilePath!).existsSync()
          ? PDFViewerScreen(
              filePath: _initialFilePath!,
              fileName: _initialFilePath!.split('/').last,
            )
          : const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

void main() {
  // Set up global error handlers to prevent crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Log to console
    if (kDebugMode) {
      print('Flutter Error: ${details.exception}');
      print('Stack trace: ${details.stack}');
    }
  };

  // Set custom error widget builder
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Log error but show user-friendly message
    if (kDebugMode) {
      return ErrorWidget(details);
    }
    return Material(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please restart the app',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  };

  // Handle errors from async operations
  PlatformDispatcher.instance.onError = (error, stack) {
    print('Platform Error: $error');
    print('Stack trace: $stack');
    return true; // Return true to prevent app from crashing
  };

  // Run app with error zone
  runZonedGuarded(
    () {
      runApp(const MyApp());
    },
    (error, stack) {
      print('Uncaught error: $error');
      print('Stack trace: $stack');
      // Don't crash the app, just log the error
    },
  );
}
