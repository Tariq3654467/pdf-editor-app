import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/pdf_file.dart';

class PDFService {
  static Future<List<PDFFile>> loadPDFsFromDevice() async {
    List<PDFFile> pdfFiles = [];

    try {
      // Get the documents directory
      final directory = await getApplicationDocumentsDirectory();
      final pdfDirectory = Directory('${directory.path}/PDFs');

      // Create directory if it doesn't exist
      if (!await pdfDirectory.exists()) {
        await pdfDirectory.create(recursive: true);
      }

      // Scan for PDF files
      final files = pdfDirectory.listSync();
      for (var file in files) {
        if (file is File && file.path.toLowerCase().endsWith('.pdf')) {
          final stat = await file.stat();
          final fileName = path.basename(file.path);
          final fileSize = formatFileSize(stat.size);
          final modifiedDate = stat.modified;

          pdfFiles.add(
            PDFFile(
              name: fileName.length > 25
                  ? '${fileName.substring(0, 22)}...'
                  : fileName,
              date: formatDate(modifiedDate),
              size: fileSize,
              isFavorite: false,
              filePath: file.path,
            ),
          );
        }
      }

      // Sort by date (newest first)
      pdfFiles.sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      print('Error loading PDFs: $e');
    }

    return pdfFiles;
  }

  static Future<String?> pickPDFFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        // Copy file to app's PDF directory
        final sourceFile = File(result.files.single.path!);
        final directory = await getApplicationDocumentsDirectory();
        final pdfDirectory = Directory('${directory.path}/PDFs');

        if (!await pdfDirectory.exists()) {
          await pdfDirectory.create(recursive: true);
        }

        final fileName = path.basename(sourceFile.path);
        final destFile = File('${pdfDirectory.path}/$fileName');

        // Copy file
        await sourceFile.copy(destFile.path);

        return destFile.path;
      }
    } catch (e) {
      print('Error picking PDF: $e');
    }

    return null;
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  static String formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }
}

