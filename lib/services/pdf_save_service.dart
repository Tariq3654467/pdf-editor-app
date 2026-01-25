import 'dart:io';
import 'package:flutter/material.dart';
import 'pdf_isolate_service.dart';
import '../widgets/pdf_annotation_overlay.dart';

/// Service for saving PDFs with annotations in isolate with progress tracking
class PDFSaveService {
  /// Save PDF with annotations showing progress overlay
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
      // Convert annotations to isolate-compatible format
      final annotationData = <PDFAnnotationData>[];
      
      for (var path in annotations) {
        if (path.isEmpty) continue;
        
        final firstPoint = path.first;
        final points = path.map((p) {
          // Convert normalized coordinates to PDF coordinates
          // This is a simplified conversion - actual implementation should
          // account for page size and scaling
          return Offset(
            p.normalizedPoint.dx * 612, // Default page width
            p.normalizedPoint.dy * 792, // Default page height
          );
        }).toList();
        
        annotationData.add(PDFAnnotationData(
          pageIndex: firstPoint.pageNumber - 1, // Convert to 0-based
          type: firstPoint.toolType,
          points: points,
          color: firstPoint.color,
          strokeWidth: firstPoint.strokeWidth,
        ));
      }

      // Save in isolate (non-blocking)
      final result = await PDFIsolateService.savePDFWithAnnotations(
        PDFSaveRequest(
          filePath: filePath,
          annotations: annotationData,
        ),
      );

      // Close progress dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (result.success) {
        if (context.mounted && successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMessage),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving PDF: ${result.error ?? "Unknown error"}'),
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

