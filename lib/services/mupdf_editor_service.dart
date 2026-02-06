import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// PDF Text Object returned from native MuPDF layer
class PDFTextObject {
  final String text;
  final String fontName;
  final double fontSize;
  final double x;
  final double y;
  final double width;
  final double height;
  final String objectId;
  final int pageIndex;
  
  PDFTextObject({
    required this.text,
    required this.fontName,
    required this.fontSize,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.objectId,
    required this.pageIndex,
  });
  
  factory PDFTextObject.fromMap(Map<dynamic, dynamic> map) {
    return PDFTextObject(
      text: map['text'] as String,
      fontName: map['fontName'] as String,
      fontSize: (map['fontSize'] as num).toDouble(),
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
      objectId: map['objectId'] as String,
      pageIndex: map['pageIndex'] as int,
    );
  }
}

/// Service for PDF editing using MuPDF native engine
/// 
/// This service communicates with native Android code that uses MuPDF
/// for true PDF content stream editing (not overlays or annotations)
class MuPDFEditorService {
  static const MethodChannel _channel = MethodChannel('com.example.pdf_editor_app/pdf_editor');
  
  /// Load PDF document in native layer
  static Future<bool> loadPdf(String pdfPath) async {
    try {
      final result = await _channel.invokeMethod<bool>('loadPdf', {
        'path': pdfPath,
      });
      return result ?? false;
    } catch (e) {
      print('Error loading PDF: $e');
      return false;
    }
  }
  
  /// Get text object at specific position in PDF
  /// 
  /// This uses MuPDF to:
  /// 1. Map screen coordinates to PDF space
  /// 2. Detect nearest text object
  /// 3. Return text object with font, size, bounds, etc.
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param x X coordinate in PDF space
  /// @param y Y coordinate in PDF space
  /// @return PDFTextObject or null if not found
  static Future<PDFTextObject?> getTextAt(
    String pdfPath,
    int pageIndex,
    double x,
    double y,
  ) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getTextAt', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'x': x,
        'y': y,
      });
      
      if (result != null) {
        return PDFTextObject.fromMap(result);
      }
      return null;
    } catch (e) {
      print('Error getting text at position: $e');
      return null;
    }
  }
  
  /// Replace text in PDF content stream
  /// 
  /// This uses MuPDF to:
  /// 1. Find text object by objectId
  /// 2. Replace text in content stream
  /// 3. Preserve font, size, position, encoding
  /// 4. Rewrite PDF safely
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param objectId PDF object identifier
  /// @param newText New text content
  /// @return true if successful
  static Future<bool> replaceText(
    String pdfPath,
    int pageIndex,
    String objectId,
    String newText,
  ) async {
    try {
      final result = await _channel.invokeMethod<bool>('replaceText', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'objectId': objectId,
        'newText': newText,
      });
      return result ?? false;
    } catch (e) {
      print('Error replacing text: $e');
      return false;
    }
  }
  
  /// Save PDF after editing
  /// 
  /// @param pdfPath Path to PDF file
  /// @return true if successful
  static Future<bool> savePdf(String pdfPath) async {
    try {
      final result = await _channel.invokeMethod<bool>('savePdf', {
        'path': pdfPath,
      });
      return result ?? false;
    } catch (e) {
      print('Error saving PDF: $e');
      return false;
    }
  }
  
  /// Add pen annotation (freehand path) to PDF content stream
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param points List of points (x, y coordinates in PDF space)
  /// @param color Annotation color
  /// @param strokeWidth Stroke width in points
  /// @return true if successful
  static Future<bool> addPenAnnotation(
    String pdfPath,
    int pageIndex,
    List<Offset> points,
    Color color,
    double strokeWidth,
  ) async {
    try {
      if (points.isEmpty) return false;
      
      final pointsX = points.map((p) => p.dx).toList();
      final pointsY = points.map((p) => p.dy).toList();
      
      final result = await _channel.invokeMethod<bool>('addPenAnnotation', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'pointsX': pointsX,
        'pointsY': pointsY,
        'colorR': color.red,
        'colorG': color.green,
        'colorB': color.blue,
        'strokeWidth': strokeWidth,
      });
      return result ?? false;
    } catch (e) {
      print('Error adding pen annotation: $e');
      return false;
    }
  }
  
  /// Add highlight annotation (filled rectangle) to PDF content stream
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param rect Rectangle bounds in PDF space
  /// @param color Highlight color
  /// @param opacity Opacity (0.0-1.0)
  /// @return true if successful
  static Future<bool> addHighlightAnnotation(
    String pdfPath,
    int pageIndex,
    Rect rect,
    Color color,
    double opacity,
  ) async {
    try {
      // PDF rectangle command expects (x, y, width, height) where (x,y) is bottom-left
      // rect.top is already the bottom Y after coordinate conversion
      final result = await _channel.invokeMethod<bool>('addHighlightAnnotation', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'x': rect.left,
        'y': rect.top, // This is bottom Y in PDF coordinates after Y inversion
        'width': rect.width,
        'height': rect.height,
        'colorR': color.red,
        'colorG': color.green,
        'colorB': color.blue,
        'opacity': opacity,
      });
      return result ?? false;
    } catch (e) {
      print('Error adding highlight annotation: $e');
      return false;
    }
  }
  
  /// Add underline annotation (line) to PDF content stream
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param start Start point of line in PDF space
  /// @param end End point of line in PDF space
  /// @param color Line color
  /// @param strokeWidth Stroke width in points
  /// @return true if successful
  static Future<bool> addUnderlineAnnotation(
    String pdfPath,
    int pageIndex,
    Offset start,
    Offset end,
    Color color,
    double strokeWidth,
  ) async {
    try {
      final result = await _channel.invokeMethod<bool>('addUnderlineAnnotation', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'x1': start.dx,
        'y1': start.dy,
        'x2': end.dx,
        'y2': end.dy,
        'colorR': color.red,
        'colorG': color.green,
        'colorB': color.blue,
        'strokeWidth': strokeWidth,
      });
      return result ?? false;
    } catch (e) {
      print('Error adding underline annotation: $e');
      return false;
    }
  }
  
  /// Get text quads (bounding boxes) for text selection range
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param start Start point of selection in PDF space
  /// @param end End point of selection in PDF space
  /// @return JSON string containing array of quads
  static Future<String?> getTextQuadsForSelection(
    String pdfPath,
    int pageIndex,
    Offset start,
    Offset end,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('getTextQuadsForSelection', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'startX': start.dx,
        'startY': start.dy,
        'endX': end.dx,
        'endY': end.dy,
      });
      return result;
    } catch (e) {
      print('Error getting text quads: $e');
      return null;
    }
  }
  
  /// Render PDF page to image bytes (PNG format)
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param scale Scale factor for thumbnail (0.0-1.0, e.g., 0.3 for 30% size)
  /// @return Uint8List containing PNG image bytes, or null if failed
  static Future<Uint8List?> renderPageToImage(
    String pdfPath,
    int pageIndex,
    double scale,
  ) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('renderPageToImage', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'scale': scale,
      });
      return result;
    } catch (e) {
      print('Error rendering page to image: $e');
      return null;
    }
  }
}

