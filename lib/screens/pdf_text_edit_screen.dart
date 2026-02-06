import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/pdf_text_extraction_service.dart';
import '../widgets/in_app_file_picker.dart';
import 'pdf_viewer_screen.dart';

/// Screen for editing PDF text content
/// 
/// Implements a three-step workflow:
/// 1. Extract text from existing PDF
/// 2. Display in editable TextField
/// 3. Generate new PDF from edited text
class PDFTextEditScreen extends StatefulWidget {
  final String? initialPdfPath;
  
  const PDFTextEditScreen({
    super.key,
    this.initialPdfPath,
  });

  @override
  State<PDFTextEditScreen> createState() => _PDFTextEditScreenState();
}

class _PDFTextEditScreenState extends State<PDFTextEditScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;
  String? _currentPdfPath;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialPdfPath != null) {
      _loadPdf(widget.initialPdfPath!);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// Load PDF file and extract text content
  Future<void> _loadPdf(String pdfPath) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        setState(() {
          _errorMessage = 'PDF file not found';
          _isLoading = false;
        });
        return;
      }

      final pdfBytes = await file.readAsBytes();
      
      // Extract text from PDF
      final extractedText = await PDFTextExtractionService.extractPdfContent(pdfBytes);
      
      setState(() {
        _textController.text = extractedText;
        _currentPdfPath = pdfPath;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading PDF: $e';
        _isLoading = false;
      });
    }
  }

  /// Pick PDF file from app files
  Future<void> _pickPdfFile() async {
    try {
      final selectedFiles = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (context) => const InAppFilePicker(
            allowMultiSelect: false,
            title: 'Select PDF to Edit Text',
          ),
        ),
      );

      if (selectedFiles != null && selectedFiles.isNotEmpty) {
        await _loadPdf(selectedFiles.first);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking file: $e';
      });
    }
  }

  /// Save edited text as new PDF
  Future<void> _savePdf() async {
    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter some text before saving'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // Generate new PDF from edited text
      final pdfBytes = await PDFTextExtractionService.generateEditedPdf(
        _textController.text,
      );

      if (pdfBytes == null) {
        setState(() {
          _errorMessage = 'Failed to generate PDF';
          _isSaving = false;
        });
        return;
      }

      // Get directory for saving
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = _currentPdfPath != null
          ? path.basenameWithoutExtension(_currentPdfPath!) + '_edited.pdf'
          : 'edited_pdf_$timestamp.pdf';
      final savePath = path.join(directory.path, fileName);

      // Save PDF file
      final file = File(savePath);
      await file.writeAsBytes(pdfBytes);

      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved successfully: $fileName'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () {
                // Navigate to PDF viewer for inline editing
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => PDFViewerScreen(
                      filePath: savePath,
                      fileName: fileName,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving PDF: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit PDF Text'),
        actions: [
          if (_currentPdfPath == null)
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: _isLoading ? null : _pickPdfFile,
              tooltip: 'Load PDF',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _errorMessage != null && _textController.text.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _pickPdfFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Pick PDF File'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        color: Colors.red.shade50,
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          expands: true,
                          decoration: const InputDecoration(
                            hintText: 'PDF text will appear here after loading...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(12),
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : _savePdf,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save PDF'),
            ),
    );
  }
}

