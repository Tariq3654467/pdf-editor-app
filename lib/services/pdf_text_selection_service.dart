import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:flutter/material.dart';

/// Represents a text element found in PDF
class SelectedTextElement {
  final String text;
  final Rect bounds;
  final int pageIndex;
  final double fontSize;
  final Color color;
  final String? fontFamily;
  final bool isBold;
  final bool isItalic;
  final Offset position; // Position in PDF coordinates

  SelectedTextElement({
    required this.text,
    required this.bounds,
    required this.pageIndex,
    this.fontSize = 12.0,
    this.color = Colors.black,
    this.fontFamily,
    this.isBold = false,
    this.isItalic = false,
    required this.position,
  });
}

/// Service for detecting and editing selected text in PDF (Sejda-style)
class PDFTextSelectionService {
  /// Find text at a specific position in PDF
  /// Returns null if no text found at that position
  static Future<SelectedTextElement?> findTextAtPosition(
    String filePath,
    int pageIndex,
    Offset pdfPosition,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        return null;
      }

      final page = document.pages[pageIndex];
      final pageSize = page.size;

      // Use text extractor to get text with bounds
      final textExtractor = sf.PdfTextExtractor(document);
      
      // Extract text from the specific page
      // Note: Syncfusion doesn't provide exact text bounds easily
      // We'll use a workaround: extract all text and approximate positions
      
      final extractedText = textExtractor.extractText(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );

      document.dispose();

      // For now, return a simplified text element
      // In a full implementation, you'd parse PDF content stream to get exact bounds
      if (extractedText.isNotEmpty) {
        // Approximate: assume text starts at the tap position
        return SelectedTextElement(
          text: extractedText,
          bounds: Rect.fromLTWH(
            pdfPosition.dx,
            pdfPosition.dy,
            200, // Approximate width
            20, // Approximate height
          ),
          pageIndex: pageIndex,
          fontSize: 12.0,
          color: Colors.black,
          position: pdfPosition,
        );
      }

      return null;
    } catch (e) {
      print('Error finding text at position: $e');
      return null;
    }
  }

  /// Replace text in PDF with formatted version
  static Future<bool> replaceTextWithFormatting(
    String filePath,
    int pageIndex,
    String oldText,
    String newText,
    Offset position, {
    double? fontSize,
    Color? color,
    String? fontFamily,
    bool? isBold,
    bool? isItalic,
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

      // Clamp position to page bounds
      final pdfX = position.dx.clamp(0.0, pageSize.width);
      final pdfY = position.dy.clamp(0.0, pageSize.height);

      // Create font with formatting
      sf.PdfFont font;
      if (fontFamily != null) {
        // Map font family names to Syncfusion font families
        sf.PdfFontFamily fontFamilyEnum;
        switch (fontFamily.toLowerCase()) {
          case 'helvetica':
          case 'arial':
            fontFamilyEnum = sf.PdfFontFamily.helvetica;
            break;
          case 'times-roman':
          case 'times new roman':
            fontFamilyEnum = sf.PdfFontFamily.timesRoman;
            break;
          case 'courier':
            fontFamilyEnum = sf.PdfFontFamily.courier;
            break;
          default:
            fontFamilyEnum = sf.PdfFontFamily.helvetica;
        }
        font = sf.PdfStandardFont(
          fontFamilyEnum,
          fontSize ?? 12,
          style: _getFontStyle(isBold ?? false, isItalic ?? false),
        );
      } else {
        font = sf.PdfStandardFont(
          sf.PdfFontFamily.helvetica,
          fontSize ?? 12,
          style: _getFontStyle(isBold ?? false, isItalic ?? false),
        );
      }

      // Create brush with color
      final textColor = color ?? Colors.black;
      final brush = sf.PdfSolidBrush(sf.PdfColor(
        textColor.red,
        textColor.green,
        textColor.blue,
      ));

      // Draw new text (this overlays the old text)
      // Note: True text replacement would require removing old text objects from PDF structure
      // For now, we overlay the new formatted text
      final stringFormat = sf.PdfStringFormat();
      stringFormat.alignment = sf.PdfTextAlignment.left;
      stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;

      graphics.drawString(
        newText,
        font,
        brush: brush,
        format: stringFormat,
        bounds: Rect.fromLTWH(
          pdfX,
          pdfY,
          pageSize.width - pdfX,
          100, // Allow multi-line
        ),
      );

      // Save modified PDF
      final modifiedBytes = await document.save();
      await file.writeAsBytes(modifiedBytes);
      document.dispose();

      return true;
    } catch (e) {
      print('Error replacing text: $e');
      return false;
    }
  }

  static sf.PdfFontStyle _getFontStyle(bool isBold, bool isItalic) {
    // Syncfusion PdfFontStyle is an enum, not a flags enum
    // When both bold and italic are needed, we'll prioritize bold
    // For true bold+italic, we'd need to use a different approach
    if (isBold) {
      return sf.PdfFontStyle.bold;
    } else if (isItalic) {
      return sf.PdfFontStyle.italic;
    } else {
      return sf.PdfFontStyle.regular;
    }
  }
  
  /// Check if PDF is a scanned document (image-based, no extractable text)
  static Future<bool> isScannedDocument(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      // Check first few pages for extractable text
      final maxPagesToCheck = document.pages.count < 3 ? document.pages.count : 3;
      final textExtractor = sf.PdfTextExtractor(document);
      
      bool hasText = false;
      for (int i = 0; i < maxPagesToCheck; i++) {
        final extractedText = textExtractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        if (extractedText.trim().isNotEmpty) {
          hasText = true;
          break;
        }
      }

      document.dispose();
      
      // If no text found in first few pages, likely a scanned document
      return !hasText;
    } catch (e) {
      print('Error checking if document is scanned: $e');
      // On error, assume it's not scanned to be safe
      return false;
    }
  }
}
