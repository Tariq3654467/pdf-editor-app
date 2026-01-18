import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'screens/splash_screen.dart';
import 'screens/pdf_viewer_screen.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const platform = MethodChannel('com.example.pdf_editor_app/file_intent');
  String? _initialFilePath;

  @override
  void initState() {
    super.initState();
    _getInitialFileIntent();
  }

  Future<void> _getInitialFileIntent() async {
    try {
      final String? filePath = await platform.invokeMethod('getInitialFileIntent');
      if (filePath != null && mounted) {
        // The native code should have already handled content:// URIs and returned a file path
        final file = File(filePath);
        if (file.existsSync()) {
          setState(() {
            _initialFilePath = filePath;
          });
        } else {
          // If it's still a URI string, try to parse it
          final uri = Uri.parse(filePath);
          if (uri.scheme == 'file') {
            final path = uri.path;
            if (File(path).existsSync()) {
              setState(() {
                _initialFilePath = path;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error getting initial file intent: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE53935)),
      ),
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
  runApp(const MyApp());
}
