import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'dart:io';
import '../services/pdf_service.dart';
import '../models/pdf_file.dart';
import '../widgets/pdf_annotation_overlay.dart';

class PDFViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const PDFViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  late PdfViewerController _pdfViewerController;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = true;
  bool _isDarkMode = false;
  bool _isFavorite = false;
  PDFFile? _pdfFileInfo;
  
  // Annotation/Editing state
  bool _isEditingMode = false;
  String _selectedTool = 'pen'; // 'pen', 'highlight', 'underline', 'eraser', 'text', 'none'
  Color _selectedColor = Colors.red;
  double _strokeWidth = 3.0;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _loadPDFInfo();
  }

  Future<void> _loadPDFInfo() async {
    final file = File(widget.filePath);
    if (await file.exists()) {
      final stat = await file.stat();
      final fileName = widget.fileName;
      final fileSize = PDFService.formatFileSize(stat.size);
      final modifiedDate = stat.modified;
      final date = PDFService.formatDate(modifiedDate);

      setState(() {
        _pdfFileInfo = PDFFile(
          name: fileName,
          date: date,
          size: fileSize,
          isFavorite: _isFavorite,
          filePath: widget.filePath,
        );
      });
    }
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }

  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    setState(() {
      _totalPages = details.document.pages.count;
      _isLoading = false;
    });
  }

  void _onPageChanged(PdfPageChangedDetails details) {
    setState(() {
      _currentPage = details.newPageNumber;
      // Clear annotations when page changes (optional - you can remove this if you want annotations to persist)
    });
  }

  void _goToPage(int pageNumber) {
    if (pageNumber >= 1 && pageNumber <= _totalPages) {
      _pdfViewerController.jumpToPage(pageNumber);
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
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {
              // Search functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.black),
            onPressed: () {
              // Share functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.description, color: Colors.black),
            onPressed: () {
              // Document info
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: _showOptionsBottomSheet,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Page $_currentPage',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // PDF Viewer with annotation overlay
          PDFAnnotationOverlay(
            drawingColor: _getToolColor(),
            strokeWidth: _getStrokeWidth(),
            isDrawing: _isEditingMode && (_selectedTool == 'pen' || _selectedTool == 'highlight' || _selectedTool == 'underline' || _selectedTool == 'eraser'),
            isEraser: _selectedTool == 'eraser',
            toolType: _selectedTool,
            onClear: () {},
            child: SfPdfViewer.file(
              File(widget.filePath),
              controller: _pdfViewerController,
              onDocumentLoaded: _onDocumentLoaded,
              onPageChanged: _onPageChanged,
            ),
          ),
          // Loading indicator
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      floatingActionButton: _isEditingMode
          ? null
          : FloatingActionButton(
              onPressed: () {
                setState(() {
                  _isEditingMode = true;
                });
              },
              backgroundColor: const Color(0xFF1976D2),
              child: const Icon(Icons.edit, color: Colors.white),
            ),
      bottomNavigationBar: _isEditingMode
          ? _buildEditingToolbar()
          : (_totalPages > 0
              ? Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  _totalPages > 3 ? 3 : _totalPages,
                  (index) {
                    final pageNumber = index + 1;
                    final isActive = _currentPage == pageNumber;
                    return GestureDetector(
                      onTap: () => _goToPage(pageNumber),
                      child: Container(
                        width: 60,
                        height: 60,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.white : Colors.grey[200],
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFFE53935)
                                : Colors.grey[300]!,
                            width: isActive ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Page thumbnail placeholder
                            Container(
                              width: 40,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Center(
                                child: Text(
                                  '$pageNumber',
                                  style: TextStyle(
                                    color: isActive
                                        ? const Color(0xFFE53935)
                                        : Colors.grey[600],
                                    fontSize: 12,
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$pageNumber',
                              style: TextStyle(
                                color: isActive
                                    ? const Color(0xFFE53935)
                                    : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
              : null),
    );
  }

  Color _getToolColor() {
    switch (_selectedTool) {
      case 'highlight':
        return Colors.yellow.withOpacity(0.4);
      case 'underline':
        return Colors.blue;
      case 'eraser':
        return Colors.white;
      default:
        return _selectedColor;
    }
  }

  double _getStrokeWidth() {
    switch (_selectedTool) {
      case 'highlight':
        return 15.0; // Thicker for highlight
      case 'underline':
        return 2.0; // Thin line for underline
      case 'eraser':
        return 20.0; // Larger eraser
      default:
        return _strokeWidth;
    }
  }

  Widget _buildEditingToolbar() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Document/Text tool
          _buildToolButton(
            icon: Icons.text_fields,
            label: 'Text',
            isSelected: _selectedTool == 'text',
            onTap: () => _showTextInputDialog(),
          ),
          // Underline tool
          _buildToolButton(
            icon: Icons.format_underline,
            label: 'Underline',
            isSelected: _selectedTool == 'underline',
            onTap: () => setState(() => _selectedTool = 'underline'),
          ),
          // Highlight tool
          _buildToolButton(
            icon: Icons.highlight,
            label: 'Highlight',
            isSelected: _selectedTool == 'highlight',
            onTap: () => setState(() => _selectedTool = 'highlight'),
          ),
          // Pen tool
          _buildToolButton(
            icon: Icons.edit,
            label: 'Pen',
            isSelected: _selectedTool == 'pen',
            onTap: () => setState(() => _selectedTool = 'pen'),
          ),
          // Eraser tool
          _buildToolButton(
            icon: Icons.cleaning_services,
            label: 'Eraser',
            isSelected: _selectedTool == 'eraser',
            onTap: () => setState(() => _selectedTool = 'eraser'),
          ),
          // Done button
          _buildToolButton(
            icon: Icons.check,
            label: 'Done',
            isSelected: false,
            onTap: () {
              setState(() {
                _isEditingMode = false;
                _selectedTool = 'none';
              });
            },
            color: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final buttonColor = color ?? (_selectedTool == 'pen' ? Colors.red : Colors.grey[700]!);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? buttonColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? buttonColor : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? buttonColor : Colors.grey[600],
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildOptionsBottomSheet(),
    );
  }

  Widget _buildOptionsBottomSheet() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // PDF File Information
          if (_pdfFileInfo != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'PDF',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pdfFileInfo!.name,
                          style: const TextStyle(
                            color: Color(0xFF263238),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_pdfFileInfo!.date} • ${_pdfFileInfo!.size}',
                          style: const TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.star : Icons.star_outline,
                      color: _isFavorite
                          ? const Color(0xFFE53935)
                          : const Color(0xFF9E9E9E),
                    ),
                    onPressed: () {
                      setState(() {
                        _isFavorite = !_isFavorite;
                      });
                    },
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // Options List
          _buildOptionTile(
            icon: Icons.dark_mode,
            title: 'Dark mode',
            onTap: _toggleDarkMode,
          ),
          _buildOptionTile(
            icon: Icons.merge,
            title: 'Merge PDF',
            onTap: _mergePDF,
          ),
          _buildOptionTile(
            icon: Icons.content_cut,
            title: 'Split PDF',
            onTap: _splitPDF,
          ),
          _buildOptionTile(
            icon: Icons.arrow_forward,
            title: 'Go to page',
            onTap: _goToPageDialog,
          ),
          _buildOptionTile(
            icon: Icons.print,
            title: 'Print',
            onTap: _printPDF,
          ),
          _buildOptionTile(
            icon: Icons.share,
            title: 'Share',
            onTap: _sharePDF,
          ),
          _buildOptionTile(
            icon: Icons.delete,
            title: 'Delete',
            onTap: _deletePDF,
            isDestructive: true,
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red : const Color(0xFF263238),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : const Color(0xFF263238),
          fontSize: 16,
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isDarkMode ? 'Dark mode enabled' : 'Dark mode disabled'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _mergePDF() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select another PDF to merge'),
        duration: Duration(seconds: 2),
      ),
    );
    // TODO: Implement merge PDF functionality
  }

  void _splitPDF() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Split PDF'),
        content: const Text('This will split the PDF into separate pages. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PDF split functionality coming soon'),
                ),
              );
            },
            child: const Text('Split'),
          ),
        ],
      ),
    );
  }

  void _goToPageDialog() {
    final pageController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to Page'),
        content: TextField(
          controller: pageController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter page number (1-$_totalPages)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final pageNumber = int.tryParse(pageController.text);
              if (pageNumber != null &&
                  pageNumber >= 1 &&
                  pageNumber <= _totalPages) {
                Navigator.pop(context);
                _goToPage(pageNumber);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a valid page number (1-$_totalPages)'),
                  ),
                );
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  Future<void> _printPDF() async {
    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();
      
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error printing PDF: $e'),
        ),
      );
    }
  }

  Future<void> _sharePDF() async {
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(widget.filePath)],
          text: 'Check out this PDF: ${widget.fileName}',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF file not found'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing PDF: $e'),
        ),
      );
    }
  }

  void _deletePDF() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete PDF'),
        content: Text('Are you sure you want to delete "${widget.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final file = File(widget.filePath);
                if (await file.exists()) {
                  await file.delete();
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to home screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('PDF deleted successfully'),
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error deleting PDF: $e'),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showTextInputDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Text'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'Enter text to add',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Text "${textController.text}" added'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                // TODO: Implement text annotation on PDF
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

