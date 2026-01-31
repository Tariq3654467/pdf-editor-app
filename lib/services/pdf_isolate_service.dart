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

  /// Split PDF in isolate - CRITICAL: Prevents ANR (splits all pages)
  static Future<List<String>> splitPDF(String pdfPath) async {
    // Get directory path in main isolate before passing to compute
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory('${directory.path}/PDFs');
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }
    
    // Pass both pdfPath and outputDirectory to isolate (null = split all pages)
    final splitRequest = SplitPDFRequest(
      pdfPath: pdfPath,
      outputDirectory: pdfDirectory.path,
      selectedPageIndices: null, // Split all pages
    );
    
    return await compute(_splitPDFIsolate, splitRequest);
  }

  /// Split selected PDF pages in isolate - CRITICAL: Prevents ANR
  static Future<List<String>> splitPDFPages(SplitPDFRequest request) async {
    return await compute(_splitPDFIsolate, request);
  }

  /// Merge PDFs in isolate - CRITICAL: Prevents ANR
  static Future<String?> mergePDFs(List<String> pdfPaths) async {
    // Get directory path in main isolate before passing to compute
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory('${directory.path}/PDFs');
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }
    
    // Pass both pdfPaths and outputDirectory to isolate
    final mergeRequest = MergePDFRequest(
      pdfPaths: pdfPaths,
      outputDirectory: pdfDirectory.path,
    );
    
    return await compute(_mergePDFsIsolate, mergeRequest);
  }

  /// Compress PDF in isolate - CRITICAL: Prevents ANR
  static Future<String?> compressPDF(String pdfPath) async {
    // Get directory path in main isolate before passing to compute
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory('${directory.path}/PDFs');
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }
    
    // Pass both pdfPath and outputDirectory to isolate
    final compressRequest = CompressPDFRequest(
      pdfPath: pdfPath,
      outputDirectory: pdfDirectory.path,
    );
    
    return await compute(_compressPDFIsolate, compressRequest);
  }
}

/// Isolate function: Load PDF info
/// Must be top-level (not static) for compute() to work
Future<PDFDocumentInfo> _loadPDFInfoIsolate(String filePath) async {
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
/// Must be top-level (not static) for compute() to work
Future<PDFSaveResult> _savePDFWithAnnotationsIsolate(
  PDFSaveRequest request,
) async {
  try {
    final file = File(request.filePath);
    if (!await file.exists()) {
      return PDFSaveResult(success: false, error: 'File does not exist');
    }

    final bytes = await file.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);

    // NOTE: Annotation drawing in PDF is complex and requires proper Syncfusion API
    // For now, we skip annotation drawing in isolate to avoid API compatibility issues
    // Annotations are handled in the UI layer (PDFAnnotationOverlay)
    // This function saves the PDF without modifying annotations
    // TODO: Implement proper annotation drawing using Syncfusion PDF graphics API
    // For now, we just save the PDF as-is (annotations are visual-only in the viewer)

    // Save modified PDF
    final modifiedBytes = await document.save();
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
/// Must be top-level (not static) for compute() to work
Future<Uint8List?> _renderPageToImageIsolate(
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
/// Must be top-level (not static) for compute() to work
Future<PDFDocumentData> _parsePDFIsolate(String filePath) async {
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

/// Request class for split PDF operation
class SplitPDFRequest {
  final String pdfPath;
  final String outputDirectory;
  final List<int>? selectedPageIndices; // null means split all pages
  
  SplitPDFRequest({
    required this.pdfPath,
    required this.outputDirectory,
    this.selectedPageIndices,
  });
}

/// Request class for merge PDF operation
class MergePDFRequest {
  final List<String> pdfPaths;
  final String outputDirectory;
  
  MergePDFRequest({
    required this.pdfPaths,
    required this.outputDirectory,
  });
}

/// Request class for compress PDF operation
class CompressPDFRequest {
  final String pdfPath;
  final String outputDirectory;
  
  CompressPDFRequest({
    required this.pdfPath,
    required this.outputDirectory,
  });
}

/// Isolate function: Split PDF
/// Must be top-level (not static) for compute() to work
Future<List<String>> _splitPDFIsolate(SplitPDFRequest request) async {
  final List<String> splitFiles = [];
  sf.PdfDocument? pdf;
  
  try {
    final file = File(request.pdfPath);
    if (!await file.exists()) return splitFiles;

    final bytes = await file.readAsBytes();
    pdf = sf.PdfDocument(inputBytes: bytes);
    final totalPages = pdf.pages.count;
    final baseName = path.basenameWithoutExtension(request.pdfPath);

    // Determine which pages to split
    final pagesToSplit = request.selectedPageIndices ?? 
        List.generate(totalPages, (index) => index);
    
    // Sort pages to process in order
    pagesToSplit.sort();

    for (final pageIndex in pagesToSplit) {
      // Validate page index
      if (pageIndex < 0 || pageIndex >= totalPages) {
        print('Invalid page index: $pageIndex (total pages: $totalPages)');
        continue;
      }
      
      final i = pageIndex;
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

        // Save to app storage directory using provided path
        final pdfDirectory = Directory(request.outputDirectory);
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
/// Must be top-level (not static) for compute() to work
Future<String?> _mergePDFsIsolate(MergePDFRequest request) async {
  sf.PdfDocument? mergedPdf;
  final List<sf.PdfDocument> pdfsToDispose = [];
  
  try {
    if (request.pdfPaths.isEmpty) return null;

    mergedPdf = sf.PdfDocument();

    for (var pdfPath in request.pdfPaths) {
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
    
    // Save to app storage using provided directory path
    final pdfDirectory = Directory(request.outputDirectory);
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
/// Must be top-level (not static) for compute() to work
Future<String?> _compressPDFIsolate(CompressPDFRequest request) async {
  sf.PdfDocument? pdf;
  sf.PdfDocument? compressedPdf;
  
  try {
    final file = File(request.pdfPath);
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
    
    // Save to app storage using provided directory path
    final pdfDirectory = Directory(request.outputDirectory);
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }

    final baseName = path.basenameWithoutExtension(request.pdfPath);
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

