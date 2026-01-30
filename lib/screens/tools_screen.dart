import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../painters/tool_icons_painter.dart';
import '../services/pdf_tools_service.dart';
import '../services/pdf_service.dart';
import '../services/pdf_preferences_service.dart';
import '../widgets/in_app_file_picker.dart';
import 'pdf_viewer_screen.dart';

class ToolsScreen extends StatefulWidget {
  final VoidCallback? onOperationComplete;
  
  const ToolsScreen({super.key, this.onOperationComplete});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // First row of tools
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Scan to PDF',
                  backgroundColor: const Color(0xFFB2E7D9),
                  iconColor: const Color(0xFF4CAF50),
                  painter: ScanToPDFPainter(color: const Color(0xFF4CAF50)),
                  onTap: _scanToPDF,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Image to PDF',
                  backgroundColor: const Color(0xFFFFD9B3),
                  iconColor: const Color(0xFFFF9800),
                  painter: ImageToPDFPainter(color: const Color(0xFFFF9800)),
                  onTap: _imageToPDF,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Second row of tools
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Split PDF',
                  backgroundColor: const Color(0xFFE8B4E1),
                  iconColor: const Color(0xFF9C27B0),
                  painter: SplitPDFPainter(color: const Color(0xFF9C27B0)),
                  onTap: _splitPDF,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Merge PDF',
                  backgroundColor: const Color(0xFFB3E5B3),
                  iconColor: const Color(0xFF4CAF50),
                  painter: MergePDFPainter(color: const Color(0xFF4CAF50)),
                  onTap: _mergePDF,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Third row of tools
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Annotate',
                  backgroundColor: const Color(0xFFD9D4E8),
                  iconColor: const Color(0xFF9C27B0),
                  painter: AnnotatePainter(color: const Color(0xFF9C27B0)),
                  onTap: _annotatePDF,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Compress PDF',
                  backgroundColor: const Color(0xFFFFCDD2),
                  iconColor: const Color(0xFFE53935),
                  painter: CompressPDFPainter(color: const Color(0xFFE53935)),
                  onTap: _compressPDF,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Fourth row of tools
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Create a ZIP file',
                  backgroundColor: const Color(0xFFFFE8B3),
                  iconColor: const Color(0xFFFFC107),
                  painter: CreateZIPPainter(color: const Color(0xFFFFC107)),
                  onTap: _createZIPFile,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Print',
                  backgroundColor: const Color(0xFFB3D9FF),
                  iconColor: const Color(0xFF2196F3),
                  painter: PrintPainter(color: const Color(0xFF2196F3)),
                  onTap: _printPDF,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildToolCard(
    BuildContext context, {
    required String title,
    required Color backgroundColor,
    required Color iconColor,
    required CustomPainter painter,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isProcessing ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.08,
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: CustomPaint(
                painter: painter,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF263238),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanToPDF() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (photo != null) {
        final pdfPath = await PDFToolsService.scanToPDF(photo.path);
        if (pdfPath != null) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PDFViewerScreen(
                  filePath: pdfPath,
                  fileName: 'Scanned Document.pdf',
                ),
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PDF created successfully'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error creating PDF'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _imageToPDF() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final List<XFile>? images = await _imagePicker.pickMultiImage();
      if (images != null && images.isNotEmpty) {
        final imagePaths = images.map((img) => img.path).toList();
        final pdfPath = await PDFToolsService.imageToPDF(imagePaths);
        if (pdfPath != null) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PDFViewerScreen(
                  filePath: pdfPath,
                  fileName: 'Images to PDF.pdf',
                ),
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PDF created successfully'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _splitPDF() async {
    if (_isProcessing) return;

    // Show in-app file picker
    final selectedFiles = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => const InAppFilePicker(
          allowMultiSelect: false,
          title: 'Select PDF to Split',
        ),
      ),
    );

    if (selectedFiles == null || selectedFiles.isEmpty) return;
    final filePath = selectedFiles.first;

    setState(() => _isProcessing = true);

    // Show loading dialog
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        dialogContext = context;
          return PopScope(
          canPop: false,
          child: Dialog(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Splitting PDF...',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This may take a moment',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      // Run split with timeout
      final splitFiles = await PDFToolsService.splitPDF(filePath)
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () {
              print('Split PDF operation timed out');
              return <String>[];
            },
          )
          .catchError((e) {
            print('Error in split PDF: $e');
            return <String>[];
          });

      // Close loading dialog
      if (mounted && dialogContext != null) {
        Navigator.of(dialogContext!).pop();
      }

      if (splitFiles.isNotEmpty) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'split',
          filePath,
          resultPath: splitFiles.first,
        );
        
        // Trigger refresh of file list
        widget.onOperationComplete?.call();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF split into ${splitFiles.length} files. Files saved in app storage and will appear in your file list.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // PHASE 5: User-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to split PDF. The PDF may be too large or corrupted. Please try with a smaller PDF.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // PHASE 5: Close loading dialog on error and show user-friendly message
      if (mounted && dialogContext != null) {
        Navigator.of(dialogContext!).pop();
      }
      if (mounted) {
        final errorMessage = e.toString().contains('timeout')
            ? 'Operation timed out. The PDF may be too large. Please try with a smaller PDF.'
            : e.toString().contains('permission')
                ? 'Permission denied. Please grant storage access in settings.'
                : 'An error occurred while splitting the PDF. Please try again.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _splitPDF(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _mergePDF() async {
    if (_isProcessing) return;

    // Show in-app file picker with multi-select
    final selectedFiles = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => const InAppFilePicker(
          allowMultiSelect: true,
          title: 'Select PDFs to Merge',
        ),
      ),
    );

    if (selectedFiles == null || selectedFiles.isEmpty) return;
    if (selectedFiles.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least 2 PDFs to merge'),
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final mergedPath = await PDFToolsService.mergePDFs(selectedFiles);
      if (mergedPath != null) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'merge',
          selectedFiles.first,
          resultPath: mergedPath,
        );
        
        // Trigger refresh of file list BEFORE navigating
        // This ensures the merged file appears in the list when user returns
        widget.onOperationComplete?.call();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDFs merged successfully! File saved in app storage and will appear in your file list.'),
              duration: Duration(seconds: 3),
            ),
          );
          
          // Navigate to merged PDF (optional - user can view it)
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                filePath: mergedPath,
                fileName: 'Merged PDF.pdf',
              ),
            ),
          );
          
          // Refresh file list when returning from PDF viewer
          if (result == true || mounted) {
            widget.onOperationComplete?.call();
          }
        }
      } else {
        // PHASE 5: User-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to merge PDFs. One or more PDFs may be corrupted or too large.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // PHASE 5: User-friendly error with retry
      if (mounted) {
        final errorMessage = e.toString().contains('timeout')
            ? 'Merge operation timed out. The PDFs may be too large. Please try with smaller PDFs.'
            : e.toString().contains('permission')
                ? 'Permission denied. Please grant storage access in settings.'
                : 'An error occurred while merging PDFs. Please try again.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _mergePDF(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _annotatePDF() async {
    // Use in-app file picker instead of system file manager
    final selectedFiles = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => const InAppFilePicker(
          allowMultiSelect: false,
          title: 'Select PDF to Annotate',
        ),
      ),
    );

    if (selectedFiles != null && selectedFiles.isNotEmpty && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PDFViewerScreen(
            filePath: selectedFiles.first,
            fileName: 'Annotate PDF',
          ),
        ),
      );
    }
  }

  Future<void> _compressPDF() async {
    if (_isProcessing) return;

    // Use in-app file picker instead of system file manager
    final selectedFiles = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => const InAppFilePicker(
          allowMultiSelect: false,
          title: 'Select PDF to Compress',
        ),
      ),
    );

    if (selectedFiles == null || selectedFiles.isEmpty) return;

    final filePath = selectedFiles.first;
    setState(() => _isProcessing = true);

    try {
      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      final compressedPath = await PDFToolsService.compressPDF(filePath);

      // Close loading dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (compressedPath != null) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'compress',
          filePath,
          resultPath: compressedPath,
        );
        widget.onOperationComplete?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF compressed successfully! File saved in app storage.'),
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                filePath: compressedPath,
                fileName: 'Compressed PDF.pdf',
              ),
            ),
          );
        }
      } else {
        // PHASE 5: User-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to compress PDF. The PDF may be corrupted or already compressed.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // PHASE 5: Close loading dialog on error and show user-friendly message
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        final errorMessage = e.toString().contains('timeout')
            ? 'Compression timed out. The PDF may be too large. Please try with a smaller PDF.'
            : e.toString().contains('permission')
                ? 'Permission denied. Please grant storage access in settings.'
                : 'An error occurred while compressing the PDF. Please try again.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _compressPDF(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _createZIPFile() async {
    if (_isProcessing) return;

    // Use in-app file picker with multi-select instead of system file manager
    final selectedFiles = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => const InAppFilePicker(
          allowMultiSelect: true,
          title: 'Select PDFs to Create ZIP',
        ),
      ),
    );

    if (selectedFiles == null || selectedFiles.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      final zipPath = await PDFToolsService.createZIPFile(selectedFiles);

      // Close loading dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (zipPath != null) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'zip',
          selectedFiles.first,
          resultPath: zipPath,
        );
        widget.onOperationComplete?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ZIP file created: ${path.basename(zipPath)}. File saved in app storage.'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create ZIP file. Please try again.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog on error
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _printPDF() async {
    // Use in-app file picker instead of system file manager
    final selectedFiles = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => const InAppFilePicker(
          allowMultiSelect: false,
          title: 'Select PDF to Print',
        ),
      ),
    );

    if (selectedFiles == null || selectedFiles.isEmpty) return;

    final filePath = selectedFiles.first;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF file not found'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      final bytes = await file.readAsBytes();
      
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing: $e')),
        );
      }
    }
  }
}
