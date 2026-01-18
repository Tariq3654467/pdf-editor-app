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
      final String? fileUri = await platform.invokeMethod('getInitialFileIntent');
      if (fileUri != null && mounted) {
        // Convert URI to file path
        final uri = Uri.parse(fileUri);
        if (uri.scheme == 'file') {
          final filePath = uri.path;
          if (File(filePath).existsSync()) {
            setState(() {
              _initialFilePath = filePath;
            });
          }
        } else if (uri.scheme == 'content' && Platform.isAndroid) {
          // For content:// URIs, we'll need to handle via file_picker or similar
          // For now, try to extract path
          setState(() {
            _initialFilePath = fileUri;
          });
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
