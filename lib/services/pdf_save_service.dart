import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'mupdf_editor_service.dart';
import '../widgets/pdf_annotation_overlay.dart';

/// Service for saving PDFs with annotations in isolate with progress tracking
class PDFSaveService {
  /// Save PDF with annotations using MuPDF (true PDF content objects)
  static Future<bool> savePDFWithProgress({
    required BuildContext context,
    required String filePath,
    required List<List<AnnotationPoint>> annotations,
    String? successMessage,
  }) async {
    // Show non-blocking progress overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PDFSaveProgressDialog(),
    );

    try {
      // Get PDF page sizes for accurate coordinate conversion
      final file = File(filePath);
      if (!await file.exists()) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF file does not exist'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      final pageCount = document.pages.count;
      final pageSizes = <Size>[];
      
      for (int i = 0; i < pageCount; i++) {
        final page = document.pages[i];
        pageSizes.add(Size(page.size.width, page.size.height));
      }
      document.dispose();

      // Process each annotation and add to PDF using MuPDF
      int successCount = 0;
      int totalCount = 0;
      
      for (var path in annotations) {
        if (path.isEmpty) continue;
        
        final firstPoint = path.first;
        final pageIndex = firstPoint.pageNumber - 1; // Convert to 0-based
        
        if (pageIndex < 0 || pageIndex >= pageSizes.length) {
          print('Invalid page index: $pageIndex');
          continue;
        }
        
        final pageSize = pageSizes[pageIndex];
        totalCount++;
        
        try {
          // Convert normalized coordinates (0-1) to PDF coordinates (points)
          if (firstPoint.toolType == 'pen') {
            // Pen annotation - freehand path
            final pdfPoints = path.map((p) {
              return Offset(
                p.normalizedPoint.dx * pageSize.width,
                p.normalizedPoint.dy * pageSize.height,
              );
            }).toList();
            
            if (pdfPoints.length >= 2) {
              final success = await MuPDFEditorService.addPenAnnotation(
                filePath,
                pageIndex,
                pdfPoints,
                firstPoint.color,
                firstPoint.strokeWidth,
              );
              if (success) successCount++;
            }
          } else if (firstPoint.toolType == 'highlight') {
            // Highlight annotation - filled rectangle
            final pdfPoints = path.map((p) {
              return Offset(
                p.normalizedPoint.dx * pageSize.width,
                p.normalizedPoint.dy * pageSize.height,
              );
            }).toList();
            
            if (pdfPoints.length >= 2) {
              final minX = pdfPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
              final maxX = pdfPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
              final minY = pdfPoints.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
              final maxY = pdfPoints.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
              
              final rect = Rect.fromLTRB(minX, minY, maxX, maxY);
              final success = await MuPDFEditorService.addHighlightAnnotation(
                filePath,
                pageIndex,
                rect,
                firstPoint.color,
                0.4, // Default highlight opacity
              );
              if (success) successCount++;
            }
          } else if (firstPoint.toolType == 'underline') {
            // Underline annotation - line
            final pdfPoints = path.map((p) {
              return Offset(
                p.normalizedPoint.dx * pageSize.width,
                p.normalizedPoint.dy * pageSize.height,
              );
            }).toList();
            
            if (pdfPoints.length >= 2) {
              final minX = pdfPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
              final maxX = pdfPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
              final y = pdfPoints.first.dy;
              
              final success = await MuPDFEditorService.addUnderlineAnnotation(
                filePath,
                pageIndex,
                Offset(minX, y),
                Offset(maxX, y),
                firstPoint.color,
                firstPoint.strokeWidth,
              );
              if (success) successCount++;
            }
          }
          // Note: Eraser is handled by removing annotations, not adding them
        } catch (e) {
          print('Error adding annotation: $e');
        }
      }

      // Save PDF after adding all annotations
      final saveSuccess = await MuPDFEditorService.savePdf(filePath);

      // Close progress dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (saveSuccess && successCount == totalCount) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMessage ?? 'PDF saved with ${successCount} annotation(s)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      } else if (saveSuccess && successCount > 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF saved with ${successCount}/${totalCount} annotations'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return true;
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving PDF annotations. ${successCount}/${totalCount} succeeded.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return false;
      }
    } catch (e) {
      // Close progress dialog
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }
}

/// Non-blocking progress dialog for PDF save operations
class PDFSaveProgressDialog extends StatelessWidget {
  const PDFSaveProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent dismissal
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Saving PDF...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This may take a moment',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

