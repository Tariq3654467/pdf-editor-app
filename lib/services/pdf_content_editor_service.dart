import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Service for comprehensive PDF content editing using syncfusion_flutter_pdf
/// Provides text editing, image insertion, formatting, and more
class PDFContentEditorService {
  /// Extract text elements from PDF page for editing
  static Future<List<PDFTextElement>> extractTextElements(
    String filePath,
    int pageIndex,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return [];
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        return [];
      }

      final page = document.pages[pageIndex];
      final textElements = <PDFTextElement>[];

      // Extract text using text extraction
      final textExtractor = sf.PdfTextExtractor(document);
      final extractedText = textExtractor.extractText(startPageIndex: pageIndex, endPageIndex: pageIndex);
      
      // Get text bounds (approximate - Syncfusion doesn't provide exact bounds easily)
      // We'll use a simpler approach: detect text regions
      final pageSize = page.size;
      
      // For now, return a single text element representing all text on the page
      // In a full implementation, you'd parse the PDF content stream to get exact positions
      if (extractedText.isNotEmpty) {
        textElements.add(PDFTextElement(
          id: 'text_${pageIndex}_0',
          text: extractedText,
          bounds: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
          pageIndex: pageIndex,
          fontSize: 12.0,
          color: Colors.black,
        ));
      }

      document.dispose();
      return textElements;
    } catch (e) {
      print('Error extracting text elements: $e');
      return [];
    }
  }

  /// Add text to PDF at a specific position
  /// This is a convenience method for adding new text
  static Future<bool> addText(
    String filePath,
    String text,
    int pageIndex,
    Offset position, {
    double fontSize = 12.0,
    Color color = Colors.black,
    sf.PdfFontFamily fontFamily = sf.PdfFontFamily.helvetica,
    bool isBold = false,
    bool isItalic = false,
    sf.PdfTextAlignment alignment = sf.PdfTextAlignment.left,
    String? outputPath,
  }) async {
    try {
      final element = PDFTextElement(
        id: 'text_${DateTime.now().millisecondsSinceEpoch}',
        text: text,
        bounds: Rect.fromLTWH(
          position.dx,
          position.dy,
          200, // Default width
          fontSize * 1.4, // Default height based on font size
        ),
        pageIndex: pageIndex,
        fontSize: fontSize,
        color: color,
        fontFamily: _fontFamilyToString(fontFamily),
        isBold: isBold,
        isItalic: isItalic,
        alignment: alignment,
      );

      return await addOrUpdateTextElement(
        filePath,
        element,
        outputPath: outputPath,
      );
    } catch (e) {
      print('Error adding text: $e');
      return false;
    }
  }

  /// Replace existing text in PDF
  /// Erases old text by drawing white rectangle, then draws new text
  static Future<bool> replaceText(
    String filePath,
    String oldText,
    String newText,
    int pageIndex,
    Rect oldTextBounds, {
    double? fontSize,
    Color? color,
    sf.PdfFontFamily? fontFamily,
    bool? isBold,
    bool? isItalic,
    sf.PdfTextAlignment? alignment,
    String? outputPath,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        return false;
      }

      final page = document.pages[pageIndex];
      final graphics = page.graphics;
      final pageSize = page.size;

      // Erase old text by drawing white rectangle
      final whiteBrush = sf.PdfSolidBrush(sf.PdfColor(255, 255, 255));
      final eraseBounds = Rect.fromLTWH(
        oldTextBounds.left.clamp(0.0, pageSize.width),
        oldTextBounds.top.clamp(0.0, pageSize.height),
        oldTextBounds.width.clamp(0.0, pageSize.width - oldTextBounds.left),
        oldTextBounds.height.clamp(0.0, pageSize.height - oldTextBounds.top),
      );
      graphics.drawRectangle(
        brush: whiteBrush,
        bounds: eraseBounds,
      );

      // Draw new text at the same position
      final finalFontSize = fontSize ?? 12.0;
      final finalColor = color ?? Colors.black;
      final finalFontFamily = fontFamily ?? sf.PdfFontFamily.helvetica;
      final finalIsBold = isBold ?? false;
      final finalIsItalic = isItalic ?? false;
      final finalAlignment = alignment ?? sf.PdfTextAlignment.left;

      final font = sf.PdfStandardFont(
        finalFontFamily,
        finalFontSize,
        style: _getFontStyle(finalIsBold, finalIsItalic),
      );

      final brush = sf.PdfSolidBrush(sf.PdfColor(
        finalColor.red,
        finalColor.green,
        finalColor.blue,
      ));

      final stringFormat = sf.PdfStringFormat();
      stringFormat.alignment = finalAlignment;
      stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
      stringFormat.wordWrap = sf.PdfWordWrapType.word;

      graphics.drawString(
        newText,
        font,
        brush: brush,
        format: stringFormat,
        bounds: eraseBounds,
      );

      // Save modified PDF
      final modifiedBytes = await document.save();
      final targetPath = outputPath ?? filePath;
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(modifiedBytes);
      document.dispose();

      return true;
    } catch (e) {
      print('Error replacing text: $e');
      return false;
    }
  }

  /// Add or update text element in PDF
  static Future<bool> addOrUpdateTextElement(
    String filePath,
    PDFTextElement element, {
    String? outputPath,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      if (element.pageIndex < 0 || element.pageIndex >= document.pages.count) {
        document.dispose();
        return false;
      }

      final page = document.pages[element.pageIndex];
      final graphics = page.graphics;
      final pageSize = page.size;

      // Clamp bounds to page
      final bounds = Rect.fromLTWH(
        element.bounds.left.clamp(0.0, pageSize.width),
        element.bounds.top.clamp(0.0, pageSize.height),
        element.bounds.width.clamp(0.0, pageSize.width - element.bounds.left),
        element.bounds.height.clamp(0.0, pageSize.height - element.bounds.top),
      );

      // Create font with style
      final fontFamily = _stringToFontFamily(element.fontFamily) ?? sf.PdfFontFamily.helvetica;
      final font = sf.PdfStandardFont(
        fontFamily,
        element.fontSize,
        style: _getFontStyle(element.isBold, element.isItalic),
      );

      // Create brush
      final textColor = element.color;
      final brush = sf.PdfSolidBrush(sf.PdfColor(
        textColor.red,
        textColor.green,
        textColor.blue,
      ));

      // Draw text with alignment
      final stringFormat = sf.PdfStringFormat();
      stringFormat.alignment = element.alignment ?? sf.PdfTextAlignment.left;
      stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
      stringFormat.wordWrap = sf.PdfWordWrapType.word;

      graphics.drawString(
        element.text,
        font,
        brush: brush,
        format: stringFormat,
        bounds: bounds,
      );

      // Save modified PDF
      final modifiedBytes = await document.save();
      final targetPath = outputPath ?? filePath;
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(modifiedBytes);
      document.dispose();

      return true;
    } catch (e) {
      print('Error adding/updating text element: $e');
      return false;
    }
  }

  /// Remove text element from PDF by erasing with white rectangle
  static Future<bool> removeTextElement(
    String filePath,
    String elementId,
    int pageIndex,
    Rect bounds, {
    String? outputPath,
  }) async {
    // Note: Removing text from PDF is complex - requires content stream manipulation
    // For now, we'll overlay white rectangle to "erase" text
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        return false;
      }

      final page = document.pages[pageIndex];
      final graphics = page.graphics;
      final pageSize = page.size;

      // Draw white rectangle to cover text (simplified approach)
      // In a full implementation, you'd parse and remove the actual text objects
      final whiteBrush = sf.PdfSolidBrush(sf.PdfColor(255, 255, 255));
      final eraseBounds = Rect.fromLTWH(
        bounds.left.clamp(0.0, pageSize.width),
        bounds.top.clamp(0.0, pageSize.height),
        bounds.width.clamp(0.0, pageSize.width - bounds.left),
        bounds.height.clamp(0.0, pageSize.height - bounds.top),
      );
      graphics.drawRectangle(
        brush: whiteBrush,
        bounds: eraseBounds,
      );

      // Save modified PDF
      final modifiedBytes = await document.save();
      final targetPath = outputPath ?? filePath;
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(modifiedBytes);
      document.dispose();

      return true;
    } catch (e) {
      print('Error removing text element: $e');
      return false;
    }
  }

  /// Add image to PDF
  static Future<bool> addImageToPDF(
    String filePath,
    PDFImageElement element, {
    String? outputPath,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      if (element.pageIndex < 0 || element.pageIndex >= document.pages.count) {
        document.dispose();
        return false;
      }

      final page = document.pages[element.pageIndex];
      final graphics = page.graphics;
      final pageSize = page.size;

      // Load image
      final imageFile = File(element.imagePath);
      if (!await imageFile.exists()) {
        document.dispose();
        return false;
      }

      final imageBytes = await imageFile.readAsBytes();
      final pdfImage = sf.PdfBitmap(imageBytes);

      // Clamp bounds to page
      final bounds = Rect.fromLTWH(
        element.bounds.left.clamp(0.0, pageSize.width),
        element.bounds.top.clamp(0.0, pageSize.height),
        element.bounds.width.clamp(0.0, pageSize.width - element.bounds.left),
        element.bounds.height.clamp(0.0, pageSize.height - element.bounds.top),
      );

      // Draw image
      graphics.drawImage(
        pdfImage,
        bounds,
      );

      // Save modified PDF
      final modifiedBytes = await document.save();
      final targetPath = outputPath ?? filePath;
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(modifiedBytes);
      document.dispose();

      return true;
    } catch (e) {
      print('Error adding image to PDF: $e');
      return false;
    }
  }

  /// Add image from bytes to PDF
  static Future<bool> addImageFromBytes(
    String filePath,
    Uint8List imageBytes,
    int pageIndex,
    Rect bounds, {
    String? outputPath,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        return false;
      }

      final page = document.pages[pageIndex];
      final graphics = page.graphics;
      final pageSize = page.size;

      final pdfImage = sf.PdfBitmap(imageBytes);

      // Clamp bounds to page
      final imageBounds = Rect.fromLTWH(
        bounds.left.clamp(0.0, pageSize.width),
        bounds.top.clamp(0.0, pageSize.height),
        bounds.width.clamp(0.0, pageSize.width - bounds.left),
        bounds.height.clamp(0.0, pageSize.height - bounds.top),
      );

      // Draw image
      graphics.drawImage(
        pdfImage,
        imageBounds,
      );

      // Save modified PDF
      final modifiedBytes = await document.save();
      final targetPath = outputPath ?? filePath;
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(modifiedBytes);
      document.dispose();

      return true;
    } catch (e) {
      print('Error adding image from bytes: $e');
      return false;
    }
  }

  /// Save all edits to PDF (batch operation)
  static Future<bool> saveAllEdits(
    String filePath,
    List<PDFTextElement> textElements,
    List<PDFImageElement> imageElements, {
    String? outputPath,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      // Group elements by page
      final textByPage = <int, List<PDFTextElement>>{};
      final imagesByPage = <int, List<PDFImageElement>>{};

      for (var element in textElements) {
        textByPage.putIfAbsent(element.pageIndex, () => []).add(element);
      }

      for (var element in imageElements) {
        imagesByPage.putIfAbsent(element.pageIndex, () => []).add(element);
      }

      // Apply edits to each page
      for (int pageIndex = 0; pageIndex < document.pages.count; pageIndex++) {
        final page = document.pages[pageIndex];
        final graphics = page.graphics;
        final pageSize = page.size;

        // Add text elements
        final pageTexts = textByPage[pageIndex] ?? [];
        for (var element in pageTexts) {
          final fontFamily = _stringToFontFamily(element.fontFamily) ?? sf.PdfFontFamily.helvetica;
          final font = sf.PdfStandardFont(
            fontFamily,
            element.fontSize,
            style: _getFontStyle(element.isBold, element.isItalic),
          );

          final textColor = element.color;
          final brush = sf.PdfSolidBrush(sf.PdfColor(
            textColor.red,
            textColor.green,
            textColor.blue,
          ));

          final stringFormat = sf.PdfStringFormat();
          stringFormat.alignment = element.alignment ?? sf.PdfTextAlignment.left;
          stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
          stringFormat.wordWrap = sf.PdfWordWrapType.word;

          final bounds = Rect.fromLTWH(
            element.bounds.left.clamp(0.0, pageSize.width),
            element.bounds.top.clamp(0.0, pageSize.height),
            element.bounds.width.clamp(0.0, pageSize.width - element.bounds.left),
            element.bounds.height.clamp(0.0, pageSize.height - element.bounds.top),
          );

          graphics.drawString(
            element.text,
            font,
            brush: brush,
            format: stringFormat,
            bounds: bounds,
          );
        }

        // Add image elements
        final pageImages = imagesByPage[pageIndex] ?? [];
        for (var element in pageImages) {
          try {
            final imageFile = File(element.imagePath);
            if (await imageFile.exists()) {
              final imageBytes = await imageFile.readAsBytes();
              final pdfImage = sf.PdfBitmap(imageBytes);

              final bounds = Rect.fromLTWH(
                element.bounds.left.clamp(0.0, pageSize.width),
                element.bounds.top.clamp(0.0, pageSize.height),
                element.bounds.width.clamp(0.0, pageSize.width - element.bounds.left),
                element.bounds.height.clamp(0.0, pageSize.height - element.bounds.top),
              );

              graphics.drawImage(pdfImage, bounds);
            }
          } catch (e) {
            print('Error adding image to page $pageIndex: $e');
          }
        }
      }

      // Save modified PDF
      final modifiedBytes = await document.save();
      final targetPath = outputPath ?? filePath;
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(modifiedBytes);
      document.dispose();

      return true;
    } catch (e) {
      print('Error saving all edits: $e');
      return false;
    }
  }

  /// Create a copy of PDF for editing (preserves original)
  static Future<String?> createEditableCopy(String originalPath) async {
    try {
      final originalFile = File(originalPath);
      if (!await originalFile.exists()) {
        return null;
      }

      final directory = await getApplicationDocumentsDirectory();
      final pdfDirectory = Directory('${directory.path}/PDFs');
      if (!await pdfDirectory.exists()) {
        await pdfDirectory.create(recursive: true);
      }

      final fileName = path.basenameWithoutExtension(originalPath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final copyPath = '${pdfDirectory.path}/${fileName}_editable_$timestamp.pdf';

      // Copy file
      await originalFile.copy(copyPath);

      return copyPath;
    } catch (e) {
      print('Error creating editable copy: $e');
      return null;
    }
  }

  /// Draw rectangle on PDF (useful for highlighting or erasing)
  static Future<bool> drawRectangle(
    String filePath,
    int pageIndex,
    Rect bounds, {
    Color? fillColor,
    Color? strokeColor,
    double strokeWidth = 1.0,
    String? outputPath,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        return false;
      }

      final page = document.pages[pageIndex];
      final graphics = page.graphics;
      final pageSize = page.size;

      final rectBounds = Rect.fromLTWH(
        bounds.left.clamp(0.0, pageSize.width),
        bounds.top.clamp(0.0, pageSize.height),
        bounds.width.clamp(0.0, pageSize.width - bounds.left),
        bounds.height.clamp(0.0, pageSize.height - bounds.top),
      );

      if (fillColor != null) {
        final brush = sf.PdfSolidBrush(sf.PdfColor(
          fillColor.red,
          fillColor.green,
          fillColor.blue,
        ));
        graphics.drawRectangle(
          brush: brush,
          bounds: rectBounds,
        );
      }

      if (strokeColor != null) {
        final pen = sf.PdfPen(
          sf.PdfColor(
            strokeColor.red,
            strokeColor.green,
            strokeColor.blue,
          ),
          width: strokeWidth,
        );
        graphics.drawRectangle(
          pen: pen,
          bounds: rectBounds,
        );
      }

      // Save modified PDF
      final modifiedBytes = await document.save();
      final targetPath = outputPath ?? filePath;
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(modifiedBytes);
      document.dispose();

      return true;
    } catch (e) {
      print('Error drawing rectangle: $e');
      return false;
    }
  }

  /// Helper methods
  static sf.PdfFontStyle _getFontStyle(bool isBold, bool isItalic) {
    if (isBold) {
      return sf.PdfFontStyle.bold;
    } else if (isItalic) {
      return sf.PdfFontStyle.italic;
    } else {
      return sf.PdfFontStyle.regular;
    }
  }

  static String _fontFamilyToString(sf.PdfFontFamily family) {
    switch (family) {
      case sf.PdfFontFamily.helvetica:
        return 'helvetica';
      case sf.PdfFontFamily.timesRoman:
        return 'timesRoman';
      case sf.PdfFontFamily.courier:
        return 'courier';
      default:
        return 'helvetica';
    }
  }

  static sf.PdfFontFamily? _stringToFontFamily(String? familyStr) {
    if (familyStr == null) return null;
    final lower = familyStr.toLowerCase();
    if (lower.contains('helvetica')) return sf.PdfFontFamily.helvetica;
    if (lower.contains('times') || lower.contains('roman')) return sf.PdfFontFamily.timesRoman;
    if (lower.contains('courier')) return sf.PdfFontFamily.courier;
    return sf.PdfFontFamily.helvetica;
  }
}

/// Represents a text element in PDF (for editing)
class PDFTextElement {
  final String id;
  final String text;
  final Rect bounds;
  final int pageIndex;
  final double fontSize;
  final Color color;
  final String? fontFamily;
  final bool isBold;
  final bool isItalic;
  final sf.PdfTextAlignment? alignment;

  PDFTextElement({
    required this.id,
    required this.text,
    required this.bounds,
    required this.pageIndex,
    this.fontSize = 12.0,
    this.color = Colors.black,
    this.fontFamily,
    this.isBold = false,
    this.isItalic = false,
    this.alignment,
  });

  PDFTextElement copyWith({
    String? id,
    String? text,
    Rect? bounds,
    int? pageIndex,
    double? fontSize,
    Color? color,
    String? fontFamily,
    bool? isBold,
    bool? isItalic,
    sf.PdfTextAlignment? alignment,
  }) {
    return PDFTextElement(
      id: id ?? this.id,
      text: text ?? this.text,
      bounds: bounds ?? this.bounds,
      pageIndex: pageIndex ?? this.pageIndex,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      alignment: alignment ?? this.alignment,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'bounds': {
        'left': bounds.left,
        'top': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      },
      'pageIndex': pageIndex,
      'fontSize': fontSize,
      'color': {
        'r': color.red,
        'g': color.green,
        'b': color.blue,
        'a': color.alpha,
      },
      'fontFamily': fontFamily,
      'isBold': isBold,
      'isItalic': isItalic,
      'alignment': alignment?.toString(),
    };
  }

  static PDFTextElement fromMap(Map<String, dynamic> map) {
    return PDFTextElement(
      id: map['id'] as String,
      text: map['text'] as String,
      bounds: Rect.fromLTWH(
        (map['bounds'] as Map)['left'] as double,
        (map['bounds'] as Map)['top'] as double,
        (map['bounds'] as Map)['width'] as double,
        (map['bounds'] as Map)['height'] as double,
      ),
      pageIndex: map['pageIndex'] as int,
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 12.0,
      color: Color.fromARGB(
        (map['color'] as Map)['a'] as int? ?? 255,
        (map['color'] as Map)['r'] as int? ?? 0,
        (map['color'] as Map)['g'] as int? ?? 0,
        (map['color'] as Map)['b'] as int? ?? 0,
      ),
      fontFamily: map['fontFamily'] as String?,
      isBold: map['isBold'] as bool? ?? false,
      isItalic: map['isItalic'] as bool? ?? false,
      alignment: _parseAlignment(map['alignment'] as String?),
    );
  }

  static sf.PdfTextAlignment? _parseAlignment(String? alignmentStr) {
    if (alignmentStr == null) return null;
    final str = alignmentStr.toLowerCase();
    if (str.contains('left')) return sf.PdfTextAlignment.left;
    if (str.contains('center')) return sf.PdfTextAlignment.center;
    if (str.contains('right')) return sf.PdfTextAlignment.right;
    if (str.contains('justify')) return sf.PdfTextAlignment.justify;
    return sf.PdfTextAlignment.left;
  }
}

/// Represents an image element in PDF (for editing)
class PDFImageElement {
  final String id;
  final String imagePath;
  final Rect bounds;
  final int pageIndex;

  PDFImageElement({
    required this.id,
    required this.imagePath,
    required this.bounds,
    required this.pageIndex,
  });

  PDFImageElement copyWith({
    String? id,
    String? imagePath,
    Rect? bounds,
    int? pageIndex,
  }) {
    return PDFImageElement(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      bounds: bounds ?? this.bounds,
      pageIndex: pageIndex ?? this.pageIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imagePath': imagePath,
      'bounds': {
        'left': bounds.left,
        'top': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      },
      'pageIndex': pageIndex,
    };
  }

  static PDFImageElement fromMap(Map<String, dynamic> map) {
    return PDFImageElement(
      id: map['id'] as String,
      imagePath: map['imagePath'] as String,
      bounds: Rect.fromLTWH(
        (map['bounds'] as Map)['left'] as double,
        (map['bounds'] as Map)['top'] as double,
        (map['bounds'] as Map)['width'] as double,
        (map['bounds'] as Map)['height'] as double,
      ),
      pageIndex: map['pageIndex'] as int,
    );
  }
}
