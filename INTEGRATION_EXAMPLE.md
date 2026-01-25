# Quick Integration Example

## Replace Annotation Overlay in PDF Viewer Screen

In `lib/screens/pdf_viewer_screen.dart`, replace:

```dart
// OLD (causes ANR):
PDFAnnotationOverlay(
  key: _annotationOverlayKey,
  // ... props
)

// NEW (optimized):
PDFAnnotationOverlayOptimized(
  key: _annotationOverlayKey,
  // ... same props
)
```

## Update Save Function

Replace synchronous save with async isolate-based save:

```dart
// OLD (blocks UI):
Future<void> _savePDF() async {
  final document = PdfDocument(inputBytes: bytes);
  // ... modify document
  await file.writeAsBytes(document.save());
  document.dispose();
}

// NEW (non-blocking):
Future<void> _savePDF() async {
  final annotations = _annotationOverlayKey.currentState?.annotations ?? [];
  await PDFSaveService.savePDFWithProgress(
    context: context,
    filePath: _actualFilePath!,
    annotations: annotations,
    successMessage: 'PDF saved successfully',
  );
}
```

## Initialize Page Cache

In `main.dart` or app initialization:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize page cache
  await PDFPageCache().initialize();
  
  runApp(const MyApp());
}
```

## Load PDF Info Asynchronously

```dart
// OLD (blocks UI):
Future<void> _loadPDFInfo() async {
  final document = PdfDocument(inputBytes: bytes);
  setState(() {
    _totalPages = document.pages.count;
  });
  document.dispose();
}

// NEW (non-blocking):
Future<void> _loadPDFInfo() async {
  final info = await PDFIsolateService.loadPDFInfo(_actualFilePath!);
  if (mounted && info.isValid) {
    setState(() {
      _totalPages = info.pageCount;
    });
  }
}
```

## Add RepaintBoundary to PDF Viewer

```dart
RepaintBoundary(
  child: SfPdfViewer.file(
    file,
    // ... props
  ),
)
```

