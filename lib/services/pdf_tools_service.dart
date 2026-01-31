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
import 'pdf_isolate_service.dart';
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
  // CRITICAL: Uses isolate to prevent ANR with timeout protection
  // Split PDF - Split only selected pages
  static Future<List<String>> splitPDFPages(String pdfPath, List<int> selectedPageIndices) async {
    try {
      // Get directory path in main isolate before passing to compute
      final directory = await getApplicationDocumentsDirectory();
      final pdfDirectory = Directory('${directory.path}/PDFs');
      if (!await pdfDirectory.exists()) {
        await pdfDirectory.create(recursive: true);
      }
      
      // Pass pdfPath, outputDirectory, and selected pages to isolate
      final splitRequest = SplitPDFRequest(
        pdfPath: pdfPath,
        outputDirectory: pdfDirectory.path,
        selectedPageIndices: selectedPageIndices,
      );
      
      // Use isolate service for heavy operation with timeout (5 minutes max)
      final splitFiles = await PDFIsolateService.splitPDFPages(splitRequest)
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () {
              print('PDFToolsService: Split operation timed out after 5 minutes');
              return <String>[];
            },
          )
          .catchError((e, stackTrace) {
            print('PDFToolsService: Error in split isolate: $e');
            print('Stack trace: $stackTrace');
            return <String>[];
          });
      
      // Add to cache after splitting - CRITICAL: Must complete before returning
      for (var filePath in splitFiles) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final stat = await file.stat();
            final pdfFile = PDFFile(
              name: path.basename(filePath),
              date: PDFService.formatDate(stat.modified),
              size: PDFService.formatFileSize(stat.size),
              isFavorite: false,
              filePath: filePath,
              lastAccessed: DateTime.now(),
              folderPath: path.dirname(filePath),
              folderName: 'App Files',
              dateModified: stat.modified,
              fileSizeBytes: stat.size,
            );
            // Synchronously update cache - no async gaps
            await PDFCacheService.addPDFToCache(pdfFile);
            await PDFPreferencesService.setLastAccessed(filePath);
          }
        } catch (e) {
          print('PDFToolsService: Error adding split file to cache: $e');
          // Continue with other files
        }
      }
      
      return splitFiles;
    } catch (e, stackTrace) {
      print('PDFToolsService: Fatal error in splitPDFPages: $e');
      print('Stack trace: $stackTrace');
      return <String>[];
    }
  }

  static Future<List<String>> splitPDF(String pdfPath) async {
    try {
      // Use isolate service for heavy operation with timeout (5 minutes max)
      final splitFiles = await PDFIsolateService.splitPDF(pdfPath)
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () {
              print('PDFToolsService: Split operation timed out after 5 minutes');
              return <String>[];
            },
          )
          .catchError((e, stackTrace) {
            print('PDFToolsService: Error in split isolate: $e');
            print('Stack trace: $stackTrace');
            return <String>[];
          });
      
      // Add to cache after splitting - CRITICAL: Must complete before returning
      for (var filePath in splitFiles) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final stat = await file.stat();
            final pdfFile = PDFFile(
              name: path.basename(filePath),
              date: PDFService.formatDate(stat.modified),
              size: PDFService.formatFileSize(stat.size),
              isFavorite: false,
              filePath: filePath,
              lastAccessed: DateTime.now(),
              folderPath: path.dirname(filePath),
              folderName: 'App Files',
              dateModified: stat.modified,
              fileSizeBytes: stat.size,
            );
            // Synchronously update cache - no async gaps
            await PDFCacheService.addPDFToCache(pdfFile);
            await PDFPreferencesService.setLastAccessed(filePath);
          }
        } catch (e) {
          print('PDFToolsService: Error adding split file to cache: $e');
          // Continue with other files
        }
      }
      
      return splitFiles;
    } catch (e, stackTrace) {
      print('PDFToolsService: Fatal error in splitPDF: $e');
      print('Stack trace: $stackTrace');
      return <String>[];
    }
  }
  
  // OLD IMPLEMENTATION - KEPT FOR REFERENCE BUT NOT USED
  // Split PDF - Split PDF into separate page files
  // CRITICAL: This operation is CPU-intensive and must yield to UI thread
  static Future<List<String>> _splitPDFOld(String pdfPath) async {
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
  // CRITICAL: Uses isolate to prevent ANR with timeout protection
  static Future<String?> mergePDFs(List<String> pdfPaths) async {
    try {
      if (pdfPaths.isEmpty) return null;
      
      // Use isolate service for heavy operation with timeout (5 minutes max)
      final mergedPath = await PDFIsolateService.mergePDFs(pdfPaths)
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () {
              print('PDFToolsService: Merge operation timed out after 5 minutes');
              return null;
            },
          )
          .catchError((e, stackTrace) {
            print('PDFToolsService: Error in merge isolate: $e');
            print('Stack trace: $stackTrace');
            return null;
          });
      
      // Add to cache after merging - CRITICAL: Must complete before returning
      if (mergedPath != null) {
        try {
          final file = File(mergedPath);
          if (await file.exists()) {
            final stat = await file.stat();
            final pdfFile = PDFFile(
              name: path.basename(mergedPath),
              date: PDFService.formatDate(stat.modified),
              size: PDFService.formatFileSize(stat.size),
              isFavorite: false,
              filePath: mergedPath,
              lastAccessed: DateTime.now(),
              folderPath: path.dirname(mergedPath),
              folderName: 'App Files',
              dateModified: stat.modified,
              fileSizeBytes: stat.size,
            );
            // Synchronously update cache - no async gaps
            await PDFCacheService.addPDFToCache(pdfFile);
            await PDFPreferencesService.setLastAccessed(mergedPath);
          } else {
            print('PDFToolsService: Merged file does not exist at: $mergedPath');
            return null;
          }
        } catch (e) {
          print('PDFToolsService: Error adding merged file to cache: $e');
          // Return path anyway - file exists even if cache update failed
        }
      }
      
      return mergedPath;
    } catch (e, stackTrace) {
      print('PDFToolsService: Fatal error in mergePDFs: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  // Compress PDF - Reduce PDF file size
  // CRITICAL: Uses isolate to prevent ANR with timeout protection
  static Future<String?> compressPDF(String pdfPath) async {
    try {
      // Use isolate service for heavy operation with timeout (5 minutes max)
      final compressedPath = await PDFIsolateService.compressPDF(pdfPath)
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () {
              print('PDFToolsService: Compress operation timed out after 5 minutes');
              return null;
            },
          )
          .catchError((e, stackTrace) {
            print('PDFToolsService: Error in compress isolate: $e');
            print('Stack trace: $stackTrace');
            return null;
          });
      
      // Add to cache after compressing - CRITICAL: Must complete before returning
      if (compressedPath != null) {
        try {
          final file = File(compressedPath);
          if (await file.exists()) {
            final stat = await file.stat();
            final pdfFile = PDFFile(
              name: path.basename(compressedPath),
              date: PDFService.formatDate(stat.modified),
              size: PDFService.formatFileSize(stat.size),
              isFavorite: false,
              filePath: compressedPath,
              lastAccessed: DateTime.now(),
              folderPath: path.dirname(compressedPath),
              folderName: 'App Files',
              dateModified: stat.modified,
              fileSizeBytes: stat.size,
            );
            // Synchronously update cache - no async gaps
            await PDFCacheService.addPDFToCache(pdfFile);
            await PDFPreferencesService.setLastAccessed(compressedPath);
          } else {
            print('PDFToolsService: Compressed file does not exist at: $compressedPath');
            return null;
          }
        } catch (e) {
          print('PDFToolsService: Error adding compressed file to cache: $e');
          // Return path anyway - file exists even if cache update failed
        }
      }
      
      return compressedPath;
    } catch (e, stackTrace) {
      print('PDFToolsService: Fatal error in compressPDF: $e');
      print('Stack trace: $stackTrace');
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

