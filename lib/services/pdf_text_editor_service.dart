import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:flutter/material.dart';

class PDFTextEditorService {
  // Extract text from a PDF page (simplified - just get all text)
  static Future<String> extractTextFromPage(String pdfPath, int pageIndex) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return '';

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        return '';
      }

      final textExtractor = sf.PdfTextExtractor(document);
      final textCollection = textExtractor.extractText(startPageIndex: pageIndex, endPageIndex: pageIndex);
      
      document.dispose();
      return textCollection;
    } catch (e) {
      print('Error extracting text: $e');
      return '';
    }
  }

  // Find text near a specific point (simplified approach)
  // Since we can't get exact text bounds, we'll extract all text and let user select
  static Future<TextElement?> findTextAtPoint(String pdfPath, int pageIndex, Offset point) async {
    try {
      // For now, return null to always show "add new text" dialog
      // In a full implementation, you'd need to parse PDF text objects with bounds
      // which requires more complex PDF parsing
      return null;
    } catch (e) {
      print('Error finding text at point: $e');
      return null;
    }
  }

  // Edit text in PDF - add text overlay at a specific location
  // Note: True text editing (replacing existing text) requires complex PDF manipulation
  // This implementation adds text as an overlay, which is more practical
  static Future<bool> editTextInPDF(
    String pdfPath,
    int pageIndex,
    String oldText,
    String newText,
    Offset position,
  ) async {
    // For now, just add new text at the position (overlay approach)
    // True text replacement would require removing text objects from PDF structure
    return await addTextToPDF(pdfPath, pageIndex, newText, position);
  }

  // Add new text to PDF at a specific position
  static Future<bool> addTextToPDF(
    String pdfPath,
    int pageIndex,
    String text,
    Offset position,
    {Color? color, double? fontSize}
  ) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        return false;
      }

      final page = document.pages[pageIndex];
      final graphics = page.graphics;
      final pageSize = page.size;
      
      // Convert screen coordinates (top-left origin) to PDF coordinates (bottom-left origin)
      // PDF Y coordinate = page height - screen Y coordinate
      final pdfX = position.dx.clamp(0.0, pageSize.width);
      final pdfY = (pageSize.height - position.dy).clamp(0.0, pageSize.height);
      
      // Add text
      final font = sf.PdfStandardFont(
        sf.PdfFontFamily.helvetica,
        fontSize ?? 12,
      );
      final textColor = color ?? Colors.black;
      final textBrush = sf.PdfSolidBrush(sf.PdfColor(
        textColor.red,
        textColor.green,
        textColor.blue,
      ));
      
      // Use PdfStringFormat for better text rendering
      final stringFormat = sf.PdfStringFormat();
      stringFormat.alignment = sf.PdfTextAlignment.left;
      stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
      
      // Calculate available width for text wrapping
      final availableWidth = pageSize.width - pdfX;
      
      graphics.drawString(
        text,
        font,
        brush: textBrush,
        format: stringFormat,
        bounds: Rect.fromLTWH(
          pdfX,
          pdfY,
          availableWidth > 0 ? availableWidth : pageSize.width, // Use available width
          100, // Allow multi-line text
        ),
      );
      
      // Save the modified PDF
      final modifiedBytes = await document.save();
      await file.writeAsBytes(modifiedBytes);
      
      document.dispose();
      return true;
    } catch (e) {
      print('Error adding text to PDF: $e');
      return false;
    }
  }
}

class TextElement {
  final String text;
  final Rect bounds;
  final int pageIndex;

  TextElement({
    required this.text,
    required this.bounds,
    required this.pageIndex,
  });
}

