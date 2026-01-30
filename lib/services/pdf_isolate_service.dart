import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Service for running heavy PDF operations in isolates to prevent ANR
/// All PDF parsing, rendering, and saving operations run off the main thread
class PDFIsolateService {
  /// Load PDF document in isolate and return basic info
  static Future<PDFDocumentInfo> loadPDFInfo(String filePath) async {
    return await compute(_loadPDFInfoIsolate, filePath);
  }

  /// Save PDF with annotations in isolate
  static Future<PDFSaveResult> savePDFWithAnnotations(
    PDFSaveRequest request,
  ) async {
    return await compute(_savePDFWithAnnotationsIsolate, request);
  }

  /// Render PDF page to image in isolate (for caching)
  static Future<Uint8List?> renderPageToImage(
    PDFPageRenderRequest request,
  ) async {
    return await compute(_renderPageToImageIsolate, request);
  }

  /// Parse PDF document in isolate
  static Future<PDFDocumentData> parsePDF(String filePath) async {
    return await compute(_parsePDFIsolate, filePath);
  }

  /// Split PDF in isolate - CRITICAL: Prevents ANR
  static Future<List<String>> splitPDF(String pdfPath) async {
    return await compute(_splitPDFIsolate, pdfPath);
  }

  /// Merge PDFs in isolate - CRITICAL: Prevents ANR
  static Future<String?> mergePDFs(List<String> pdfPaths) async {
    return await compute(_mergePDFsIsolate, pdfPaths);
  }

  /// Compress PDF in isolate - CRITICAL: Prevents ANR
  static Future<String?> compressPDF(String pdfPath) async {
    return await compute(_compressPDFIsolate, pdfPath);
  }
}

/// Isolate function: Load PDF info
static Future<PDFDocumentInfo> _loadPDFInfoIsolate(String filePath) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      return PDFDocumentInfo(
        pageCount: 0,
        fileSize: 0,
        isValid: false,
        error: 'File does not exist',
      );
    }

    final bytes = await file.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);
    
    final pageCount = document.pages.count;
    final fileSize = bytes.length;
    
    document.dispose();
    
    return PDFDocumentInfo(
      pageCount: pageCount,
      fileSize: fileSize,
      isValid: true,
    );
  } catch (e) {
    return PDFDocumentInfo(
      pageCount: 0,
      fileSize: 0,
      isValid: false,
      error: e.toString(),
    );
  }
}

/// Isolate function: Save PDF with annotations
static Future<PDFSaveResult> _savePDFWithAnnotationsIsolate(
  PDFSaveRequest request,
) async {
  try {
    final file = File(request.filePath);
    if (!await file.exists()) {
      return PDFSaveResult(success: false, error: 'File does not exist');
    }

    final bytes = await file.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);

    // Apply annotations to PDF pages
    for (var annotation in request.annotations) {
      if (annotation.pageIndex >= 0 && 
          annotation.pageIndex < document.pages.count) {
        final page = document.pages[annotation.pageIndex];
        final graphics = page.graphics;

        // Draw annotation based on type
        if (annotation.type == 'pen' || annotation.type == 'highlight') {
          final brush = sf.PdfSolidBrush(sf.PdfColor(
            annotation.color.red,
            annotation.color.green,
            annotation.color.blue,
            annotation.color.alpha,
          ));

          if (annotation.points.length >= 2) {
            final path = sf.PdfPath();
            path.moveTo(
              annotation.points[0].dx,
              annotation.points[0].dy,
            );
            
            for (int i = 1; i < annotation.points.length; i++) {
              path.lineTo(
                annotation.points[i].dx,
                annotation.points[i].dy,
              );
            }

            if (annotation.type == 'highlight') {
              // Draw filled rectangle for highlight
              final minX = annotation.points.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
              final maxX = annotation.points.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
              final minY = annotation.points.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
              final maxY = annotation.points.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
              
              graphics.drawRectangle(
                brush: brush,
                bounds: sf.Rect.fromLTWH(
                  minX,
                  minY,
                  maxX - minX,
                  maxY - minY,
                ),
              );
            } else {
              // Draw pen stroke
              final pen = sf.PdfPen(brush, width: annotation.strokeWidth);
              graphics.drawPath(pen, path);
            }
          }
        } else if (annotation.type == 'underline') {
          if (annotation.points.length >= 2) {
            final minX = annotation.points.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
            final maxX = annotation.points.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
            final y = annotation.points.first.dy;
            
            final pen = sf.PdfPen(
              sf.PdfSolidBrush(sf.PdfColor(
                annotation.color.red,
                annotation.color.green,
                annotation.color.blue,
              )),
              width: annotation.strokeWidth,
            );
            
            graphics.drawLine(pen, minX, y, maxX, y);
          }
        }
      }
    }

    // Save modified PDF
    final modifiedBytes = document.save();
    document.dispose();

    // Write to file
    await file.writeAsBytes(modifiedBytes);

    return PDFSaveResult(success: true);
  } catch (e) {
    return PDFSaveResult(success: false, error: e.toString());
  }
}

/// Isolate function: Render PDF page to image
/// Note: This is a placeholder - actual implementation depends on Syncfusion API
static Future<Uint8List?> _renderPageToImageIsolate(
  PDFPageRenderRequest request,
) async {
  try {
    final file = File(request.filePath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);

    if (request.pageIndex >= document.pages.count) {
      document.dispose();
      return null;
    }

    // TODO: Implement actual page rendering to image
    // Syncfusion PDF viewer handles rendering internally
    // For caching, consider using the viewer's rendered output
    // This function is a placeholder for future implementation
    
    document.dispose();
    return null;
  } catch (e) {
    return null;
  }
}

/// Isolate function: Parse PDF document
static Future<PDFDocumentData> _parsePDFIsolate(String filePath) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      return PDFDocumentData(isValid: false, error: 'File does not exist');
    }

    final bytes = await file.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);
    
    final pageCount = document.pages.count;
    final pages = <PDFPageData>[];
    
    for (int i = 0; i < pageCount; i++) {
      final page = document.pages[i];
      pages.add(PDFPageData(
        index: i,
        width: page.size.width,
        height: page.size.height,
      ));
    }
    
    document.dispose();
    
    return PDFDocumentData(
      isValid: true,
      pageCount: pageCount,
      pages: pages,
    );
  } catch (e) {
    return PDFDocumentData(isValid: false, error: e.toString());
  }
}

// Data classes for isolate communication

class PDFDocumentInfo {
  final int pageCount;
  final int fileSize;
  final bool isValid;
  final String? error;

  PDFDocumentInfo({
    required this.pageCount,
    required this.fileSize,
    required this.isValid,
    this.error,
  });
}

class PDFSaveRequest {
  final String filePath;
  final List<PDFAnnotationData> annotations;

  PDFSaveRequest({
    required this.filePath,
    required this.annotations,
  });
}

class PDFAnnotationData {
  final int pageIndex;
  final String type; // 'pen', 'highlight', 'underline'
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  PDFAnnotationData({
    required this.pageIndex,
    required this.type,
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

class PDFSaveResult {
  final bool success;
  final String? error;

  PDFSaveResult({
    required this.success,
    this.error,
  });
}

class PDFPageRenderRequest {
  final String filePath;
  final int pageIndex;
  final double scale;

  PDFPageRenderRequest({
    required this.filePath,
    required this.pageIndex,
    this.scale = 1.0,
  });
}

class PDFDocumentData {
  final bool isValid;
  final int? pageCount;
  final List<PDFPageData>? pages;
  final String? error;

  PDFDocumentData({
    required this.isValid,
    this.pageCount,
    this.pages,
    this.error,
  });
}

class PDFPageData {
  final int index;
  final double width;
  final double height;

  PDFPageData({
    required this.index,
    required this.width,
    required this.height,
  });
}

/// Isolate function: Split PDF
static Future<List<String>> _splitPDFIsolate(String pdfPath) async {
  final List<String> splitFiles = [];
  sf.PdfDocument? pdf;
  
  try {
    final file = File(pdfPath);
    if (!await file.exists()) return splitFiles;

    final bytes = await file.readAsBytes();
    pdf = sf.PdfDocument(inputBytes: bytes);
    final totalPages = pdf.pages.count;
    final baseName = path.basenameWithoutExtension(pdfPath);

    for (int i = 0; i < totalPages; i++) {
      try {
        final singlePagePdf = sf.PdfDocument();
        final sourcePage = pdf.pages[i];
        final newPage = singlePagePdf.pages.add();
        
        final template = sourcePage.createTemplate();
        final pageSize = sourcePage.size;
        newPage.graphics.drawPdfTemplate(
          template,
          const ui.Offset(0, 0),
          ui.Size(pageSize.width, pageSize.height),
        );

        final fileName = '${baseName}_page_${i + 1}.pdf';
        final splitBytes = await singlePagePdf.save();
        singlePagePdf.dispose();

        // Save to app storage directory
        final directory = await getApplicationDocumentsDirectory();
        final pdfDirectory = Directory('${directory.path}/PDFs');
        if (!await pdfDirectory.exists()) {
          await pdfDirectory.create(recursive: true);
        }

        var targetPath = path.join(pdfDirectory.path, fileName);
        var targetFile = File(targetPath);
        int counter = 1;
        
        while (await targetFile.exists()) {
          final nameWithoutExt = path.basenameWithoutExtension(fileName);
          final ext = path.extension(fileName);
          final newFileName = '${nameWithoutExt}_$counter$ext';
          targetPath = path.join(pdfDirectory.path, newFileName);
          targetFile = File(targetPath);
          counter++;
        }

        await targetFile.writeAsBytes(splitBytes);
        splitFiles.add(targetPath);
      } catch (e) {
        print('Error splitting page ${i + 1}: $e');
        continue;
      }
    }

    pdf?.dispose();
    return splitFiles;
  } catch (e) {
    pdf?.dispose();
    print('Error splitting PDF: $e');
    return splitFiles;
  }
}

/// Isolate function: Merge PDFs
static Future<String?> _mergePDFsIsolate(List<String> pdfPaths) async {
  sf.PdfDocument? mergedPdf;
  final List<sf.PdfDocument> pdfsToDispose = [];
  
  try {
    if (pdfPaths.isEmpty) return null;

    mergedPdf = sf.PdfDocument();

    for (var pdfPath in pdfPaths) {
      final file = File(pdfPath);
      if (!await file.exists()) continue;

      final bytes = await file.readAsBytes();
      final pdf = sf.PdfDocument(inputBytes: bytes);
      pdfsToDispose.add(pdf);

      for (int i = 0; i < pdf.pages.count; i++) {
        final sourcePage = pdf.pages[i];
        final newPage = mergedPdf.pages.add();
        final template = sourcePage.createTemplate();
        final pageSize = sourcePage.size;
        newPage.graphics.drawPdfTemplate(
          template,
          const ui.Offset(0, 0),
          ui.Size(pageSize.width, pageSize.height),
        );
      }
    }

    if (mergedPdf.pages.count == 0) {
      mergedPdf.dispose();
      for (var pdf in pdfsToDispose) {
        pdf.dispose();
      }
      return null;
    }

    final mergedBytes = await mergedPdf.save();
    
    // Save to app storage
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory('${directory.path}/PDFs');
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }

    final fileName = 'Merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
    var targetPath = path.join(pdfDirectory.path, fileName);
    var targetFile = File(targetPath);
    int counter = 1;
    
    while (await targetFile.exists()) {
      final nameWithoutExt = path.basenameWithoutExtension(fileName);
      final ext = path.extension(fileName);
      final newFileName = '${nameWithoutExt}_$counter$ext';
      targetPath = path.join(pdfDirectory.path, newFileName);
      targetFile = File(targetPath);
      counter++;
    }

    await targetFile.writeAsBytes(mergedBytes);
    
    mergedPdf.dispose();
    for (var pdf in pdfsToDispose) {
      pdf.dispose();
    }

    return targetPath;
  } catch (e) {
    mergedPdf?.dispose();
    for (var pdf in pdfsToDispose) {
      pdf.dispose();
    }
    print('Error merging PDFs: $e');
    return null;
  }
}

/// Isolate function: Compress PDF
static Future<String?> _compressPDFIsolate(String pdfPath) async {
  sf.PdfDocument? pdf;
  sf.PdfDocument? compressedPdf;
  
  try {
    final file = File(pdfPath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    pdf = sf.PdfDocument(inputBytes: bytes);
    compressedPdf = sf.PdfDocument();

    for (int i = 0; i < pdf.pages.count; i++) {
      try {
        final sourcePage = pdf.pages[i];
        final newPage = compressedPdf.pages.add();
        final template = sourcePage.createTemplate();
        final pageSize = sourcePage.size;
        newPage.graphics.drawPdfTemplate(
          template,
          const ui.Offset(0, 0),
          ui.Size(pageSize.width, pageSize.height),
        );
      } catch (e) {
        print('Error processing page $i: $e');
        continue;
      }
    }

    if (compressedPdf.pages.count == 0) {
      pdf.dispose();
      compressedPdf.dispose();
      return null;
    }

    final compressedBytes = await compressedPdf.save();
    
    // Save to app storage
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory('${directory.path}/PDFs');
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }

    final baseName = path.basenameWithoutExtension(pdfPath);
    final fileName = '${baseName}_compressed.pdf';
    var targetPath = path.join(pdfDirectory.path, fileName);
    var targetFile = File(targetPath);
    int counter = 1;
    
    while (await targetFile.exists()) {
      final nameWithoutExt = path.basenameWithoutExtension(fileName);
      final ext = path.extension(fileName);
      final newFileName = '${nameWithoutExt}_$counter$ext';
      targetPath = path.join(pdfDirectory.path, newFileName);
      targetFile = File(targetPath);
      counter++;
    }

    await targetFile.writeAsBytes(compressedBytes);
    
    pdf.dispose();
    compressedPdf.dispose();

    return targetPath;
  } catch (e) {
    pdf?.dispose();
    compressedPdf?.dispose();
    print('Error compressing PDF: $e');
    return null;
  }
}

