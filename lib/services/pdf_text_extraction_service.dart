import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:flutter/material.dart';

/// Service for extracting text from PDFs and generating new PDFs from edited text
class PDFTextExtractionService {
  /// Extract all text content from a PDF document
  /// 
  /// Uses PdfTextExtractor to pull all text from an existing PDF.
  /// Returns an empty string if extraction fails.
  /// 
  /// [pdfBytes] - The PDF file as a Uint8List
  /// Returns the extracted text as a String
  static Future<String> extractPdfContent(Uint8List pdfBytes) async {
    try {
      // Load PDF document from bytes
      final document = sf.PdfDocument(inputBytes: pdfBytes);
      
      // Create text extractor
      final textExtractor = sf.PdfTextExtractor(document);
      
      // Extract text from all pages
      final extractedText = textExtractor.extractText();
      
      // Dispose document to free resources
      document.dispose();
      
      return extractedText;
    } catch (e) {
      print('Error extracting PDF content: $e');
      // Return empty string on error
      return '';
    }
  }

  /// Generate a new PDF document from edited text
  /// 
  /// Takes the modified text string and renders it into a new PdfDocument.
  /// Uses manual text wrapping to ensure text wraps correctly within
  /// page margins (standard A4 size).
  /// 
  /// [newText] - The edited text content
  /// Returns the generated PDF as Uint8List, or null on error
  static Future<Uint8List?> generateEditedPdf(String newText) async {
    try {
      // Create a new PDF document
      final document = sf.PdfDocument();
      
      // Standard A4 page size (595 x 842 points at 72 DPI)
      const double pageWidth = 595.0;
      const double pageHeight = 842.0;
      
      // Page margins (standard margins: 1 inch = 72 points)
      const double marginLeft = 72.0;
      const double marginRight = 72.0;
      const double marginTop = 72.0;
      const double marginBottom = 72.0;
      
      // Calculate available text area
      final double textAreaWidth = pageWidth - marginLeft - marginRight;
      final double textAreaHeight = pageHeight - marginTop - marginBottom;
      
      // Create font (PdfStandardFont with Helvetica, size 12)
      final font = sf.PdfStandardFont(
        sf.PdfFontFamily.helvetica,
        12,
      );
      
      // Create text brush (black)
      final brush = sf.PdfSolidBrush(sf.PdfColor(0, 0, 0));
      
      // Create string format for text wrapping
      final stringFormat = sf.PdfStringFormat();
      stringFormat.alignment = sf.PdfTextAlignment.left;
      stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
      stringFormat.wordWrap = sf.PdfWordWrapType.word;
      
      // Manual text wrapping and pagination
      final lines = _wrapText(newText, font, textAreaWidth);
      double currentY = marginTop;
      sf.PdfPage? currentPage;
      
      // Line height (approximate: font size * 1.4 for spacing)
      const double lineHeight = 12.0 * 1.4;
      
      for (final line in lines) {
        // Create new page if needed
        if (currentPage == null || currentY + lineHeight > pageHeight - marginBottom) {
          currentPage = document.pages.add();
          // Note: Page size is set automatically to A4 by default
          currentY = marginTop;
        }
        
        // Draw the line
        final graphics = currentPage!.graphics;
        graphics.drawString(
          line,
          font,
          brush: brush,
          format: stringFormat,
          bounds: Rect.fromLTWH(
            marginLeft,
            currentY,
            textAreaWidth,
            lineHeight,
          ),
        );
        
        // Move to next line
        currentY += lineHeight;
      }
      
      // Ensure at least one page exists
      if (document.pages.count == 0) {
        document.pages.add();
      }
      
      // Save the document to bytes (using async save method)
      final pdfBytesList = await document.save();
      
      // Dispose document to free resources
      document.dispose();
      
      // Convert List<int> to Uint8List
      return Uint8List.fromList(pdfBytesList);
    } catch (e) {
      print('Error generating edited PDF: $e');
      return null;
    }
  }
  
  /// Helper method to wrap text into lines that fit within the given width
  /// Uses approximate character width calculation
  static List<String> _wrapText(String text, sf.PdfFont font, double maxWidth) {
    final lines = <String>[];
    final paragraphs = text.split('\n');
    
    // Approximate character width: font size * 0.6 (average for Helvetica)
    final charWidth = font.size * 0.6;
    final maxCharsPerLine = (maxWidth / charWidth).floor();
    
    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty) {
        lines.add('');
        continue;
      }
      
      final words = paragraph.split(' ');
      String currentLine = '';
      
      for (final word in words) {
        final testLine = currentLine.isEmpty ? word : '$currentLine $word';
        
        // Check if line fits (approximate)
        if (testLine.length <= maxCharsPerLine || currentLine.isEmpty) {
          currentLine = testLine;
        } else {
          // Current line is full, start a new one
          if (currentLine.isNotEmpty) {
            lines.add(currentLine);
          }
          // If word is too long, split it
          if (word.length > maxCharsPerLine) {
            // Split long word
            int start = 0;
            while (start < word.length) {
              final end = (start + maxCharsPerLine).clamp(0, word.length);
              lines.add(word.substring(start, end));
              start = end;
            }
            currentLine = '';
          } else {
            currentLine = word;
          }
        }
      }
      
      // Add the last line of the paragraph
      if (currentLine.isNotEmpty) {
        lines.add(currentLine);
      }
    }
    
    return lines.isEmpty ? [''] : lines;
  }
}

