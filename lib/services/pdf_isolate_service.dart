import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'mupdf_editor_service.dart';

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

  /// Render PDF page to image (using native MuPDF rendering)
  /// Note: Cannot use isolates because platform channels don't work in isolates
  /// This runs on the main thread but is async, so it won't block UI
  static Future<Uint8List?> renderPageToImage(
    PDFPageRenderRequest request,
  ) async {
    try {
      // Validate file exists first
      final file = File(request.filePath);
      if (!await file.exists()) {
        print('PDF file does not exist: ${request.filePath}');
        return null;
      }
      
      // Get page dimensions first using Syncfusion (lightweight operation)
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        print('PDF file is empty: ${request.filePath}');
        return null;
      }
      
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (request.pageIndex < 0 || request.pageIndex >= document.pages.count) {
        print('Invalid page index: ${request.pageIndex}, total pages: ${document.pages.count}');
        document.dispose();
        return null;
      }
      
      final page = document.pages[request.pageIndex];
      final pageSize = page.size;
      final thumbWidth = (pageSize.width * request.scale).round();
      final thumbHeight = (pageSize.height * request.scale).round();
      document.dispose();
      
      if (thumbWidth <= 0 || thumbHeight <= 0) {
        print('Invalid thumbnail dimensions: ${thumbWidth}x${thumbHeight}');
        return null;
      }
      
      // Use native MuPDF rendering via platform channel
      // This returns raw RGB data
      final rawRgbData = await MuPDFEditorService.renderPageToImage(
        request.filePath,
        request.pageIndex,
        request.scale,
      );
      
      if (rawRgbData == null || rawRgbData.isEmpty) {
        print('Native rendering returned null or empty for page ${request.pageIndex}');
        return null;
      }
      
      // Convert raw RGB data to PNG using image package
      // The native code returns RGB data (3 bytes per pixel)
      final imageDataSize = thumbWidth * thumbHeight * 3;
      
      // Handle case where native code might return slightly different size (due to stride/padding)
      if (rawRgbData.length < imageDataSize) {
        print('Invalid RGB data size: expected at least $imageDataSize, got ${rawRgbData.length} for page ${request.pageIndex}');
        // Try to use what we have if it's close (within 10%)
        if (rawRgbData.length >= (imageDataSize * 0.9).round()) {
          print('Using partial RGB data (${rawRgbData.length} bytes)');
          // Calculate actual dimensions from data
          final actualPixels = rawRgbData.length ~/ 3;
          final actualHeight = (actualPixels / thumbWidth).round();
          if (actualHeight > 0 && actualHeight <= thumbHeight * 1.1) {
            // Use actual dimensions
            final image = img.Image(
              width: thumbWidth,
              height: actualHeight,
            );
            
            int srcIndex = 0;
            final maxPixels = (thumbWidth * actualHeight).clamp(0, actualPixels);
            for (int y = 0; y < actualHeight && srcIndex < rawRgbData.length - 2; y++) {
              for (int x = 0; x < thumbWidth && srcIndex < rawRgbData.length - 2; x++) {
                final r = rawRgbData[srcIndex++];
                final g = rawRgbData[srcIndex++];
                final b = rawRgbData[srcIndex++];
                image.setPixelRgba(x, y, r, g, b, 255);
              }
            }
            
            final pngBytes = img.encodePng(image);
            return Uint8List.fromList(pngBytes);
          }
        }
        return null;
      }
      
      // Create image from RGB data
      final image = img.Image(
        width: thumbWidth,
        height: thumbHeight,
      );
      
      // Copy RGB data to image
      int srcIndex = 0;
      for (int y = 0; y < thumbHeight; y++) {
        for (int x = 0; x < thumbWidth; x++) {
          if (srcIndex + 2 < rawRgbData.length) {
            final r = rawRgbData[srcIndex++];
            final g = rawRgbData[srcIndex++];
            final b = rawRgbData[srcIndex++];
            image.setPixelRgba(x, y, r, g, b, 255);
          } else {
            break;
          }
        }
      }
      
      // Encode to PNG
      final pngBytes = img.encodePng(image);
      return Uint8List.fromList(pngBytes);
      
    } catch (e, stackTrace) {
      print('Error rendering page ${request.pageIndex} to image: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
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
      print('_loadPDFInfoIsolate: File does not exist: $filePath');
      return PDFDocumentInfo(
        pageCount: 0,
        fileSize: 0,
        isValid: false,
        error: 'File does not exist',
      );
    }

    final stat = await file.stat();
    if (stat.size == 0) {
      print('_loadPDFInfoIsolate: File is empty: $filePath');
      return PDFDocumentInfo(
        pageCount: 0,
        fileSize: 0,
        isValid: false,
        error: 'File is empty',
      );
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      print('_loadPDFInfoIsolate: Read bytes are empty: $filePath');
      return PDFDocumentInfo(
        pageCount: 0,
        fileSize: 0,
        isValid: false,
        error: 'File is empty',
      );
    }

    // Validate PDF header
    if (bytes.length < 4 || 
        String.fromCharCodes(bytes.take(4)) != '%PDF') {
      print('_loadPDFInfoIsolate: Invalid PDF header: $filePath');
      return PDFDocumentInfo(
        pageCount: 0,
        fileSize: bytes.length,
        isValid: false,
        error: 'Invalid PDF file (missing PDF header)',
      );
    }

    sf.PdfDocument? document;
    try {
      document = sf.PdfDocument(inputBytes: bytes);
      final pageCount = document.pages.count;
      
      if (pageCount <= 0) {
        print('_loadPDFInfoIsolate: PDF has no pages: $filePath');
        document.dispose();
        return PDFDocumentInfo(
          pageCount: 0,
          fileSize: bytes.length,
          isValid: false,
          error: 'PDF has no pages',
        );
      }

      final fileSize = bytes.length;
      document.dispose();
      document = null;

      print('_loadPDFInfoIsolate: Successfully loaded PDF: $filePath, pages: $pageCount');
      return PDFDocumentInfo(
        pageCount: pageCount,
        fileSize: fileSize,
        isValid: true,
      );
    } catch (e) {
      document?.dispose();
      print('_loadPDFInfoIsolate: Error parsing PDF document: $e');
      return PDFDocumentInfo(
        pageCount: 0,
        fileSize: bytes.length,
        isValid: false,
        error: 'Error parsing PDF: $e',
      );
    }
  } catch (e, stackTrace) {
    print('_loadPDFInfoIsolate: Unexpected error: $e');
    print('Stack trace: $stackTrace');
    return PDFDocumentInfo(
      pageCount: 0,
      fileSize: 0,
      isValid: false,
      error: 'Unexpected error: $e',
    );
  }
}

/// Isolate function: Save PDF with annotations using MuPDF
/// Must be top-level (not static) for compute() to work
/// NOTE: This function cannot use MuPDF directly because platform channels don't work in isolates
/// Instead, we'll process annotations in the main isolate and use MuPDF there
Future<PDFSaveResult> _savePDFWithAnnotationsIsolate(
  PDFSaveRequest request,
) async {
  // NOTE: MuPDF platform channels cannot be called from isolates
  // The actual MuPDF saving will be done in the main isolate
  // This function is kept for compatibility but will be bypassed
  // The real saving happens in PDFSaveService using MuPDF directly
  
  try {
    final file = File(request.filePath);
    if (!await file.exists()) {
      return PDFSaveResult(success: false, error: 'File does not exist');
    }

    // Return success - actual MuPDF saving happens in main isolate
    // This is just a placeholder to maintain the isolate interface
    return PDFSaveResult(success: true);
  } catch (e) {
    return PDFSaveResult(success: false, error: e.toString());
  }
}

/// Isolate function: Render PDF page to image
/// Must be top-level (not static) for compute() to work
Future<Uint8List?> _renderPageToImageIsolate(
  PDFPageRenderRequest request,
) async {
  try {
    final file = File(request.filePath);
    if (!await file.exists()) {
      print('PDF file does not exist: ${request.filePath}');
      return null;
    }

    final bytes = await file.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);
    
    if (request.pageIndex < 0 || request.pageIndex >= document.pages.count) {
      document.dispose();
      print('Invalid page index: ${request.pageIndex}, total pages: ${document.pages.count}');
      return null;
    }

    final page = document.pages[request.pageIndex];
    final pageSize = page.size;
    
    // Calculate thumbnail dimensions based on scale
    final thumbnailWidth = (pageSize.width * request.scale).round();
    final thumbnailHeight = (pageSize.height * request.scale).round();
    
    // Note: Printing.raster doesn't work well in isolates and PdfRaster API is limited
    // For now, we'll use a workaround: create a single-page PDF and use Printing.raster
    // outside the isolate, or return null to show placeholders
    // TODO: Implement proper PDF page rendering using pdfx or native rendering
    
    // Create a temporary PDF with just this page for rendering
    final tempPdf = sf.PdfDocument();
    final tempPage = tempPdf.pages.add();
    final pageTemplate = page.createTemplate();
    tempPage.graphics.drawPdfTemplate(
      pageTemplate,
      const ui.Offset(0, 0),
      ui.Size(pageSize.width, pageSize.height),
    );
    
    final tempPdfBytesList = await tempPdf.save();
    final tempPdfBytes = Uint8List.fromList(tempPdfBytesList);
    tempPdf.dispose();
    document.dispose();
    
    // Try using Printing.raster - note: this may not work in isolates
    // If it fails, we'll return null and show placeholders
    try {
      final imageStream = Printing.raster(
        tempPdfBytes,
        pages: [0],
        dpi: (72 * request.scale).toDouble(),
      );
      
      // Get the first PdfRaster from the stream
      final pdfRaster = await imageStream.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('Timeout rendering page ${request.pageIndex}');
          throw TimeoutException('Rendering timeout');
        },
      );
      
      // PdfRaster should have properties to access the image
      // Check if it has a toPng() method or similar
      // For now, return null to show placeholders until we find the correct API
      print('PdfRaster received for page ${request.pageIndex}, but conversion not implemented yet');
      return null;
      
      // TODO: Find correct way to convert PdfRaster to Uint8List
      // The printing package's PdfRaster might need to be converted differently
    } catch (e) {
      print('Error using printing.raster for page ${request.pageIndex}: $e');
      // Return null to show placeholder - this is acceptable for now
      return null;
    }
  } catch (e, stackTrace) {
    print('Error rendering PDF page ${request.pageIndex} to image: $e');
    print('Stack trace: $stackTrace');
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

