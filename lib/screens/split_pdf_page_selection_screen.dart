import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../services/pdf_isolate_service.dart';
import '../services/pdf_tools_service.dart';
import '../services/pdf_service.dart';
import '../services/pdf_cache_service.dart';
import '../services/pdf_preferences_service.dart';

class SplitPDFPageSelectionScreen extends StatefulWidget {
  final String pdfPath;
  final String fileName;

  const SplitPDFPageSelectionScreen({
    super.key,
    required this.pdfPath,
    required this.fileName,
  });

  @override
  State<SplitPDFPageSelectionScreen> createState() => _SplitPDFPageSelectionScreenState();
}

class _SplitPDFPageSelectionScreenState extends State<SplitPDFPageSelectionScreen> {
  Set<int> _selectedPages = {};
  int _totalPages = 0;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadPDFInfo();
  }

  Future<void> _loadPDFInfo() async {
    try {
      final info = await PDFIsolateService.loadPDFInfo(widget.pdfPath);
      if (mounted) {
        setState(() {
          _totalPages = info.pageCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _togglePageSelection(int pageIndex) {
    setState(() {
      if (_selectedPages.contains(pageIndex)) {
        _selectedPages.remove(pageIndex);
      } else {
        _selectedPages.add(pageIndex);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPages.length == _totalPages) {
        _selectedPages.clear();
      } else {
        _selectedPages = List.generate(_totalPages, (index) => index).toSet();
      }
    });
  }

  Future<void> _splitSelectedPages() async {
    if (_selectedPages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one page to split'),
          backgroundColor: Colors.red,
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
      // Convert page indices (0-based) to page numbers (1-based) and sort
      final selectedPageNumbers = _selectedPages.toList()..sort();
      
      // Split only selected pages
      final splitFiles = await PDFToolsService.splitPDFPages(
        widget.pdfPath,
        selectedPageNumbers,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      if (splitFiles.isNotEmpty) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'split',
          widget.pdfPath,
          resultPath: splitFiles.first,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF split into ${splitFiles.length} file(s). Files saved in app storage.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );

          // Pop back to tools screen
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to split PDF. Please try again.'),
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
        title: Text(
          'Selected ${_selectedPages.length}',
          style: const TextStyle(
            color: Color(0xFF263238),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Row(
            children: [
              const Text(
                'All',
                style: TextStyle(
                  color: Color(0xFF263238),
                  fontSize: 14,
                ),
              ),
              Checkbox(
                value: _totalPages > 0 && _selectedPages.length == _totalPages,
                onChanged: _isLoading ? null : (value) => _toggleSelectAll(),
                activeColor: const Color(0xFFE53935),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.7,
                    ),
                    itemCount: _totalPages,
                    itemBuilder: (context, index) {
                      final pageNumber = index + 1;
                      final isSelected = _selectedPages.contains(index);
                      return _buildPageThumbnail(pageNumber, index, isSelected);
                    },
                  ),
                ),
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
                    onPressed: _isProcessing || _selectedPages.isEmpty
                        ? null
                        : _splitSelectedPages,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: Text(
                      'Continue (${_selectedPages.length})',
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

  Widget _buildPageThumbnail(int pageNumber, int pageIndex, bool isSelected) {
    return GestureDetector(
      onTap: () => _togglePageSelection(pageIndex),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: isSelected ? const Color(0xFFE53935) : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(7),
                      topRight: Radius.circular(7),
                    ),
                    child: _PDFPageThumbnail(
                      filePath: widget.pdfPath,
                      pageNumber: pageNumber,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '$pageNumber',
                    style: TextStyle(
                      color: isSelected ? const Color(0xFFE53935) : Colors.grey[600],
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Checkbox in top-right corner
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      color: Color(0xFFE53935),
                      size: 18,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// Widget to display a single PDF page as thumbnail
class _PDFPageThumbnail extends StatefulWidget {
  final String filePath;
  final int pageNumber;

  const _PDFPageThumbnail({
    required this.filePath,
    required this.pageNumber,
  });

  @override
  State<_PDFPageThumbnail> createState() => _PDFPageThumbnailState();
}

class _PDFPageThumbnailState extends State<_PDFPageThumbnail> {
  late PdfViewerController _controller;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _controller.jumpToPage(widget.pageNumber);
        setState(() {
          _isLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[200],
      child: _isLoaded
          ? SfPdfViewer.file(
              File(widget.filePath),
              controller: _controller,
              enableDoubleTapZooming: false,
              enableTextSelection: false,
              canShowScrollHead: false,
              canShowScrollStatus: false,
              canShowPaginationDialog: false,
              canShowPasswordDialog: false,
              pageLayoutMode: PdfPageLayoutMode.single,
              scrollDirection: PdfScrollDirection.horizontal,
              onDocumentLoaded: (details) {
                if (mounted) {
                  _controller.jumpToPage(widget.pageNumber);
                }
              },
            )
          : const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
                ),
              ),
            ),
    );
  }
}

