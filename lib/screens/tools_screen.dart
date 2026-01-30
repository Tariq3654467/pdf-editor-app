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
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
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
              style: const TextStyle(
                color: Color(0xFF263238),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to split PDF. The PDF may be too large.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog on error
      if (mounted && dialogContext != null) {
        Navigator.of(dialogContext!).pop();
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
        // Trigger refresh of file list
        widget.onOperationComplete?.call();
        
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                filePath: mergedPath,
                fileName: 'Merged PDF.pdf',
              ),
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDFs merged successfully! File saved in app storage and will appear in your file list.'),
              duration: Duration(seconds: 3),
            ),
          );
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

  Future<void> _annotatePDF() async {
    final filePath = await PDFService.pickPDFFile();
    if (filePath != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PDFViewerScreen(
            filePath: filePath,
            fileName: 'Annotate PDF',
          ),
        ),
      );
    }
  }

  Future<void> _compressPDF() async {
    if (_isProcessing) return;

    final filePath = await PDFService.pickPDFFile();
    if (filePath == null) return;

    setState(() => _isProcessing = true);

    try {
      final compressedPath = await PDFToolsService.compressPDF(filePath);
      if (compressedPath != null) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'compress',
          filePath,
          resultPath: compressedPath,
        );
        widget.onOperationComplete?.call();
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                filePath: compressedPath,
                fileName: 'Compressed PDF.pdf',
              ),
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF compressed successfully'),
              duration: Duration(seconds: 2),
            ),
          );
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

  Future<void> _createZIPFile() async {
    if (_isProcessing) return;

    final List<String> pdfPaths = [];
    
    // Pick multiple PDFs
    while (true) {
      final filePath = await PDFService.pickPDFFile();
      if (filePath == null) break;
      pdfPaths.add(filePath);

      if (mounted) {
        final continuePicking = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add More PDFs?'),
            content: Text('${pdfPaths.length} PDF(s) selected. Add more?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Done'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add More'),
              ),
            ],
          ),
        );

        if (continuePicking != true) break;
      }
    }

    if (pdfPaths.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final zipPath = await PDFToolsService.createZIPFile(pdfPaths);
      if (zipPath != null) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'zip',
          pdfPaths.first,
          resultPath: zipPath,
        );
        widget.onOperationComplete?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ZIP file created: ${path.basename(zipPath)}'),
              duration: const Duration(seconds: 3),
            ),
          );
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

  Future<void> _printPDF() async {
    final filePath = await PDFService.pickPDFFile();
    if (filePath == null) return;

    try {
      final file = File(filePath);
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
