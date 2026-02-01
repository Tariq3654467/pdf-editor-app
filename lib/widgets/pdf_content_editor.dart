import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../services/pdf_content_editor_service.dart';
import 'dart:io';

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

  @override
  void initState() {
    super.initState();
    _loadElements();
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
      'textElements': _textElements.map((e) => e.id).toList(),
      'imageElements': _imageElements.map((e) => e.id).toList(),
    });
    _redoStack.clear();
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add({
      'textElements': _textElements.map((e) => e.id).toList(),
      'imageElements': _imageElements.map((e) => e.id).toList(),
    });
    // In a full implementation, restore previous state
    setState(() {
      _selectedTextElement = null;
      _selectedImageElement = null;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add({
      'textElements': _textElements.map((e) => e.id).toList(),
      'imageElements': _imageElements.map((e) => e.id).toList(),
    });
    // In a full implementation, restore next state
    setState(() {
      _selectedTextElement = null;
      _selectedImageElement = null;
    });
  }

  void _onTextTap(Offset position, Size pageSize) {
    // Check if tapped on existing text element
    for (var element in _textElements) {
      if (element.pageIndex == widget.currentPage - 1) {
        final bounds = _convertToScreenBounds(element.bounds, pageSize);
        if (bounds.contains(position)) {
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
      _newTextPosition = position;
      _isAddingText = true;
      _selectedTextElement = null;
      _selectedImageElement = null;
    });
    _showAddTextDialog(position, pageSize);
  }

  void _showTextEditDialog(PDFTextElement element) {
    final controller = TextEditingController(text: element.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Text'),
        content: Column(
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
                    value: element.fontSize,
                    min: 8,
                    max: 72,
                    divisions: 64,
                    label: '${element.fontSize.toInt()}',
                    onChanged: (value) {
                      setState(() {
                        _selectedFontSize = value;
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
              ].map((color) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: _selectedColor == color ? Colors.black : Colors.grey,
                        width: _selectedColor == color ? 3 : 1,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _saveState();
              final updatedElement = element.copyWith(
                text: controller.text,
                fontSize: _selectedFontSize,
                color: _selectedColor,
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
    );
  }

  void _showAddTextDialog(Offset position, Size pageSize) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Text'),
        content: Column(
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
                    value: _selectedFontSize,
                    min: 8,
                    max: 72,
                    divisions: 64,
                    label: '${_selectedFontSize.toInt()}',
                    onChanged: (value) {
                      setState(() {
                        _selectedFontSize = value;
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
              ].map((color) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: _selectedColor == color ? Colors.black : Colors.grey,
                        width: _selectedColor == color ? 3 : 1,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
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
              final pdfBounds = _convertToPDFBounds(
                Rect.fromLTWH(position.dx, position.dy, 200, 50),
                pageSize,
              );
              final newElement = PDFTextElement(
                id: 'text_${DateTime.now().millisecondsSinceEpoch}',
                text: controller.text,
                bounds: pdfBounds,
                pageIndex: widget.currentPage - 1,
                fontSize: _selectedFontSize,
                color: _selectedColor,
              );
              setState(() {
                _textElements.add(newElement);
                _isAddingText = false;
                _newTextPosition = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Rect _convertToScreenBounds(Rect pdfBounds, Size pageSize) {
    // Convert PDF coordinates to screen coordinates
    // This is a simplified conversion - actual implementation should account for zoom
    return Rect.fromLTWH(
      pdfBounds.left * (pageSize.width / 612), // Assuming default PDF width
      pdfBounds.top * (pageSize.height / 792), // Assuming default PDF height
      pdfBounds.width * (pageSize.width / 612),
      pdfBounds.height * (pageSize.height / 792),
    );
  }

  Rect _convertToPDFBounds(Rect screenBounds, Size pageSize) {
    // Convert screen coordinates to PDF coordinates
    return Rect.fromLTWH(
      screenBounds.left * (612 / pageSize.width),
      screenBounds.top * (792 / pageSize.height),
      screenBounds.width * (612 / pageSize.width),
      screenBounds.height * (792 / pageSize.height),
    );
  }

  Future<void> _saveEdits() async {
    final success = await PDFContentEditorService.saveAllEdits(
      widget.filePath,
      _textElements,
      _imageElements,
    );

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
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return Stack(
      children: [
        // PDF viewer
        SfPdfViewer.file(
          File(widget.filePath),
          initialZoomLevel: 1.0,
          onDocumentLoadFailed: (details) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error loading PDF: ${details.error}'),
                backgroundColor: Colors.red,
              ),
            );
          },
        ),
        // Overlay for interactive text elements
        GestureDetector(
          onTapDown: (details) {
            // Convert tap position to page coordinates
            final pageSize = screenSize;
            _onTextTap(details.localPosition, pageSize);
          },
          child: Container(
            color: Colors.transparent,
            child: Stack(
              children: _textElements
                  .where((e) => e.pageIndex == widget.currentPage - 1)
                  .map((element) {
                    // Convert PDF bounds to screen bounds
                    final screenBounds = _convertToScreenBounds(element.bounds, screenSize);
                    return Positioned(
                      left: screenBounds.left,
                      top: screenBounds.top,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTextElement = element;
                            _selectedImageElement = null;
                          });
                          _showTextEditDialog(element);
                        },
                        child: Container(
                          width: screenBounds.width,
                          height: screenBounds.height,
                          decoration: BoxDecoration(
                            border: _selectedTextElement?.id == element.id
                                ? Border.all(color: Colors.blue, width: 2)
                                : Border.all(color: Colors.transparent),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            element.text,
                            style: TextStyle(
                              fontSize: element.fontSize * (screenSize.width / 612),
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

  Widget _buildTextElementOverlay(PDFTextElement element) {
    return Positioned(
      left: element.bounds.left,
      top: element.bounds.top,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTextElement = element;
            _selectedImageElement = null;
          });
        },
        child: Container(
          width: element.bounds.width,
          height: element.bounds.height,
          decoration: BoxDecoration(
            border: _selectedTextElement?.id == element.id
                ? Border.all(color: Colors.blue, width: 2)
                : null,
          ),
          child: Text(
            element.text,
            style: TextStyle(
              fontSize: element.fontSize,
              color: element.color,
              fontWeight: element.isBold ? FontWeight.bold : FontWeight.normal,
              fontStyle: element.isItalic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
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
              // Toggle text editing mode
            },
            tooltip: 'Add Text',
          ),
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: () {
              // Add image
            },
            tooltip: 'Add Image',
          ),
          ElevatedButton(
            onPressed: _saveEdits,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: widget.onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

