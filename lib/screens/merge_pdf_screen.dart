import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/pdf_file.dart';
import '../services/pdf_cache_service.dart';
import '../services/pdf_tools_service.dart';
import '../services/pdf_preferences_service.dart';
import '../services/pdf_storage_service.dart';
import '../services/pdf_service.dart';
import 'pdf_viewer_screen.dart';
import '../widgets/in_app_file_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class MergePDFScreen extends StatefulWidget {
  const MergePDFScreen({super.key});

  @override
  State<MergePDFScreen> createState() => _MergePDFScreenState();
}

class _MergePDFScreenState extends State<MergePDFScreen> {
  List<PDFFile> _selectedPDFs = [];
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF263238)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Merge PDF',
          style: TextStyle(
            color: Color(0xFF263238),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : _addPDFs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE53935)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Add',
                style: TextStyle(
                  color: Color(0xFFE53935),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _selectedPDFs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.insert_drive_file,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No PDFs selected',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap "Add" to select PDFs to merge',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _selectedPDFs.length,
                    itemBuilder: (context, index) {
                      return _buildPDFItem(_selectedPDFs[index], index);
                    },
                  ),
          ),
          if (_selectedPDFs.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isProcessing || _selectedPDFs.length < 2
                    ? null
                    : _showFileNameDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: Text(
                  'Merge (${_selectedPDFs.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPDFItem(PDFFile pdf, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        dense: true,
        leading: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFFE53935),
          ),
          child: const Center(
            child: Text(
              'PDF',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        ),
        title: Text(
          pdf.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF263238),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${pdf.date} - ${pdf.size}',
          style: const TextStyle(
            color: Color(0xFF9E9E9E),
            fontSize: 11,
          ),
        ),
        trailing: IconButton(
          onPressed: () {
            setState(() {
              _selectedPDFs.removeAt(index);
            });
          },
          icon: const Icon(
            Icons.close,
            color: Color(0xFF9E9E9E),
            size: 20,
          ),
        ),
      ),
    );
  }

  Future<void> _addPDFs() async {
    final selectedFiles = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => const InAppFilePicker(
          allowMultiSelect: true,
          title: 'Select PDFs to Merge',
        ),
      ),
    );

    if (selectedFiles != null && selectedFiles.isNotEmpty) {
      // Load PDF info for selected files
      final List<PDFFile> newPDFs = [];
      for (final filePath in selectedFiles) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final stat = await file.stat();
            final pdf = PDFFile(
              name: path.basename(filePath),
              date: PDFService.formatDate(stat.modified),
              size: PDFService.formatFileSize(stat.size),
              filePath: filePath,
              isFavorite: false,
              dateModified: stat.modified,
              fileSizeBytes: stat.size,
            );
            newPDFs.add(pdf);
          }
        } catch (e) {
          print('Error loading PDF info: $e');
        }
      }

      setState(() {
        // Avoid duplicates
        final existingPaths = _selectedPDFs.map((p) => p.filePath).toSet();
        final uniqueNewPDFs = newPDFs.where((p) => 
          p.filePath != null && !existingPaths.contains(p.filePath)
        ).toList();
        _selectedPDFs.addAll(uniqueNewPDFs);
      });
    }
  }

  Future<void> _showFileNameDialog() async {
    // Generate default file name
    final now = DateTime.now();
    final defaultName = 'PDF_Merged_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    final TextEditingController controller = TextEditingController(text: defaultName);
    final selectedText = TextSelection(
      baseOffset: 0,
      extentOffset: defaultName.length,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'File name',
                  style: TextStyle(
                    color: Color(0xFF263238),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE53935)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              controller.clear();
                              setDialogState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        final fileName = controller.text.trim();
                        if (fileName.isNotEmpty) {
                          Navigator.of(context).pop(fileName);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE53935),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      await _mergePDFs(result);
    }
  }

  Future<void> _mergePDFs(String fileName) async {
    if (_selectedPDFs.isEmpty || _selectedPDFs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 2 PDFs to merge'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
        ),
      ),
    );

    try {
      // Get file paths
      final filePaths = _selectedPDFs
          .where((pdf) => pdf.filePath != null)
          .map((pdf) => pdf.filePath!)
          .toList();

      if (filePaths.length < 2) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select at least 2 valid PDFs to merge'),
            ),
          );
        }
        return;
      }

      // Merge PDFs
      String? finalMergedPath = await PDFToolsService.mergePDFs(filePaths);
      
      // Rename the merged file to user's chosen name (non-blocking)
      if (finalMergedPath != null) {
        try {
          // Use compute to move file operations off main thread
          final renamedPath = await _renameMergedFile(finalMergedPath, fileName);
          if (renamedPath != null) {
            finalMergedPath = renamedPath;
            
            // Update cache with new file path and name (non-blocking)
            unawaited(_updateCacheForRenamedFile(finalMergedPath));
          }
        } catch (e) {
          print('Error renaming merged file: $e');
          // Continue with original path if rename fails
        }
      }

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      if (finalMergedPath != null) {
        // Save to history (non-blocking)
        unawaited(PDFPreferencesService.addToolsHistory(
          'merge',
          filePaths.first,
          resultPath: finalMergedPath,
        ));

        if (mounted) {
          // Pop merge screen first to return to tools/home screen
          Navigator.of(context).pop(true);
          
          // Show success message after navigation completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PDFs merged successfully!'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          });

          // Navigate to merged PDF after a short delay to allow screen to pop
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && finalMergedPath != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PDFViewerScreen(
                    filePath: finalMergedPath!,
                    fileName: path.basename(finalMergedPath!),
                  ),
                ),
              );
            }
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to merge PDFs. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Rename merged file (runs in isolate to avoid blocking UI)
  Future<String?> _renameMergedFile(String mergedPath, String fileName) async {
    return await compute(_renameFileIsolate, _RenameFileRequest(
      mergedPath: mergedPath,
      fileName: fileName,
    ));
  }

  /// Update cache for renamed file (non-blocking, runs in background)
  Future<void> _updateCacheForRenamedFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        final updatedPDF = PDFFile(
          name: path.basename(filePath),
          date: PDFService.formatDate(stat.modified),
          size: PDFService.formatFileSize(stat.size),
          filePath: filePath,
          isFavorite: false,
          dateModified: stat.modified,
          fileSizeBytes: stat.size,
        );
        await PDFCacheService.addPDFToCache(updatedPDF);
        await PDFPreferencesService.setLastAccessed(filePath);
      }
    } catch (e) {
      print('Error updating cache after rename: $e');
    }
  }
}

// Helper function to run async operations without awaiting
void unawaited(Future<void> future) {
  future.catchError((error) {
    print('Unawaited future error: $error');
  });
}

/// Request class for file rename operation
class _RenameFileRequest {
  final String mergedPath;
  final String fileName;
  
  _RenameFileRequest({
    required this.mergedPath,
    required this.fileName,
  });
}

/// Isolate function: Rename file and return new path
Future<String?> _renameFileIsolate(_RenameFileRequest request) async {
  try {
    final mergedFile = File(request.mergedPath);
    if (!await mergedFile.exists()) {
      return null;
    }
    
    final directory = path.dirname(request.mergedPath);
    final newPath = path.join(directory, '${request.fileName}.pdf');
    
    // Check if file with same name exists and handle it
    var targetPath = newPath;
    var targetFile = File(targetPath);
    int counter = 1;
    while (await targetFile.exists()) {
      final nameWithoutExt = path.basenameWithoutExtension(request.fileName);
      final newFileName = '${nameWithoutExt}_$counter.pdf';
      targetPath = path.join(directory, newFileName);
      targetFile = File(targetPath);
      counter++;
    }
    
    final renamedFile = await mergedFile.rename(targetPath);
    return renamedFile.path;
  } catch (e) {
    print('Error in rename file isolate: $e');
    return null;
  }
}

