import 'package:flutter/material.dart';
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
                  selection: selectedText,
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
                            },
                          )
                        : null,
                  ),
                  style: const TextStyle(fontSize: 14),
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
      
      // Rename the merged file to user's chosen name
      if (finalMergedPath != null) {
        try {
          final mergedFile = File(finalMergedPath);
          if (await mergedFile.exists()) {
            final directory = path.dirname(finalMergedPath);
            final newPath = path.join(directory, '$fileName.pdf');
            final renamedFile = await mergedFile.rename(newPath);
            finalMergedPath = renamedFile.path;
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
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'merge',
          filePaths.first,
          resultPath: finalMergedPath,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDFs merged successfully!'),
              duration: Duration(seconds: 2),
            ),
          );

          // Navigate to merged PDF
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                filePath: finalMergedPath,
                fileName: fileName,
              ),
            ),
          );

          // Pop merge screen and trigger refresh
          if (mounted) {
            Navigator.of(context).pop(true);
          }
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
}

