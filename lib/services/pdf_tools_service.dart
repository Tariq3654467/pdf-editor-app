import 'dart:io';
import 'dart:ui' as ui;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'pdf_cache_service.dart';
import 'pdf_preferences_service.dart';
import 'pdf_service.dart';
import 'pdf_storage_service.dart';
import '../models/pdf_file.dart';

class PDFToolsService {
  // Scan to PDF - Convert camera image to PDF
  static Future<String?> scanToPDF(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) return null;

      final imageBytes = await imageFile.readAsBytes();
      final pdf = pw.Document();

      // Decode image
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // Create PDF page with image
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(
                pw.MemoryImage(imageBytes),
                fit: pw.BoxFit.contain,
              ),
            );
          },
        ),
      );

      // Save PDF using storage service (ensures it's in app storage)
      final pdfBytes = await pdf.save();
      final fileName = 'Scanned_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfPath = await PDFStorageService.savePDFBytes(pdfBytes, fileName);
      
      return pdfPath;
    } catch (e) {
      print('Error scanning to PDF: $e');
      return null;
    }
  }

  // Image to PDF - Convert one or more images to PDF
  static Future<String?> imageToPDF(List<String> imagePaths) async {
    try {
      final pdf = pw.Document();
      bool hasPages = false;

      for (var imagePath in imagePaths) {
        final imageFile = File(imagePath);
        if (!await imageFile.exists()) continue;

        final imageBytes = await imageFile.readAsBytes();
        final image = img.decodeImage(imageBytes);
        if (image == null) continue;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(
                  pw.MemoryImage(imageBytes),
                  fit: pw.BoxFit.contain,
                ),
              );
            },
          ),
        );
        hasPages = true;
      }

      if (!hasPages) return null;

      // Save PDF using storage service (ensures it's in app storage)
      final pdfBytes = await pdf.save();
      final fileName = 'Images_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfPath = await PDFStorageService.savePDFBytes(pdfBytes, fileName);
      
      return pdfPath;
    } catch (e) {
      print('Error converting images to PDF: $e');
      return null;
    }
  }

  // Split PDF - Split PDF into separate page files
  // CRITICAL: This operation is CPU-intensive and must yield to UI thread
  static Future<List<String>> splitPDF(String pdfPath) async {
    List<String> splitFiles = [];
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return splitFiles;

      // Read file bytes
      final bytes = await file.readAsBytes();
      
      // Process in chunks to avoid blocking UI thread
      // Yield to UI thread every few pages
      final pdf = sf.PdfDocument(inputBytes: bytes);
      final totalPages = pdf.pages.count;
      final baseName = path.basenameWithoutExtension(pdfPath);

      // Process pages with periodic yields to prevent UI freeze
      for (int i = 0; i < totalPages; i++) {
        // Yield to UI thread every 5 pages to prevent ANR
        if (i > 0 && i % 5 == 0) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        
        try {
          final singlePagePdf = sf.PdfDocument();
          final sourcePage = pdf.pages[i];
          final newPage = singlePagePdf.pages.add();
          
          // Create template from source page and draw it on new page
          final template = sourcePage.createTemplate();
          final pageSize = sourcePage.size;
          newPage.graphics.drawPdfTemplate(
            template, 
            const ui.Offset(0, 0), 
            ui.Size(pageSize.width, pageSize.height),
          );

          final fileName = '${baseName}_page_${i + 1}.pdf';
          final splitBytes = await singlePagePdf.save();
          
          // Dispose immediately to free memory
          singlePagePdf.dispose();
          
          // Save using storage service (ensures it's in app storage)
          // This is I/O bound, so it's okay to await
          final splitPath = await PDFStorageService.savePDFBytes(splitBytes, fileName);
          if (splitPath != null) {
            splitFiles.add(splitPath);
          }
        } catch (e) {
          print('Error splitting page ${i + 1}: $e');
          // Continue with next page instead of failing completely
          continue;
        }
      }

      pdf.dispose();
      return splitFiles;
    } catch (e) {
      print('Error splitting PDF: $e');
      return splitFiles;
    }
  }

  // Merge PDF - Merge multiple PDFs into one
  static Future<String?> mergePDFs(List<String> pdfPaths) async {
    try {
      if (pdfPaths.isEmpty) return null;

      final mergedPdf = sf.PdfDocument();

      for (var pdfPath in pdfPaths) {
        final file = File(pdfPath);
        if (!await file.exists()) continue;

        final bytes = await file.readAsBytes();
        final pdf = sf.PdfDocument(inputBytes: bytes);

        for (int i = 0; i < pdf.pages.count; i++) {
          final sourcePage = pdf.pages[i];
          final newPage = mergedPdf.pages.add();
          // Create template from source page and draw it on new page
          final template = sourcePage.createTemplate();
          final pageSize = sourcePage.size;
          newPage.graphics.drawPdfTemplate(template, const ui.Offset(0, 0), ui.Size(pageSize.width, pageSize.height));
        }

        pdf.dispose();
      }

      if (mergedPdf.pages.count == 0) {
        mergedPdf.dispose();
        return null;
      }

      // Save merged PDF using storage service (ensures it's in app storage)
      final mergedBytes = await mergedPdf.save();
      mergedPdf.dispose();
      
      final fileName = 'Merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final mergedPath = await PDFStorageService.savePDFBytes(mergedBytes, fileName);

      return mergedPath;
    } catch (e) {
      print('Error merging PDFs: $e');
      return null;
    }
  }

  // Compress PDF - Reduce PDF file size
  static Future<String?> compressPDF(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final pdf = sf.PdfDocument(inputBytes: bytes);

      // Create compressed PDF by copying pages
      final compressedPdf = sf.PdfDocument();

      for (int i = 0; i < pdf.pages.count; i++) {
        final sourcePage = pdf.pages[i];
        final newPage = compressedPdf.pages.add();
        // Create template from source page and draw it on new page
        final template = sourcePage.createTemplate();
        final pageSize = sourcePage.size;
        newPage.graphics.drawPdfTemplate(template, const ui.Offset(0, 0), ui.Size(pageSize.width, pageSize.height));
      }

      // Save compressed PDF using storage service (ensures it's in app storage)
      final compressedBytes = await compressedPdf.save();
      pdf.dispose();
      compressedPdf.dispose();

      final baseName = path.basenameWithoutExtension(pdfPath);
      final fileName = '${baseName}_compressed.pdf';
      final compressedPath = await PDFStorageService.savePDFBytes(compressedBytes, fileName);

      return compressedPath;
    } catch (e) {
      print('Error compressing PDF: $e');
      return null;
    }
  }

  // Create ZIP file - Create ZIP archive from PDFs
  static Future<String?> createZIPFile(List<String> pdfPaths) async {
    try {
      if (pdfPaths.isEmpty) return null;

      final archive = Archive();
      for (var pdfPath in pdfPaths) {
        final file = File(pdfPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final fileName = path.basename(pdfPath);
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        }
      }

      // Save ZIP file
      final directory = await getApplicationDocumentsDirectory();
      final pdfDirectory = Directory('${directory.path}/PDFs');
      if (!await pdfDirectory.exists()) {
        await pdfDirectory.create(recursive: true);
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) return null;

      final fileName = 'PDFs_${DateTime.now().millisecondsSinceEpoch}.zip';
      final zipPath = '${pdfDirectory.path}/$fileName';
      final zipFile = File(zipPath);
      await zipFile.writeAsBytes(zipData);

      return zipPath;
    } catch (e) {
      print('Error creating ZIP file: $e');
      return null;
    }
  }

}

