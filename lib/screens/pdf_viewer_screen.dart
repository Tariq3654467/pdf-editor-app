import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:async';
import '../services/pdf_service.dart';
import '../services/pdf_tools_service.dart';
import '../services/pdf_preferences_service.dart';
import '../services/pdf_text_editor_service.dart';
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
  bool _showPageIndicator = false;
  Timer? _hidePageIndicatorTimer;
  Timer? _scrollCheckTimer;
  bool _isScrolling = false;
  bool _showPagePreview = true; // Control visibility of page preview bar
  double _pdfScrollOffset = 0.0; // Track PDF vertical scroll offset for annotations
  int _pdfReloadKey = 0; // Key to force PDF viewer reload after modifications
  
  // Annotation/Editing state
  bool _isEditingMode = false;
  String _selectedTool = 'pen'; // 'pen', 'highlight', 'underline', 'eraser', 'text', 'none'
  Color _selectedColor = Colors.red;
  double _strokeWidth = 3.0;
  final GlobalKey<PDFAnnotationOverlayState> _annotationOverlayKey = GlobalKey<PDFAnnotationOverlayState>();
  bool _canUndo = false;
  bool _canRedo = false;
  
  // Text editing state (Sejda-style)
  Offset? _textEditPosition;
  String? _editingText;
  bool _isTextEditMode = false;
  List<TextAnnotation> _textAnnotations = []; // Instant text overlays (not saved to PDF yet)
  
  // View mode and orientation
  String _viewMode = 'vertical'; // 'vertical', 'horizontal', 'page'
  bool _isPortrait = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _pagePreviewScrollController = ScrollController();

  // Helper to determine when a drawing tool is really active
  bool get _isDrawingToolActive =>
      _isEditingMode &&
      (_selectedTool == 'pen' ||
       _selectedTool == 'highlight' ||
       _selectedTool == 'underline' ||
       _selectedTool == 'eraser');

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _loadPDFInfo();
    _autoBookmarkPDF();
    
    // Add listener to scroll controller to debug
    _pagePreviewScrollController.addListener(() {
      // This helps ensure the controller is working
    });
  }

  Future<void> _autoBookmarkPDF() async {
    // Automatically add PDF to bookmarks when opened
    try {
      final isBookmarked = await PDFPreferencesService.isBookmarked(widget.filePath);
      if (!isBookmarked) {
        // Auto-bookmark when PDF is opened for the first time
        await PDFPreferencesService.setBookmark(widget.filePath, true);
      }
      // Update last accessed time
      await PDFPreferencesService.setLastAccessed(widget.filePath);
    } catch (e) {
      print('Error auto-bookmarking PDF: $e');
    }
  }

  Future<void> _loadPDFInfo() async {
    final file = File(widget.filePath);
    if (await file.exists()) {
      final stat = await file.stat();
      final fileName = widget.fileName;
      final fileSize = PDFService.formatFileSize(stat.size);
      final modifiedDate = stat.modified;
      final date = PDFService.formatDate(modifiedDate);

      // Load bookmark status
      final isBookmarked = await PDFPreferencesService.isBookmarked(widget.filePath);
      
      setState(() {
        _isFavorite = isBookmarked;
        _pdfFileInfo = PDFFile(
          name: fileName,
          date: date,
          size: fileSize,
          isFavorite: isBookmarked,
          filePath: widget.filePath,
        );
      });
    }
  }


  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    setState(() {
      _totalPages = details.document.pages.count;
      _isLoading = false;
    });
    // Scroll to current page after document loads - use multiple callbacks to ensure it works
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToCurrentPage();
      }
    });
    // Also try after a longer delay to ensure the preview bar is fully built
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _scrollToCurrentPage();
      }
    });
  }

  void _onPageChanged(PdfPageChangedDetails details) {
    final newPage = details.newPageNumber;
    if (newPage != _currentPage) {
      setState(() {
        _currentPage = newPage;
        // Clear annotations when page changes (optional - you can remove this if you want annotations to persist)
      });
      // show page indicator briefly
      _hidePageIndicatorTimer?.cancel();
      setState(() {
        _showPageIndicator = true;
      });
      _hidePageIndicatorTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _showPageIndicator = false;
          });
        }
      });
      // Scroll to current page in preview bar (only if visible)
      if (_showPagePreview) {
        _scrollToCurrentPage();
      }
    }
  }

  void _scrollToCurrentPage() {
    // Try immediate scroll first, then with delay as fallback
    _performScroll();
    
    // Also try after a delay to ensure controller is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _performScroll();
      }
    });
    
    // One more attempt after longer delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _performScroll();
      }
    });
  }

  void _performScroll() {
    if (!mounted || _totalPages == 0) {
      return;
    }
    
    // Wait for scroll controller to be attached - retry if not ready
    if (!_pagePreviewScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _performScroll();
        }
      });
      return;
    }
    
    try {
      final thumbnailWidth = 60.0;
      final thumbnailMargin = 8.0;
      final totalThumbnailWidth = thumbnailWidth + thumbnailMargin;
      final screenWidth = MediaQuery.of(context).size.width;
      
      // Calculate the position of the current page thumbnail
      final pagePosition = (_currentPage - 1) * totalThumbnailWidth;
      
      // Calculate offset to center the current page
      final targetOffset = pagePosition - (screenWidth / 2) + (thumbnailWidth / 2);
      
      final maxScrollExtent = _pagePreviewScrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxScrollExtent > 0 ? maxScrollExtent : 0.0);
      
      // Only scroll if the target is different from current position
      final currentOffset = _pagePreviewScrollController.offset;
      if ((clampedOffset - currentOffset).abs() > 5) {
        _pagePreviewScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } catch (e) {
      print('Error in _performScroll: $e');
    }
  }

  void _goToPage(int pageNumber) {
    if (pageNumber >= 1 && pageNumber <= _totalPages) {
      setState(() {
        _currentPage = pageNumber;
        _showPagePreview = false; // Hide preview bar when page is clicked
      });
      _pdfViewerController.jumpToPage(pageNumber);
    }
  }

  void _startScrollCheckTimer() {
    _stopScrollCheckTimer(); // Stop any existing timer
    _scrollCheckTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isScrolling || !mounted) {
        _stopScrollCheckTimer();
        return;
      }
      _updateCurrentPageFromScroll();
    });
  }

  void _stopScrollCheckTimer() {
    _scrollCheckTimer?.cancel();
    _scrollCheckTimer = null;
  }

  void _updateCurrentPageFromScroll() {
    // Try to get the current page from the controller
    // The onPageChanged callback should be the primary source, but we check here as backup
    if (mounted) {
      try {
        // Try to access pageNumber property (may not exist in all versions)
        int? currentPageFromController;
        try {
          // Use reflection or direct access - if this fails, we'll catch it
          currentPageFromController = _pdfViewerController.pageNumber;
        } catch (_) {
          // pageNumber property might not be available, that's okay
          // We'll rely on onPageChanged callback instead
        }
        
        if (currentPageFromController != null && 
            currentPageFromController != _currentPage &&
            currentPageFromController >= 1 && 
            currentPageFromController <= _totalPages) {
          setState(() {
            _currentPage = currentPageFromController!;
          });
          // Show page indicator briefly
          _hidePageIndicatorTimer?.cancel();
          setState(() {
            _showPageIndicator = true;
          });
          _hidePageIndicatorTimer = Timer(const Duration(seconds: 1), () {
            if (mounted) {
              setState(() {
                _showPageIndicator = false;
              });
            }
          });
          // Scroll preview bar to show current page (only if visible)
          if (_showPagePreview) {
            _scrollToCurrentPage();
          }
        } else {
          // Even if page hasn't changed, ensure preview bar is in sync (only if visible)
          if (_showPagePreview) {
            _scrollToCurrentPage();
          }
        }
      } catch (e) {
        print('Error in _updateCurrentPageFromScroll: $e');
        // Fallback: just scroll the preview bar to keep it in sync
        _scrollToCurrentPage();
      }
    }
  }

  PdfScrollDirection _getScrollDirection() {
    switch (_viewMode) {
      case 'horizontal':
        return PdfScrollDirection.horizontal;
      case 'page':
        // For page-by-page interaction prefer horizontal swiping
        return PdfScrollDirection.horizontal;
      case 'vertical':
      default:
        return PdfScrollDirection.vertical;
    }
  }

  PdfPageLayoutMode _getPageLayoutMode() {
    switch (_viewMode) {
      case 'page':
        return PdfPageLayoutMode.single;
      case 'vertical':
      case 'horizontal':
      default:
        return PdfPageLayoutMode.continuous;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define colors based on dark mode
    final backgroundColor = _isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF424242);
    final iconColor = _isDarkMode ? Colors.white : const Color(0xFF424242);
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: iconColor,
            size: 24,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Page $_currentPage',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(
              Icons.search_outlined,
              color: iconColor,
              size: 24,
            ),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: Icon(
              _isPortrait ? Icons.screen_rotation_outlined : Icons.screen_lock_portrait_outlined,
              color: iconColor,
              size: 24,
            ),
            onPressed: _toggleOrientation,
          ),
          IconButton(
            icon: Icon(
              Icons.description_outlined,
              color: iconColor,
              size: 24,
            ),
            onPressed: _showViewModeBottomSheet,
          ),
          IconButton(
            icon: Icon(
              Icons.more_vert,
              color: iconColor,
              size: 24,
            ),
            onPressed: _showOptionsBottomSheet,
          ),
        ],
        iconTheme: IconThemeData(
          color: iconColor,
          size: 24,
        ),
      ),
      body: Stack(
        children: [
          // PDF Viewer with annotation overlay
          PDFAnnotationOverlay(
            key: _annotationOverlayKey,
            drawingColor: _getToolColor(),
            strokeWidth: _getStrokeWidth(),
            isDrawing: _isDrawingToolActive,
            isEraser: _selectedTool == 'eraser',
            toolType: _selectedTool,
            currentPage: _currentPage,
            scrollOffset: _pdfScrollOffset,
            textAnnotations: _textAnnotations,
            onTextTap: (textAnnotation) {
              // Allow editing text by tapping on it
              if (_isTextEditMode && _selectedTool == 'text') {
                _editTextAnnotation(textAnnotation);
              }
            },
            onClear: () {},
            onUndoStateChanged: (canUndo) {
              setState(() {
                _canUndo = canUndo;
              });
            },
            onRedoStateChanged: (canRedo) {
              setState(() {
                _canRedo = canRedo;
              });
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Detect when user scrolls manually and update preview bar
                if (notification is ScrollStartNotification) {
                  // Start periodic checks during scrolling
                  _isScrolling = true;
                  _startScrollCheckTimer();
                } else if (notification is ScrollUpdateNotification) {
                  // Update during scroll for real-time feedback
                  _isScrolling = true;
                  // Track scroll offset for annotation positioning
                  if (mounted) {
                    setState(() {
                      _pdfScrollOffset = notification.metrics.pixels;
                    });
                  }
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (mounted) {
                      _updateCurrentPageFromScroll();
                    }
                  });
                } else if (notification is ScrollEndNotification) {
                  // Stop periodic checks and do final update
                  _isScrolling = false;
                  _stopScrollCheckTimer();
                  // Update final scroll offset
                  if (mounted) {
                    setState(() {
                      _pdfScrollOffset = notification.metrics.pixels;
                    });
                  }
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (mounted) {
                      _updateCurrentPageFromScroll();
                    }
                  });
                }
                return false;
              },
              child: _isTextEditMode && _selectedTool == 'text'
                  ? GestureDetector(
                      onTapDown: (details) => _handleTextEditTap(details.localPosition),
                      behavior: HitTestBehavior.translucent, // Allow scroll gestures to pass through
                      child: SfPdfViewer.file(
                        File(widget.filePath),
                        key: ValueKey('pdf_viewer_${widget.filePath}_$_viewMode$_pdfReloadKey'), // Force rebuild when file changes
                        controller: _pdfViewerController,
                        onDocumentLoaded: _onDocumentLoaded,
                        onPageChanged: _onPageChanged,
                        scrollDirection: _getScrollDirection(),
                        pageLayoutMode: _getPageLayoutMode(),
                        enableDoubleTapZooming: true,
                        enableTextSelection: false, // Disable text selection when in text edit mode
                      ),
                    )
                  : SfPdfViewer.file(
                      File(widget.filePath),
                      key: ValueKey('pdf_viewer_${widget.filePath}_$_viewMode$_pdfReloadKey'), // Force rebuild when file changes
                      controller: _pdfViewerController,
                      onDocumentLoaded: _onDocumentLoaded,
                      onPageChanged: _onPageChanged,
                      scrollDirection: _getScrollDirection(),
                      pageLayoutMode: _getPageLayoutMode(),
                      enableDoubleTapZooming: true,
                      enableTextSelection: true,
                    ),
            ),
          ),
          // Page count indicator (briefly shown on page change)
          // Use IgnorePointer to ensure it doesn't block PDF scrolling
          Positioned(
            top: 16,
            left: 16,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showPageIndicator ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isDarkMode 
                        ? Colors.white.withOpacity(0.2) 
                        : Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_currentPage/$_totalPages',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
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
          : (_totalPages > 0 && _showPagePreview
              ? _buildPagePreviewBar()
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
          // Undo button
          _buildToolButton(
            icon: Icons.undo,
            label: 'Undo',
            isSelected: false,
            onTap: _canUndo
                ? () {
                  _annotationOverlayKey.currentState?.undo();
                }
                : null,
          ),
          // Redo button
          _buildToolButton(
            icon: Icons.redo,
            label: 'Redo',
            isSelected: false,
            onTap: _canRedo
                ? () {
                  _annotationOverlayKey.currentState?.redo();
                }
                : null,
          ),
          // Copy text button
          _buildToolButton(
            icon: Icons.content_copy,
            label: 'Copy',
            isSelected: false,
            onTap: () {
              _copySelectedText();
            },
          ),
          // Pen tool
          _buildToolButton(
            icon: Icons.edit,
            label: 'Pen',
            isSelected: _selectedTool == 'pen',
            onTap: () => setState(() => _selectedTool = 'pen'),
          ),
          // Highlight tool
          _buildToolButton(
            icon: Icons.highlight,
            label: 'Highlight',
            isSelected: _selectedTool == 'highlight',
            onTap: () => setState(() => _selectedTool = 'highlight'),
          ),
          // Underline tool
          _buildToolButton(
            icon: Icons.format_underline,
            label: 'Underline',
            isSelected: _selectedTool == 'underline',
            onTap: () => setState(() => _selectedTool = 'underline'),
          ),
          // Eraser tool
          _buildToolButton(
            icon: Icons.cleaning_services,
            label: 'Eraser',
            isSelected: _selectedTool == 'eraser',
            onTap: () => setState(() => _selectedTool = 'eraser'),
          ),
          // Text tool (Sejda-style: click to edit existing text or add new)
          _buildToolButton(
            icon: Icons.text_fields,
            label: 'Text',
            isSelected: _selectedTool == 'text',
            onTap: () {
              setState(() {
                _selectedTool = 'text';
                _isTextEditMode = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tap on text to edit it, or tap on empty space to add new text'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
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
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final buttonColor = color ?? (_selectedTool == 'pen' ? Colors.red : Colors.grey[700]!);
    final isEnabled = onTap != null;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
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
                color: isSelected ? buttonColor : (isEnabled ? Colors.grey[600] : Colors.grey[400]),
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? buttonColor : (isEnabled ? Colors.grey[600] : Colors.grey[400]),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ]),
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
    final backgroundColor = _isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF263238);
    final secondaryTextColor = _isDarkMode ? Colors.grey[400] : const Color(0xFF9E9E9E);
    
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.only(
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
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_pdfFileInfo!.date} • ${_pdfFileInfo!.size}',
                          style: TextStyle(
                            color: secondaryTextColor,
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
                          : secondaryTextColor,
                    ),
                    onPressed: () async {
                      final newBookmarkStatus = !_isFavorite;
                      await PDFPreferencesService.setBookmark(
                        widget.filePath,
                        newBookmarkStatus,
                      );
                      setState(() {
                        _isFavorite = newBookmarkStatus;
                        if (_pdfFileInfo != null) {
                          _pdfFileInfo = PDFFile(
                            name: _pdfFileInfo!.name,
                            date: _pdfFileInfo!.date,
                            size: _pdfFileInfo!.size,
                            isFavorite: newBookmarkStatus,
                            filePath: _pdfFileInfo!.filePath,
                          );
                        }
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
            icon: Icons.save_alt,
            title: 'Save to device',
            onTap: _saveToDevice,
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
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF263238);
    final iconColor = isDestructive ? Colors.red : textColor;
    
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : textColor,
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

  Future<void> _mergePDF() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Pick another PDF file to merge
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final selectedPdfPath = result.files.single.path!;
        
        // Merge the current PDF with the selected PDF
        final mergedPath = await PDFToolsService.mergePDFs([
          widget.filePath,
          selectedPdfPath,
        ]);

        // Close loading dialog
        if (mounted) {
          Navigator.pop(context);
        }

        if (mergedPath != null) {
          // Save to history
          await PDFPreferencesService.addToolsHistory(
            'merge',
            widget.filePath,
            resultPath: mergedPath,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PDFs merged successfully!'),
                duration: Duration(seconds: 2),
              ),
            );
            // Optionally navigate to the merged PDF or refresh
            // You can navigate to the new merged PDF if needed
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to merge PDFs. Please try again.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        // Close loading dialog if user cancelled
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      // Close loading dialog on error
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error merging PDFs: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _splitPDF() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Split PDF'),
        content: Text(
          'This will split "${widget.fileName}" into $_totalPages separate page files. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performSplitPDF();
            },
            child: const Text('Split'),
          ),
        ],
      ),
    );
  }

  Future<void> _performSplitPDF() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Split the PDF
      final splitFiles = await PDFToolsService.splitPDF(widget.filePath);

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      if (splitFiles.isNotEmpty) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'split',
          widget.filePath,
          resultPath: splitFiles.first,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF split successfully! Created ${splitFiles.length} page file(s).',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to split PDF. Please try again.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog on error
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error splitting PDF: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
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

  Future<void> _saveToDevice() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF file not found'),
            ),
          );
        }
        return;
      }

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

      // Try to save to app's external storage directory first (no permissions needed)
      // Then offer to share so user can save to Downloads if they want
      final fileName = path.basename(widget.filePath);
      Directory? targetDirectory;
      
      if (Platform.isAndroid) {
        // Use external storage directory (app-specific, no permissions needed)
        try {
          targetDirectory = await getExternalStorageDirectory();
          if (targetDirectory != null) {
            // Create a "Saved PDFs" subdirectory
            final savedPdfsDir = Directory('${targetDirectory.path}/Saved PDFs');
            if (!await savedPdfsDir.exists()) {
              await savedPdfsDir.create(recursive: true);
            }
            targetDirectory = savedPdfsDir;
          }
        } catch (e) {
          print('Error getting external storage: $e');
        }
      }
      
      // Fallback to app documents directory
      if (targetDirectory == null) {
        final appDocDir = await getApplicationDocumentsDirectory();
        final savedPdfsDir = Directory('${appDocDir.path}/Saved PDFs');
        if (!await savedPdfsDir.exists()) {
          await savedPdfsDir.create(recursive: true);
        }
        targetDirectory = savedPdfsDir;
      }

      // Ensure we have a valid directory
      if (targetDirectory == null) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not access device storage'),
            ),
          );
        }
        return;
      }

      // Copy file to target directory
      final targetPath = path.join(targetDirectory!.path, fileName);
      final targetFile = File(targetPath);
      await file.copy(targetPath);
      
      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }
      
      // Show success message and offer to share
      if (mounted) {
        final shouldShare = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('PDF Saved'),
            content: Text('PDF saved to:\n${targetDirectory!.path}\n\nWould you like to share it to save to Downloads?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No, thanks'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Share'),
              ),
            ],
          ),
        );
        
        if (shouldShare == true) {
          // Share the file so user can save to Downloads
          await Share.shareXFiles(
            [XFile(targetPath, name: fileName)],
            text: 'Save PDF: $fileName',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF saved to: ${targetDirectory!.path}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving PDF: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
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

  Future<void> _copySelectedText() async {
    try {
      // Syncfusion PDF viewer handles text selection natively
      // Users can select text by long-pressing and dragging
      // Once text is selected, they can copy it using the system's copy option
      // This button provides instructions on how to copy text
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Copy Text'),
            content: const Text(
              'To copy text from the PDF:\n\n'
              '1. Long press on the text you want to copy\n'
              '2. Drag to select the desired text\n'
              '3. Use the system copy option from the context menu that appears\n\n'
              'Text selection is enabled in the PDF viewer. The selected text will be automatically available for copying through the system menu.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleTextEditTap(Offset position) async {
    if (!_isTextEditMode || _selectedTool != 'text') return;
    
    // First check if user tapped on an existing text overlay
    final screenSize = MediaQuery.of(context).size;
    final tappedText = _textAnnotations.firstWhere(
      (textAnnotation) {
        if (textAnnotation.pageNumber != _currentPage) return false;
        final screenX = textAnnotation.position.dx * screenSize.width;
        final screenY = textAnnotation.documentY != null
            ? textAnnotation.documentY! - _pdfScrollOffset
            : textAnnotation.position.dy * screenSize.height;
        
        // Check if tap is within text bounds (approximate - text width based on length)
        final textWidth = textAnnotation.text.length * textAnnotation.fontSize * 0.6;
        final textHeight = textAnnotation.fontSize;
        final textRect = Rect.fromLTWH(
          screenX - 5,
          screenY - 5,
          textWidth + 10,
          textHeight + 10,
        );
        return textRect.contains(position);
      },
      orElse: () => TextAnnotation(
        text: '',
        position: Offset.zero,
        color: Colors.black,
        pageNumber: -1,
      ),
    );
    
    if (tappedText.pageNumber == _currentPage && tappedText.text.isNotEmpty) {
      // Edit existing text overlay
      _editTextAnnotation(tappedText);
      return;
    }
    
    // No existing text found - add new text at tap position
    _showTextEditDialog(
      initialText: '',
      position: position,
      isEditing: false,
    );
  }
  
  void _editTextAnnotation(TextAnnotation textAnnotation) {
    _showTextEditDialog(
      initialText: textAnnotation.id, // Use ID to identify which annotation to edit
      position: Offset(
        textAnnotation.position.dx * MediaQuery.of(context).size.width,
        textAnnotation.documentY != null
            ? textAnnotation.documentY! - _pdfScrollOffset
            : textAnnotation.position.dy * MediaQuery.of(context).size.height,
      ),
      isEditing: true,
      existingAnnotation: textAnnotation,
    );
  }

  void _showTextEditDialog({
    required String initialText,
    required Offset position,
    required bool isEditing,
    TextAnnotation? existingAnnotation,
  }) {
    final textController = TextEditingController(
      text: existingAnnotation?.text ?? initialText,
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Text' : 'Add Text'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Enter text',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isTextEditMode = false;
                _selectedTool = 'none';
              });
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newText = textController.text.trim();
              
              // Validate: don't allow empty text when adding new
              if (!isEditing && newText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter some text'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              
              Navigator.pop(context);
              
              if (isEditing && existingAnnotation != null) {
                // Update existing text annotation
                final index = _textAnnotations.indexWhere((t) => t.id == existingAnnotation.id);
                if (index != -1) {
                  setState(() {
                    if (newText.isEmpty) {
                      // Remove if text is empty
                      _textAnnotations.removeAt(index);
                    } else {
                      // Update text
                      _textAnnotations[index] = TextAnnotation(
                        text: newText,
                        position: existingAnnotation.position,
                        color: existingAnnotation.color,
                        fontSize: existingAnnotation.fontSize,
                        pageNumber: existingAnnotation.pageNumber,
                        documentY: existingAnnotation.documentY,
                        id: existingAnnotation.id,
                      );
                    }
                  });
                }
              } else {
                // Add new text annotation instantly (Sejda-style - no PDF save)
                final normalizedPosition = Offset(
                  position.dx / MediaQuery.of(context).size.width,
                  position.dy / MediaQuery.of(context).size.height,
                );
                
                setState(() {
                  _textAnnotations.add(TextAnnotation(
                    text: newText,
                    position: normalizedPosition,
                    color: _selectedColor,
                    fontSize: 12.0,
                    pageNumber: _currentPage,
                    documentY: position.dy + _pdfScrollOffset,
                  ));
                });
              }
              
              // Reset text edit mode
              setState(() {
                _isTextEditMode = false;
                _selectedTool = 'none';
              });
            },
            child: Text(isEditing ? 'Update' : 'Add'),
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
        title: const Text('Add Text Annotation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter text to add as annotation. The text will be added to the current page.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter text to add',
                border: OutlineInputBorder(),
                labelText: 'Text',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
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
                // For now, show a message. In future, this could add text annotation
                // to the PDF at the current page position
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Text annotation "${textController.text}" will be added. Use Pen tool to draw text annotations.'),
                    duration: const Duration(seconds: 3),
                  ),
                );
                // Note: True text editing (like Sejda) requires PDF text extraction
                // and manipulation which is complex. For now, users can use the Pen tool
                // to write text manually or use text selection to copy existing text.
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search in PDF'),
        content: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Enter text to search',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              _pdfViewerController.searchText(value);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              _searchController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_searchController.text.isNotEmpty) {
                _pdfViewerController.searchText(_searchController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  void _toggleOrientation() async {
    setState(() {
      _isPortrait = !_isPortrait;
    });
    
    // Actually change the device orientation
    if (_isPortrait) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    // Reset orientation to allow all orientations when leaving the screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _pdfViewerController.dispose();
    _searchController.dispose();
    _pagePreviewScrollController.dispose();
    _hidePageIndicatorTimer?.cancel();
    _stopScrollCheckTimer();
    super.dispose();
  }

  void _showViewModeBottomSheet() {
    final backgroundColor = _isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF263238);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.only(
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
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'View mode',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            _buildViewModeOption(
              icon: Icons.view_column,
              title: 'Vertical scroll',
              value: 'vertical',
            ),
            _buildViewModeOption(
              icon: Icons.view_agenda,
              title: 'Horizontal scroll',
              value: 'horizontal',
            ),
            _buildViewModeOption(
              icon: Icons.view_module,
              title: 'Page by page',
              value: 'page',
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeOption({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final isSelected = _viewMode == value;
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF263238);
    final unselectedColor = _isDarkMode ? Colors.grey[400] : const Color(0xFF9E9E9E);
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFFE53935) : unselectedColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? textColor : unselectedColor,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Radio<String>(
        value: value,
        groupValue: _viewMode,
        onChanged: (newValue) {
          final currentPage = _currentPage;
          setState(() {
            _viewMode = newValue!;
          });
          Navigator.pop(context);
          // Restore current page after view mode change
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && currentPage >= 1 && currentPage <= _totalPages) {
              _pdfViewerController.jumpToPage(currentPage);
            }
          });
        },
        activeColor: const Color(0xFFE53935),
      ),
      onTap: () {
        final currentPage = _currentPage;
        setState(() {
          _viewMode = value;
        });
        Navigator.pop(context);
        // Restore current page after view mode change
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && currentPage >= 1 && currentPage <= _totalPages) {
            _pdfViewerController.jumpToPage(currentPage);
          }
        });
      },
    );
  }

  Widget _buildPagePreviewBar() {
    // Show all pages that can fit in the screen width
    final thumbnailWidth = 60.0; // Width of each thumbnail
    
    // Show all pages in a scrollable list
    return Container(
      height: 100,
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
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _totalPages,
        controller: _pagePreviewScrollController,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final pageNumber = index + 1;
          final isActive = _currentPage == pageNumber;
          return GestureDetector(
            onTap: () => _goToPage(pageNumber),
            child: Container(
              width: thumbnailWidth,
              height: 80,
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
                  // Page thumbnail
                  SizedBox(
                    width: 40,
                    height: 50,
                    child: _buildPageThumbnail(pageNumber, isActive),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$pageNumber',
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFFE53935)
                          : Colors.grey[600],
                      fontSize: 10,
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
    );
  }

  Widget _buildPageThumbnail(int pageNumber, bool isActive) {
    return Container(
      width: 40,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? const Color(0xFFE53935) : Colors.grey[300]!,
          width: isActive ? 1.5 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Actual PDF page thumbnail using small viewer
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _PDFThumbnailViewer(
                filePath: widget.filePath,
                pageNumber: pageNumber,
              ),
            ),
          ),
          // Page number at top
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '$pageNumber',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget to display a single PDF page as thumbnail
class _PDFThumbnailViewer extends StatefulWidget {
  final String filePath;
  final int pageNumber;

  const _PDFThumbnailViewer({
    required this.filePath,
    required this.pageNumber,
  });

  @override
  State<_PDFThumbnailViewer> createState() => _PDFThumbnailViewerState();
}

class _PDFThumbnailViewerState extends State<_PDFThumbnailViewer> {
  late PdfViewerController _controller;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    // Jump to the specific page after a short delay
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
      color: Colors.white,
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
          : Container(
              color: Colors.grey[200],
              child: const Center(
                child: SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1,
                  ),
                ),
              ),
            ),
    );
  }
}

