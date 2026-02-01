# PDF Annotation System - Usage Guide

This document explains how to use the text-aware PDF annotation system.

## Overview

The annotation system provides:
- **Text-aware highlights/underlines**: Annotations anchored to text using MuPDF text quads
- **Freehand pen annotations**: Drawn paths stored in PDF coordinates
- **Eraser tool**: Removes annotations via hit-testing
- **Persistence**: All annotations saved to JSON and reloaded on PDF open
- **Zoom/Scroll support**: Annotations stay correctly positioned during transformations

## Architecture

### Data Models (`lib/models/pdf_annotation.dart`)

- **`TextQuad`**: Represents a text bounding box with 4 corner points
- **`HighlightAnnotation`**: Text-aware highlight using text quads
- **`UnderlineAnnotation`**: Text-aware underline using text quads
- **`PenAnnotation`**: Freehand drawing stored as point array in PDF coordinates

### Storage Service (`lib/services/annotation_storage_service.dart`)

- Saves annotations to JSON files (one per PDF)
- Loads annotations on PDF open
- Provides CRUD operations for annotations

### Native Integration

- **`pdf_text_quad_extractor.cpp`**: Extracts text quads from MuPDF for text selection
- **`MuPDFEditorService`**: Flutter service to call native functions

## Usage Example

### 1. Basic Integration

```dart
import 'package:pdf_editor_app/widgets/text_aware_annotation_overlay.dart';
import 'package:pdf_editor_app/models/pdf_annotation.dart';

class PDFViewerScreen extends StatefulWidget {
  final String pdfPath;
  
  @override
  _PDFViewerScreenState createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  String? _selectedTool; // 'pen', 'highlight', 'underline', 'eraser'
  Color _toolColor = Colors.yellow;
  double _strokeWidth = 2.0;
  double _zoomLevel = 1.0;
  Offset _scrollOffset = Offset.zero;
  int _currentPage = 0;
  Size _pageSize = Size(612, 792); // Default US Letter size
  
  List<PDFAnnotation> _annotations = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextAwareAnnotationOverlay(
        pdfPath: widget.pdfPath,
        currentPage: _currentPage,
        pageSize: _pageSize,
        zoomLevel: _zoomLevel,
        scrollOffset: _scrollOffset,
        selectedTool: _selectedTool,
        toolColor: _toolColor,
        strokeWidth: _strokeWidth,
        onAnnotationsChanged: (annotations) {
          setState(() {
            _annotations = annotations;
          });
        },
        child: YourPDFViewerWidget(
          // Your PDF viewer implementation
        ),
      ),
    );
  }
}
```

### 2. Tool Selection

```dart
// Enable pen tool
setState(() {
  _selectedTool = 'pen';
  _toolColor = Colors.black;
  _strokeWidth = 2.0;
});

// Enable highlight tool
setState(() {
  _selectedTool = 'highlight';
  _toolColor = Colors.yellow;
});

// Enable underline tool
setState(() {
  _selectedTool = 'underline';
  _toolColor = Colors.blue;
  _strokeWidth = 2.0;
});

// Enable eraser
setState(() {
  _selectedTool = 'eraser';
});

// Disable tools
setState(() {
  _selectedTool = null;
});
```

### 3. Working with Annotations

```dart
import 'package:pdf_editor_app/services/annotation_storage_service.dart';

final storage = AnnotationStorageService();

// Load annotations for a PDF
final annotations = await storage.loadAnnotations(pdfPath);

// Get annotations for specific page
final pageAnnotations = await storage.getAnnotationsForPage(pdfPath, pageIndex);

// Remove an annotation
await storage.removeAnnotation(pdfPath, annotationId);

// Clear all annotations
await storage.clearAnnotations(pdfPath);
```

### 4. Manual Annotation Creation

```dart
import 'package:pdf_editor_app/models/pdf_annotation.dart';

// Create a highlight annotation with text quads
final highlight = HighlightAnnotation(
  id: DateTime.now().millisecondsSinceEpoch.toString(),
  pageIndex: 0,
  quads: [
    TextQuad(
      topLeft: Offset(100, 700),
      topRight: Offset(200, 700),
      bottomLeft: Offset(100, 720),
      bottomRight: Offset(200, 720),
      pageIndex: 0,
      text: 'Sample text',
    ),
  ],
  color: Colors.yellow,
  opacity: 0.4,
);

// Create a pen annotation
final pen = PenAnnotation(
  id: DateTime.now().millisecondsSinceEpoch.toString(),
  pageIndex: 0,
  points: [
    Offset(100, 100),
    Offset(150, 120),
    Offset(200, 110),
  ],
  color: Colors.black,
  strokeWidth: 2.0,
);

// Save annotations
await storage.addAnnotation(pdfPath, highlight);
await storage.addAnnotation(pdfPath, pen);
```

## JSON Storage Format

Annotations are stored in JSON files with the following structure:

```json
{
  "pdfPath": "/path/to/file.pdf",
  "annotations": [
    {
      "id": "1234567890",
      "type": "highlight",
      "pageIndex": 0,
      "quads": [
        {
          "topLeft": {"x": 100.0, "y": 700.0},
          "topRight": {"x": 200.0, "y": 700.0},
          "bottomLeft": {"x": 100.0, "y": 720.0},
          "bottomRight": {"x": 200.0, "y": 720.0},
          "pageIndex": 0,
          "text": "Sample text"
        }
      ],
      "color": {"r": 255, "g": 255, "b": 0, "a": 255},
      "opacity": 0.4,
      "createdAt": "2024-01-01T12:00:00.000Z",
      "modifiedAt": null
    },
    {
      "id": "1234567891",
      "type": "pen",
      "pageIndex": 0,
      "points": [
        {"x": 100.0, "y": 100.0},
        {"x": 150.0, "y": 120.0},
        {"x": 200.0, "y": 110.0}
      ],
      "color": {"r": 0, "g": 0, "b": 0, "a": 255},
      "strokeWidth": 2.0,
      "createdAt": "2024-01-01T12:00:00.000Z",
      "modifiedAt": null
    }
  ],
  "lastModified": "2024-01-01T12:00:00.000Z"
}
```

## Coordinate System

### PDF Coordinates
- **Origin**: Bottom-left corner
- **Units**: Points (1/72 inch)
- **Y-axis**: Increases upward

### Screen Coordinates
- **Origin**: Top-left corner
- **Units**: Pixels
- **Y-axis**: Increases downward

### Conversion
The overlay automatically handles coordinate conversion:
- Screen → PDF: Inverts Y-axis and accounts for zoom/scroll
- PDF → Screen: Inverts Y-axis and applies zoom/scroll

## Performance Optimization

1. **Lazy Loading**: Only load annotations for visible pages
2. **Caching**: Cache rendered annotation paths
3. **Debouncing**: Debounce annotation saves during rapid drawing
4. **Hit Testing**: Use bounding box checks before detailed intersection tests

## Building Native Code

Add to `android/app/src/main/cpp/CMakeLists.txt`:

```cmake
add_library(pdf_editor_native SHARED
    pdf_editor_jni.cpp
    pdf_annotation_editor.cpp
    pdf_text_detector.cpp
    pdf_text_editor.cpp
    pdf_text_quad_extractor.cpp  # Add this line
)

target_link_libraries(pdf_editor_native
    android
    log
    mupdf
    mupdfthird
)
```

## Troubleshooting

### Annotations not appearing
- Check that annotations are loaded: `await storage.loadAnnotations(pdfPath)`
- Verify page index matches current page
- Check coordinate conversion (PDF uses bottom-left origin)

### Text quads not found
- Ensure text is selectable (not scanned image)
- Check selection coordinates are in PDF space
- Verify MuPDF text extraction is working

### Eraser not working
- Increase tolerance value in `PenAnnotation.containsPoint()`
- Check hit-testing logic for quads
- Verify annotation IDs are unique

## Future Enhancements

- [ ] Annotation editing (move, resize)
- [ ] Annotation comments/notes
- [ ] Export annotations to PDF annotations layer
- [ ] Multi-page selection
- [ ] Annotation layers/groups
- [ ] Undo/redo support

