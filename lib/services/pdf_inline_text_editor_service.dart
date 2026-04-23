import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// PDF Text Object returned from native Java PDFBox layer
class PDFInlineTextObject {
  final String text;
  final String fontName;
  final double fontSize;
  final double x;
  final double y;
  final double width;
  final double height;
  final String objectId;
  final int pageIndex;
  final int colorR;
  final int colorG;
  final int colorB;
  
  PDFInlineTextObject({
    required this.text,
    required this.fontName,
    required this.fontSize,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.objectId,
    required this.pageIndex,
    required this.colorR,
    required this.colorG,
    required this.colorB,
  });
  
  factory PDFInlineTextObject.fromMap(Map<dynamic, dynamic> map) {
    return PDFInlineTextObject(
      text: map['text'] as String? ?? '',
      fontName: map['fontName'] as String? ?? 'Helvetica',
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 12.0,
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      width: (map['width'] as num?)?.toDouble() ?? 0.0,
      height: (map['height'] as num?)?.toDouble() ?? 0.0,
      objectId: map['objectId'] as String? ?? '',
      pageIndex: map['pageIndex'] as int? ?? 0,
      colorR: map['colorR'] as int? ?? 0,
      colorG: map['colorG'] as int? ?? 0,
      colorB: map['colorB'] as int? ?? 0,
    );
  }
  
  Color get color => Color.fromRGBO(colorR, colorG, colorB, 1.0);
}

/// Service for native Java PDF inline text editing using Apache PDFBox
/// 
/// This service communicates with native Android Java code that uses Apache PDFBox
/// for true inline PDF text editing (editing actual text content in PDF streams)
class PDFInlineTextEditorService {
  static const MethodChannel _channel = MethodChannel('com.example.pdf_editor_app/pdf_inline_text_editor');
  
  /// Get text object at specific position in PDF
  /// 
  /// This uses Apache PDFBox to:
  /// 1. Parse PDF content streams
  /// 2. Extract text objects with position information
  /// 3. Find the text object closest to the given position
  /// 4. Return text object with font, size, bounds, color, etc.
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param x X coordinate in PDF space
  /// @param y Y coordinate in PDF space
  /// @return PDFInlineTextObject or null if not found
  static Future<PDFInlineTextObject?> getTextAt(
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
        return PDFInlineTextObject.fromMap(result);
      }
      return null;
    } catch (e) {
      print('Error getting text at position: $e');
      return null;
    }
  }
  
  /// Replace text in PDF content stream
  /// 
  /// This uses iText 7 to:
  /// 1. Find text object by objectId (supports float coordinates)
  /// 2. Fallback to coordinate-based search if objectId fails
  /// 3. Replace text using overlay approach (white rectangle + new text)
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param objectId PDF object identifier (format: obj_page_x_y)
  /// @param newText New text content
  /// @param x Optional X coordinate for fallback mechanism
  /// @param y Optional Y coordinate for fallback mechanism
  /// @return true if successful
  static Future<bool> replaceText(
    String pdfPath,
    int pageIndex,
    String objectId,
    String newText, {
    double? x,
    double? y,
  }) async {
    try {
      final arguments = <String, dynamic>{
        'path': pdfPath,
        'pageIndex': pageIndex,
        'objectId': objectId,
        'newText': newText,
      };
      
      // Add coordinates if provided for fallback mechanism
      if (x != null && y != null) {
        arguments['x'] = x;
        arguments['y'] = y;
      }
      
      print('PDFInlineTextEditorService.replaceText: Calling native method with objectId=$objectId, x=$x, y=$y');
      final result = await _channel.invokeMethod<bool>('replaceText', arguments);
      final success = result ?? false;
      print('PDFInlineTextEditorService.replaceText: Native method returned: $success');
      return success;
    } catch (e) {
      print('PDFInlineTextEditorService.replaceText: Error - $e');
      return false;
    }
  }
  
  /// Add new text to PDF at a specific position
  /// 
  /// This uses Apache PDFBox to add text directly to the PDF content stream
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @param text Text to add
  /// @param x X coordinate in PDF space
  /// @param y Y coordinate in PDF space
  /// @param fontSize Font size (default: 12.0)
  /// @param fontName Font name (default: "Helvetica")
  /// @param color Text color (default: black)
  /// @return true if successful
  static Future<bool> addText(
    String pdfPath,
    int pageIndex,
    String text,
    double x,
    double y, {
    double fontSize = 12.0,
    String fontName = 'Helvetica',
    Color color = Colors.black,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('addText', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'text': text,
        'x': x,
        'y': y,
        'fontSize': fontSize,
        'fontName': fontName,
        'colorR': color.red,
        'colorG': color.green,
        'colorB': color.blue,
      });
      return result ?? false;
    } catch (e) {
      print('Error adding text: $e');
      return false;
    }
  }
  
  /// Get all text objects on a page
  /// 
  /// This uses Apache PDFBox to extract all text objects with their positions
  /// 
  /// @param pdfPath Path to PDF file
  /// @param pageIndex Page number (0-based)
  /// @return List of PDFInlineTextObject
  static Future<List<PDFInlineTextObject>> getAllTextObjects(
    String pdfPath,
    int pageIndex,
  ) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getAllTextObjects', {
        'path': pdfPath,
        'pageIndex': pageIndex,
      });
      
      if (result != null) {
        return result
            .map((item) => PDFInlineTextObject.fromMap(item as Map<dynamic, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('Error getting all text objects: $e');
      return [];
    }
  }
}

