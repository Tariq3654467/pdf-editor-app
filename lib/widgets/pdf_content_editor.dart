import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../services/pdf_content_editor_service.dart';
import 'dart:io';
import 'dart:async';

/// Interactive PDF content editor widget (Sejda-style)
/// Allows true content editing with draggable/resizable elements
class PDFContentEditor extends StatefulWidget {
  final String filePath;
  final int currentPage;
  final Function(String)? onSave;
  final Function()? onCancel;

  const PDFContentEditor({
    super.key,
    required this.filePath,
    required this.currentPage,
    this.onSave,
    this.onCancel,
  });

  @override
  State<PDFContentEditor> createState() => _PDFContentEditorState();
}

class _PDFContentEditorState extends State<PDFContentEditor> {
  List<PDFTextElement> _textElements = [];
  List<PDFImageElement> _imageElements = [];
  PDFTextElement? _selectedTextElement;
  PDFImageElement? _selectedImageElement;
  bool _isAddingText = false;
  Offset? _newTextPosition;
  Color _selectedColor = Colors.black;
  double _selectedFontSize = 12.0;
  final List<Map<String, dynamic>> _undoStack = [];
  final List<Map<String, dynamic>> _redoStack = [];
  late PdfViewerController _pdfController;
  Size? _actualPageSize; // Actual PDF page size
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _loadPageDimensions();
    _loadElements();
  }

  Future<void> _loadPageDimensions() async {
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final document = sf.PdfDocument(inputBytes: bytes);
        if (widget.currentPage - 1 >= 0 && widget.currentPage - 1 < document.pages.count) {
          final page = document.pages[widget.currentPage - 1];
          setState(() {
            _actualPageSize = Size(page.size.width, page.size.height);
            _isLoading = false;
          });
        }
        document.dispose();
      }
    } catch (e) {
      print('Error loading page dimensions: $e');
      // Fallback to default size
      setState(() {
        _actualPageSize = const Size(612, 792);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadElements() async {
    // Load existing text elements from PDF
    final elements = await PDFContentEditorService.extractTextElements(
      widget.filePath,
      widget.currentPage - 1, // Convert to 0-based
    );
    setState(() {
      _textElements = elements;
    });
  }

  void _saveState() {
    _undoStack.add({
      'textElements': _textElements.map((e) => e.toMap()).toList(),
      'imageElements': _imageElements.map((e) => e.toMap()).toList(),
    });
    _redoStack.clear();
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add({
      'textElements': _textElements.map((e) => e.toMap()).toList(),
      'imageElements': _imageElements.map((e) => e.toMap()).toList(),
    });
    final previousState = _undoStack.removeLast();
    setState(() {
      _textElements = (previousState['textElements'] as List)
          .map((e) => PDFTextElement.fromMap(e))
          .toList();
      _imageElements = (previousState['imageElements'] as List)
          .map((e) => PDFImageElement.fromMap(e))
          .toList();
      _selectedTextElement = null;
      _selectedImageElement = null;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add({
      'textElements': _textElements.map((e) => e.toMap()).toList(),
      'imageElements': _imageElements.map((e) => e.toMap()).toList(),
    });
    final nextState = _redoStack.removeLast();
    setState(() {
      _textElements = (nextState['textElements'] as List)
          .map((e) => PDFTextElement.fromMap(e))
          .toList();
      _imageElements = (nextState['imageElements'] as List)
          .map((e) => PDFImageElement.fromMap(e))
          .toList();
      _selectedTextElement = null;
      _selectedImageElement = null;
    });
  }

  void _onTextTap(Offset position, Size screenSize) {
    if (_actualPageSize == null) return;
    
    // Convert screen position to PDF coordinates
    final pdfPosition = _screenToPDF(position, screenSize);
    
    // Check if tapped on existing text element
    for (var element in _textElements) {
      if (element.pageIndex == widget.currentPage - 1) {
        if (element.bounds.contains(pdfPosition)) {
          setState(() {
            _selectedTextElement = element;
            _selectedImageElement = null;
            _isAddingText = false;
          });
          _showTextEditDialog(element);
          return;
        }
      }
    }

    // If not tapped on existing text, add new text
    setState(() {
      _newTextPosition = pdfPosition;
      _isAddingText = true;
      _selectedTextElement = null;
      _selectedImageElement = null;
    });
    _showAddTextDialog(pdfPosition, screenSize);
  }

  Offset _screenToPDF(Offset screenPos, Size screenSize) {
    if (_actualPageSize == null) return screenPos;
    // Simplified conversion - in production, account for zoom and scroll
    return Offset(
      screenPos.dx * (_actualPageSize!.width / screenSize.width),
      screenPos.dy * (_actualPageSize!.height / screenSize.height),
    );
  }

  Offset _pdfToScreen(Offset pdfPos, Size screenSize) {
    if (_actualPageSize == null) return pdfPos;
    return Offset(
      pdfPos.dx * (screenSize.width / _actualPageSize!.width),
      pdfPos.dy * (screenSize.height / _actualPageSize!.height),
    );
  }

  void _showTextEditDialog(PDFTextElement element) {
    final controller = TextEditingController(text: element.text);
    final fontSize = element.fontSize;
    final color = element.color;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Text'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Text',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Font Size: '),
                    Expanded(
                      child: Slider(
                        value: fontSize,
                        min: 8,
                        max: 72,
                        divisions: 64,
                        label: '${fontSize.toInt()}',
                        onChanged: (value) {
                          setDialogState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    Colors.black,
                    Colors.red,
                    Colors.blue,
                    Colors.green,
                    Colors.orange,
                  ].map((c) {
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {});
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          border: Border.all(
                            color: color == c ? Colors.black : Colors.grey,
                            width: color == c ? 3 : 1,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _saveState();
                final updatedElement = element.copyWith(
                  text: controller.text,
                  fontSize: fontSize,
                  color: color,
                );
                setState(() {
                  final index = _textElements.indexWhere((e) => e.id == element.id);
                  if (index != -1) {
                    _textElements[index] = updatedElement;
                  }
                  _selectedTextElement = updatedElement;
                });
                Navigator.pop(context);
              },
              child: const Text('Update'),
            ),
            TextButton(
              onPressed: () {
                _saveState();
                setState(() {
                  _textElements.removeWhere((e) => e.id == element.id);
                  _selectedTextElement = null;
                });
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTextDialog(Offset pdfPosition, Size screenSize) {
    final controller = TextEditingController();
    double fontSize = _selectedFontSize;
    Color color = _selectedColor;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Text'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Text',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Font Size: '),
                    Expanded(
                      child: Slider(
                        value: fontSize,
                        min: 8,
                        max: 72,
                        divisions: 64,
                        label: '${fontSize.toInt()}',
                        onChanged: (value) {
                          setDialogState(() {
                            fontSize = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    Colors.black,
                    Colors.red,
                    Colors.blue,
                    Colors.green,
                    Colors.orange,
                  ].map((c) {
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          color = c;
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          border: Border.all(
                            color: color == c ? Colors.black : Colors.grey,
                            width: color == c ? 3 : 1,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _isAddingText = false;
                  _newTextPosition = null;
                });
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isEmpty) {
                  Navigator.pop(context);
                  return;
                }
                _saveState();
                final newElement = PDFTextElement(
                  id: 'text_${DateTime.now().millisecondsSinceEpoch}',
                  text: controller.text,
                  bounds: Rect.fromLTWH(pdfPosition.dx, pdfPosition.dy, 200, 50),
                  pageIndex: widget.currentPage - 1,
                  fontSize: fontSize,
                  color: color,
                );
                setState(() {
                  _textElements.add(newElement);
                  _isAddingText = false;
                  _newTextPosition = null;
                  _selectedFontSize = fontSize;
                  _selectedColor = color;
                });
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveEdits() async {
    if (!mounted) return;
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final success = await PDFContentEditorService.saveAllEdits(
        widget.filePath,
        _textElements,
        _imageElements,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading
      }

      if (success && widget.onSave != null) {
        widget.onSave!(widget.filePath);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error saving PDF edits'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final screenSize = MediaQuery.of(context).size;
    
    return Stack(
      children: [
        // PDF viewer
        SfPdfViewer.file(
          File(widget.filePath),
          controller: _pdfController,
          initialZoomLevel: 1.0,
          enableTextSelection: false,
          onDocumentLoadFailed: (details) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error loading PDF: ${details.error}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
        // Overlay for interactive text elements - only intercepts taps on text
        IgnorePointer(
          ignoring: false,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (details) {
              // Only handle taps if not on existing text
              final pdfPos = _screenToPDF(details.localPosition, screenSize);
              bool tappedOnText = false;
              
              for (var element in _textElements) {
                if (element.pageIndex == widget.currentPage - 1 &&
                    element.bounds.contains(pdfPos)) {
                  tappedOnText = true;
                  break;
                }
              }
              
              if (!tappedOnText) {
                _onTextTap(details.localPosition, screenSize);
              }
            },
            child: Stack(
              children: _textElements
                  .where((e) => e.pageIndex == widget.currentPage - 1)
                  .map((element) {
                    final screenPos = _pdfToScreen(
                      Offset(element.bounds.left, element.bounds.top),
                      screenSize,
                    );
                    final screenSize2 = _pdfToScreen(
                      Offset(element.bounds.width, element.bounds.height),
                      screenSize,
                    );
                    
                    return Positioned(
                      left: screenPos.dx,
                      top: screenPos.dy,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTextElement = element;
                            _selectedImageElement = null;
                          });
                          _showTextEditDialog(element);
                        },
                        child: Container(
                          width: screenSize2.dx,
                          height: screenSize2.dy,
                          decoration: BoxDecoration(
                            border: _selectedTextElement?.id == element.id
                                ? Border.all(color: Colors.blue, width: 2)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            element.text,
                            style: TextStyle(
                              fontSize: element.fontSize * (screenSize.width / (_actualPageSize?.width ?? 612)),
                              color: element.color,
                              fontWeight: element.isBold ? FontWeight.bold : FontWeight.normal,
                              fontStyle: element.isItalic ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ),
        // Toolbar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildToolbar(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _undoStack.isEmpty ? null : _undo,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _redoStack.isEmpty ? null : _redo,
              tooltip: 'Redo',
            ),
            IconButton(
              icon: const Icon(Icons.text_fields),
              onPressed: () {
                // Text tool is always active in content edit mode
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tap on the PDF to add text'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'Add Text',
            ),
            IconButton(
              icon: const Icon(Icons.image),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Image insertion coming soon'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'Add Image',
            ),
            ElevatedButton(
              onPressed: _saveEdits,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onCancel,
              tooltip: 'Cancel',
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }
}
