import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import '../services/pdf_service.dart';
import '../services/pdf_tools_service.dart';
import '../services/pdf_preferences_service.dart';
import '../services/pdf_text_editor_service.dart';
import '../services/pdf_cache_service.dart';
import '../services/theme_service.dart';
import '../models/pdf_file.dart';
import '../widgets/pdf_annotation_overlay.dart';
import '../widgets/pdf_text_formatting_toolbar.dart';
import '../models/selected_pdf_text.dart';
import '../services/pdf_text_selection_service.dart';
import '../services/mupdf_editor_service.dart';
import '../services/pdf_inline_text_editor_service.dart';
import '../services/pdf_save_service.dart';
import '../widgets/in_app_file_picker.dart';
import '../widgets/text_aware_annotation_overlay.dart';
import '../models/pdf_annotation.dart' as app_models;
import '../services/annotation_storage_service.dart';

/// Active tool for the bottom annotation toolbar
enum PdfTool {
  none,
  copy,
  pen,
  highlight,
  underline,
  strike, // Strikethrough
  eraser, // kept for compatibility, not shown in toolbar
  editText, // Edit existing text (enables text selection)
}

/// Cursor type for desktop/web (conceptual on mobile)
enum CursorType {
  none,          // Default cursor
  text,          // I-beam for text selection/editing
  pen,           // Freehand drawing cursor
  underline,     // Underline tool
  highlight,     // Highlight tool
  strikeThrough, // Strike-through tool
}

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
  bool _isFavorite = false;
  PDFFile? _pdfFileInfo;
  bool _showPageIndicator = false;
  Timer? _hidePageIndicatorTimer;
  Timer? _scrollCheckTimer;
  Timer? _pdfReloadDebounceTimer; // Debounce timer for PDF reloads
  bool _isScrolling = false;
  bool _showPagePreview = true; // Control visibility of page preview bar
  double _pdfScrollOffsetY = 0.0; // Track PDF vertical scroll offset (pixels) from SfPdfViewer callback
  int _pdfReloadKey = 0; // Key to force PDF viewer reload after modifications
  bool _isSavingAnnotation = false; // Prevent multiple simultaneous saves
  DateTime? _lastReloadTime; // Track last reload time to prevent excessive reloads
  
  // Text-aware annotation system
  Size? _pdfPageSize; // PDF page size in points (fallback for first page)
  List<Size> _pdfPageSizes = []; // Per-page sizes in points (supports varying page sizes)
  double _zoomLevel = 1.0;
  static const double _pageSpacing = 8.0; // MUST match SfPdfViewer.pageSpacing
  List<app_models.PDFAnnotation> _savedAnnotations = [];
  final AnnotationStorageService _annotationStorage = AnnotationStorageService();
  
  // Undo/Redo for Syncfusion annotations (highlight, underline, strikethrough)
  List<Uint8List> _annotationHistory = []; // Store PDF document bytes as snapshots
  int _historyIndex = -1; // Current position in history (-1 means no history)
  double? _savedZoomLevel; // Store zoom level before Copy tool zoom
  Timer? _annotationSaveTimer; // Timer to save state after annotation is created
  PdfTool? _previousTool; // Track previous tool to detect when annotation is finished
  
  // Error handling
  String? _errorMessage;
  String? _actualFilePath; // May differ from widget.filePath if content URI was copied
  Timer? _loadingTimeoutTimer;
  static const MethodChannel _fileChannel = MethodChannel('com.example.pdf_editor_app/file_intent');
  
  // Annotation/Editing state
  bool _isEditingMode = false;
  bool _isContentEditMode = false; // True content editing mode (Sejda-style)
  PdfTool _selectedTool = PdfTool.none;
  // Internal string mode used by overlays/text editor: 'pen', 'highlight', 'underline', 'eraser', 'text', 'none'
  String _selectedMode = 'none';
  Color _selectedColor = Colors.red;
  double _strokeWidth = 3.0;
  final GlobalKey<PDFAnnotationOverlayState> _annotationOverlayKey = GlobalKey<PDFAnnotationOverlayState>();
  final GlobalKey<TextAwareAnnotationOverlayState> _textAwareOverlayKey = GlobalKey<TextAwareAnnotationOverlayState>();
  bool _canUndo = false;
  bool _canRedo = false;
  
  // Text editing state (Sejda-style)
  Offset? _textEditPosition;
  String? _editingText;
  bool _isTextEditMode = false;
  List<TextAnnotation> _textAnnotations = []; // Instant text overlays (not saved to PDF yet)
  
  // Text selection state (Sejda-style - select existing text to edit)
  SelectedPDFText? _selectedPDFText;
  String? _selectedPDFTextObjectId; // MuPDF object ID for text replacement
  
  // Cache for text detection to avoid repeated lookups
  final Map<String, dynamic> _textDetectionCache = {};
  static const int _maxCacheSize = 50; // Limit cache size
  Offset? _textSelectionToolbarPosition;
  bool _showTextFormattingToolbar = false;
  bool _isScannedDocument = false; // Track if PDF is scanned (image-based)
  
  // Text editing undo/redo state
  final _TextEditorController _textEditorController = _TextEditorController();
  bool _canUndoText = false;
  bool _canRedoText = false;

  // Cursor state (desktop/web)
  CursorType _cursorType = CursorType.none;

  // Add-text tool state ("T" tool)
  bool _isAddTextToolActive = false;
  
  // Text selection state (for Syncfusion built-in text selection)
  String? _syncfusionSelectedText; // Text selected via Syncfusion's built-in selection
  Rect? _syncfusionSelectionBounds; // Bounds of selected text
  int? _syncfusionSelectionPage; // Page number where text is selected
  bool _showFloatingTextToolbar = false; // Show floating Edit/Copy/Delete toolbar
  Offset? _floatingToolbarPosition; // Position for floating toolbar
  Timer? _textSelectionCheckTimer; // Timer to check for text selection
  Offset? _lastTapPosition; // Last tap position for editText tool
  DateTime? _lastTapTime; // Last tap time for editText tool
  
  // Edit Text mode: All text objects for highlighting
  List<PDFInlineTextObject>? _allEditableTextObjects; // All text objects on current page
  int? _editableTextPageIndex; // Page index for which text objects are loaded
  bool _isLoadingEditableText = false; // Loading state for text extraction

  // Enable text editing mode (used by main FAB)
  void _enableTextEditing() {
    setState(() {
      _isEditingMode = true;
      _selectedMode = 'text';
      _isTextEditMode = true;
      _cursorType = CursorType.text;
    });
  }

  // Map logical CursorType to a SystemMouseCursor (no-op on mobile)
  MouseCursor _getSystemCursorForType() {
    switch (_cursorType) {
      case CursorType.text:
        return SystemMouseCursors.text;
      case CursorType.pen:
        return SystemMouseCursors.precise;
      case CursorType.underline:
      case CursorType.highlight:
      case CursorType.strikeThrough:
        return SystemMouseCursors.click;
      case CursorType.none:
      default:
        return SystemMouseCursors.basic;
    }
  }
  
  
  // View mode and orientation
  String _viewMode = 'vertical'; // 'vertical', 'horizontal', 'page'
  bool _isPortrait = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _pagePreviewScrollController = ScrollController();

  // Helper to determine when a drawing tool is really active
  bool get _isDrawingToolActive =>
      _isEditingMode &&
      (_selectedTool == PdfTool.pen ||
       _selectedTool == PdfTool.highlight ||
       _selectedTool == PdfTool.underline ||
       _selectedTool == PdfTool.eraser);

  /// Map the active [PdfTool] to the overlay's string-based tool id
  String? get _selectedOverlayTool {
    if (!_isEditingMode) return null;
    switch (_selectedTool) {
      case PdfTool.pen:
        return 'pen';
      case PdfTool.strike:
        // Strikethrough uses Syncfusion annotationMode only, no overlay
        return null;
      case PdfTool.eraser:
        return 'eraser';
      case PdfTool.highlight:
      case PdfTool.underline:
      case PdfTool.copy:
      case PdfTool.editText:
      case PdfTool.none:
        // Highlight/underline use Syncfusion annotationMode (accurate alignment)
        // Copy/editText/none should not block PDF viewer gestures
        return null;
    }
  }

  /// Central place to activate a tool and keep state in sync
  void _selectTool(PdfTool tool) {
    // Initialize undo/redo history when entering edit mode for the first time
    if (!_isEditingMode && tool != PdfTool.none && _annotationHistory.isEmpty) {
      // Save initial state when first entering edit mode (async, don't await)
      _saveAnnotationState();
    }

    setState(() {
      _selectedTool = tool;
      _isEditingMode = tool != PdfTool.none;

      // Map enum to internal string mode for existing overlays/text editor
      switch (tool) {
        case PdfTool.copy:
          _selectedMode = 'none';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          // Auto-zoom for easier text selection
          _zoomInForSelection();
          _cursorType = CursorType.text;
          break;
        case PdfTool.pen:
          // Custom overlay pen drawing, disable SfPdfViewer annotations
          _selectedMode = 'pen';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          _cursorType = CursorType.pen;
          break;
        case PdfTool.highlight:
          _selectedMode = 'none';
          // Save state before applying annotation for undo/redo
          _saveStateBeforeAnnotation();
          _pdfViewerController.annotationMode = PdfAnnotationMode.highlight;
          // Set up listener to save state after annotation is created
          _setupAnnotationCompletionListener();
          _cursorType = CursorType.highlight;
          break;
        case PdfTool.underline:
          _selectedMode = 'none';
          // Save state before applying annotation for undo/redo
          _saveStateBeforeAnnotation();
          _pdfViewerController.annotationMode = PdfAnnotationMode.underline;
          // Set up listener to save state after annotation is created
          _setupAnnotationCompletionListener();
          _cursorType = CursorType.underline;
          break;
        case PdfTool.strike:
          _selectedMode = 'none';
          // Save state before applying annotation for undo/redo
          _saveStateBeforeAnnotation();
          _pdfViewerController.annotationMode = PdfAnnotationMode.strikethrough;
          // Set up listener to save state after annotation is created
          _setupAnnotationCompletionListener();
          _cursorType = CursorType.strikeThrough;
          break;
        case PdfTool.eraser:
          _selectedMode = 'eraser';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          _cursorType = CursorType.none;
          break;
        case PdfTool.editText:
          _selectedMode = 'text';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          _cursorType = CursorType.text;
          // Start checking for text selection
          _startTextSelectionCheck();
          // Load all text objects for highlighting when edit mode is activated
          _loadAllTextObjectsForEditing();
          break;
        case PdfTool.none:
          _selectedMode = 'none';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          _cursorType = CursorType.none;
          // Stop checking for text selection
          _stopTextSelectionCheck();
          break;
      }

      // Exiting any text-editing mode when switching tools
      _isTextEditMode = false;
      _selectedPDFText = null;
      _showTextFormattingToolbar = false;
      _showFloatingTextToolbar = false;
      _syncfusionSelectedText = null;
      _syncfusionSelectionBounds = null;
      _syncfusionSelectionPage = null;
      _floatingToolbarPosition = null;
      _isAddTextToolActive = false;
      // Note: Syncfusion's text selection will be cleared automatically when user interacts with PDF

      // Save state after annotation is created (when switching away from annotation tool)
      if (_previousTool != null && 
          (_previousTool == PdfTool.highlight || 
           _previousTool == PdfTool.underline || 
           _previousTool == PdfTool.strike) &&
          tool != _previousTool) {
        // User switched away from annotation tool, save state after annotation was created
        _saveStateAfterAnnotation();
      }

      _previousTool = tool;

      // Whenever switching tools, turn off add-text mode
      _isAddTextToolActive = false;
    });
  }

  /// Persist Syncfusion annotations (highlight/underline) to PDF file
  Future<void> _persistViewerAnnotations() async {
    try {
      final filePath = _actualFilePath ?? widget.filePath;
      if (filePath.isEmpty) {
        print('_persistViewerAnnotations: No file path available');
        return;
      }

      print('_persistViewerAnnotations: Saving Syncfusion annotations to $filePath');
      
      // Save document with annotations
      // saveDocument returns List<int>, convert to Uint8List
      List<int>? bytesList;
      try {
        // Try saveDocument without parameters first (PdfFlattenOption may not exist in this version)
        bytesList = await _pdfViewerController.saveDocument();
      } catch (e) {
        print('_persistViewerAnnotations: saveDocument failed: $e');
        return;
      }
      
      if (bytesList == null || bytesList.isEmpty) {
        print('_persistViewerAnnotations: saveDocument returned null or empty bytes');
        return;
      }
      
      final bytes = Uint8List.fromList(bytesList);
      
      // Write bytes back to the same file
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      
      print('_persistViewerAnnotations: Successfully saved ${bytes.length} bytes to $filePath');
    } catch (e) {
      // Non-fatal error - log but don't crash
      print('_persistViewerAnnotations: Error saving Syncfusion annotations: $e');
    }
  }


  /// Zoom in when Copy tool is activated for easier text selection
  void _zoomInForSelection() {
    // Save current zoom level to restore later
    _savedZoomLevel = _pdfViewerController.zoomLevel;
    
    // Zoom in to 2.0x for easier text selection
    _pdfViewerController.zoomLevel = 2.0;
    
    // Show prompt message
    _showZoomDemoMessage();
  }

  /// Show demo message for text selection
  void _showZoomDemoMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Zooming in for easier text selection. Long press to select text!'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Save state BEFORE annotation tool is selected (to enable undo)
  Future<void> _saveStateBeforeAnnotation() async {
    // Cancel any pending save timer
    _annotationSaveTimer?.cancel();
    
    // Save current state before annotation is created
    await _saveAnnotationState();
  }

  /// Set up listener to detect when annotation is completed
  void _setupAnnotationCompletionListener() {
    // Cancel any existing timer
    _annotationSaveTimer?.cancel();
    
    // We'll save state when user switches tools or when annotation mode changes
    // This is handled in _selectTool when switching away from annotation tool
  }

  /// Save state AFTER annotation is created (when user switches tools or annotation completes)
  void _saveStateAfterAnnotation() {
    // Cancel any pending timer
    _annotationSaveTimer?.cancel();
    
    // Use a short delay to ensure annotation is saved to document
    _annotationSaveTimer = Timer(const Duration(milliseconds: 800), () async {
      await _saveAnnotationState();
    });
  }

  /// Save current PDF document state for undo/redo
  Future<void> _saveAnnotationState() async {
    try {
      // Get current document bytes
      List<int>? bytesList = await _pdfViewerController.saveDocument();
      if (bytesList == null || bytesList.isEmpty) {
        print('_saveAnnotationState: Failed to get document bytes');
        return;
      }

      final bytes = Uint8List.fromList(bytesList);

      // Verify bytes are valid PDF (should start with %PDF)
      if (bytes.length < 4 || 
          String.fromCharCodes(bytes.take(4)) != '%PDF') {
        print('_saveAnnotationState: Invalid PDF bytes, not saving');
        return;
      }

      // Remove any future history if we're not at the end
      if (_historyIndex < _annotationHistory.length - 1) {
        _annotationHistory = _annotationHistory.sublist(0, _historyIndex + 1);
      }

      // Add current state to history
      _annotationHistory.add(bytes);
      _historyIndex++;

      // Limit history size to prevent memory issues (keep last 50 states)
      if (_annotationHistory.length > 50) {
        _annotationHistory.removeAt(0);
        _historyIndex--;
      }

      // Update undo/redo button states
      setState(() {
        _canUndo = _historyIndex > 0;
        _canRedo = false; // Can't redo after a new action
      });

      print('_saveAnnotationState: Saved state at index $_historyIndex (total: ${_annotationHistory.length}), size: ${bytes.length} bytes');
    } catch (e) {
      print('_saveAnnotationState: Error saving state: $e');
    }
  }

  /// Undo last annotation change
  Future<void> _undo() async {
    if (_historyIndex <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to undo'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    try {
      _historyIndex--;
      final previousState = _annotationHistory[_historyIndex];

      // Restore document from saved state
      await _restoreDocumentState(previousState);

      setState(() {
        _canUndo = _historyIndex > 0;
        _canRedo = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Undone'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      print('_undo: Error restoring state: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error undoing: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Redo last undone annotation change
  Future<void> _redo() async {
    if (_historyIndex >= _annotationHistory.length - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to redo'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    try {
      _historyIndex++;
      final nextState = _annotationHistory[_historyIndex];

      // Restore document from saved state
      await _restoreDocumentState(nextState);

      setState(() {
        _canUndo = true;
        _canRedo = _historyIndex < _annotationHistory.length - 1;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Redone'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      print('_redo: Error restoring state: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error redoing: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Restore PDF document from saved bytes
  Future<void> _restoreDocumentState(Uint8List bytes) async {
    try {
      final filePath = _actualFilePath ?? widget.filePath;
      if (filePath.isEmpty) {
        print('_restoreDocumentState: No file path available');
        return;
      }

      print('_restoreDocumentState: Starting restore, file size: ${bytes.length} bytes');

      // Cancel any pending annotation save timers
      _annotationSaveTimer?.cancel();

      // Reset annotation mode and close viewer
      _pdfViewerController.annotationMode = PdfAnnotationMode.none;

      // First, force close the PDF viewer by incrementing reload key
      // This ensures the file is released before we write to it
      if (mounted) {
        setState(() {
          _selectedTool = PdfTool.none;
          _selectedMode = 'none';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          // Increment key to close current viewer
          _pdfReloadKey++;
        });
      }

      // Wait longer for viewer to completely close and release file handle
      await Future.delayed(const Duration(milliseconds: 400));

      // Write bytes to file with explicit flush
      final file = File(filePath);
      final raf = await file.open(mode: FileMode.write);
      try {
        await raf.writeFrom(bytes);
        await raf.flush();
        await raf.close();
      } catch (e) {
        await raf.close();
        rethrow;
      }

      // Force file system sync
      await file.writeAsBytes(bytes, flush: true);

      // Wait for file system to fully sync
      await Future.delayed(const Duration(milliseconds: 400));

      print('_restoreDocumentState: File written, reloading viewer...');

      // Force complete reload of the PDF viewer with new file
      if (mounted) {
        setState(() {
          // Increment reload key again to force complete reload with new file
          _pdfReloadKey++;
        });
      }

      // Wait longer for viewer to fully reload
      await Future.delayed(const Duration(milliseconds: 500));

      print('_restoreDocumentState: Restored document from ${bytes.length} bytes, reloadKey: $_pdfReloadKey');
    } catch (e) {
      print('_restoreDocumentState: Error restoring document: $e');
      // Fallback: try simpler approach
      try {
        // Reset state first
        if (mounted) {
          setState(() {
            _selectedTool = PdfTool.none;
            _selectedMode = 'none';
            _pdfViewerController.annotationMode = PdfAnnotationMode.none;
            _pdfReloadKey++;
          });
        }
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        final file = File(_actualFilePath ?? widget.filePath);
        await file.writeAsBytes(bytes, flush: true);
        
        await Future.delayed(const Duration(milliseconds: 400));
        
        if (mounted) {
          setState(() {
            _pdfReloadKey++;
          });
        }
        
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e2) {
        print('_restoreDocumentState: Fallback also failed: $e2');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error restoring: ${e2.toString()}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// Handle tapping the Done button: persist annotations & exit edit mode
  Future<void> _onDoneEditing() async {
    // Cancel any pending debounced reloads
    _pdfReloadDebounceTimer?.cancel();
    
    // Cancel any pending annotation save timer
    _annotationSaveTimer?.cancel();
    
    // Save final state if user was using annotation tool
    if (_previousTool != null && 
        (_previousTool == PdfTool.highlight || 
         _previousTool == PdfTool.underline || 
         _previousTool == PdfTool.strike)) {
      await _saveAnnotationState();
    }

    // Restore zoom level if it was changed for Copy tool
    if (_savedZoomLevel != null) {
      _pdfViewerController.zoomLevel = _savedZoomLevel!;
      _savedZoomLevel = null;
    }

    // Persist Syncfusion annotations (highlight/underline) BEFORE exiting edit mode
    await _persistViewerAnnotations();

    // Persist custom overlay annotations snapshot via storage service if possible
    try {
      if (_actualFilePath != null && _savedAnnotations.isNotEmpty) {
        await _annotationStorage.saveAnnotations(_actualFilePath!, _savedAnnotations);
      }
    } catch (e) {
      // Non-fatal; we still exit edit mode but log the error
      print('Error saving overlay annotations on Done: $e');
    }

    if (!mounted) return;

    setState(() {
      _isEditingMode = false;
      _selectedTool = PdfTool.none;
      _selectedMode = 'none';
      _pdfViewerController.annotationMode = PdfAnnotationMode.none;
      // Clear undo/redo history when exiting edit mode
      _annotationHistory.clear();
      _historyIndex = -1;
      _canUndo = false;
      _canRedo = false;
      // Reload PDF when exiting edit mode to show all saved annotations
      _pdfReloadKey++;
    });

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All changes saved'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Start checking for text selection (when editText tool is active)
  void _startTextSelectionCheck() {
    _stopTextSelectionCheck(); // Stop any existing timer
    _textSelectionCheckTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      _checkForTextSelection();
    });
  }

  /// Stop checking for text selection
  void _stopTextSelectionCheck() {
    _textSelectionCheckTimer?.cancel();
    _textSelectionCheckTimer = null;
  }

  /// Check if text is currently selected in Syncfusion PDF viewer
  void _checkForTextSelection() {
    if (_selectedTool != PdfTool.editText || !mounted) return;
    
    try {
      // Try to get selected text from controller
      // Note: Syncfusion may not expose this directly, so we'll use a workaround
      // We'll detect selection by checking if user has selected text via long-press
      // For now, we'll use the tap-based detection as fallback
      
      // The actual implementation would need to use Syncfusion's text selection API
      // Since that's not directly available, we'll rely on the tap-based detection
      // which already works well
    } catch (e) {
      print('Error checking text selection: $e');
    }
  }

  /// Handle when user taps on selected text (shows floating toolbar)
  void _onSelectedTextTapped(Offset position) {
    if (_syncfusionSelectedText == null || _syncfusionSelectedText!.isEmpty) return;
    
    setState(() {
      _showFloatingTextToolbar = true;
      // Position toolbar near the tap position
      final screenSize = MediaQuery.of(context).size;
      _floatingToolbarPosition = Offset(
        position.dx.clamp(16.0, screenSize.width - 200),
        (position.dy - 80).clamp(16.0, screenSize.height - 200),
      );
    });
  }

  /// Handle Edit button from floating toolbar
  void _onFloatingEditPressed() {
    if (_syncfusionSelectedText == null || _syncfusionSelectedText!.isEmpty) return;
    if (_syncfusionSelectionBounds == null || _syncfusionSelectionPage == null) return;
    
    // Convert Syncfusion selection to our SelectedPDFText format
    // Create SelectedPDFText from the selected text
    setState(() {
      _showFloatingTextToolbar = false;
      
      // Create SelectedPDFText object for formatting toolbar
      _selectedPDFText = SelectedPDFText(
        text: _syncfusionSelectedText!,
        bounds: _syncfusionSelectionBounds!,
        pageIndex: _syncfusionSelectionPage!,
        position: _syncfusionSelectionBounds!.topLeft,
        fontSize: 12.0,
        color: Colors.black,
        fontFamily: null,
        isBold: false,
        isItalic: false,
        isUnderline: false,
      );
      
      // Initialize text editor controller
      _textEditorController.setInitialText(_syncfusionSelectedText!);
      
      // Show formatting toolbar at bottom
      _showTextFormattingToolbar = true;
      _isTextEditMode = true;
      _selectedMode = 'text';
      
      // Update undo/redo state
      _canUndoText = _textEditorController.canUndo;
      _canRedoText = _textEditorController.canRedo;
    });
    
    // objectId is already stored when floating toolbar was shown (in _handlePDFTextTap)
  }

  /// Handle Copy button from floating toolbar
  void _onFloatingCopyPressed() {
    if (_syncfusionSelectedText == null || _syncfusionSelectedText!.isEmpty) return;
    
    Clipboard.setData(ClipboardData(text: _syncfusionSelectedText!));
    setState(() {
      _showFloatingTextToolbar = false;
      _syncfusionSelectedText = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Text copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Handle Delete button from floating toolbar
  void _onFloatingDeletePressed() {
    if (_syncfusionSelectedText == null || _syncfusionSelectedText!.isEmpty) return;
    
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Text'),
        content: const Text('Are you sure you want to delete the selected text?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Delete text by replacing with empty string
              if (_syncfusionSelectionBounds != null && _syncfusionSelectionPage != null) {
                final tapPosition = _syncfusionSelectionBounds!.center;
                // This will be handled by the text editing flow
                setState(() {
                  _showFloatingTextToolbar = false;
                  _syncfusionSelectedText = null;
                });
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    
    // Add listener to scroll controller
    _pagePreviewScrollController.addListener(() {
      // This helps ensure the controller is working
    });
    
    // CRITICAL FIX: Delay initialization to prevent crashes on Samsung devices
    // Widget must be fully built before starting heavy file operations
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      try {
        _initializePDF();
        // Auto-bookmark in background (non-blocking)
        _autoBookmarkPDF().catchError((e) {
          print('Error auto-bookmarking: $e');
        });
      } catch (e, stackTrace) {
        print('Error in delayed init: $e');
        print('Stack trace: $stackTrace');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Error initializing PDF viewer. Please try again.';
          });
        }
      }
    });
    
    // Set loading timeout (30 seconds for large PDFs - reduced for Samsung)
    _loadingTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _isLoading && _actualFilePath != null) {
        print('PDFViewer: Loading timeout after 30 seconds');
        setState(() {
          _isLoading = false;
          _errorMessage = 'PDF took too long to load. The file might be very large. Please try again.';
        });
      }
    });
  }
  
  @override
  void dispose() {
    // Cancel all timers
    _stopTextSelectionCheck();
    _loadingTimeoutTimer?.cancel();
    _hidePageIndicatorTimer?.cancel();
    _scrollCheckTimer?.cancel();
    _pdfReloadDebounceTimer?.cancel();
    _textPreviewDebounceTimer?.cancel();
    _formattingDebounceTimer?.cancel();
    _annotationSaveTimer?.cancel();
    _stopScrollCheckTimer();
    
    // Reset orientation to allow all orientations when leaving the screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // Dispose controllers
    _pdfViewerController.dispose();
    _searchController.dispose();
    _pagePreviewScrollController.dispose();
    
    super.dispose();
  }
  
  Future<void> _initializePDF() async {
    if (!mounted) return;
    
    try {
      print('PDFViewer: Initializing PDF with path: ${widget.filePath}');
      
      // Check if filePath is a content URI
      if (widget.filePath.startsWith('content://')) {
        print('PDFViewer: Detected content URI, copying to cache...');
        // Copy content URI to cache with timeout
        final tempPath = await _copyContentUriToCache(widget.filePath)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                print('PDFViewer: Content URI copy timeout');
                return null;
              },
            )
            .catchError((e) {
              print('PDFViewer: Error copying content URI: $e');
              return null;
            });
            
        if (tempPath != null && mounted) {
          print('PDFViewer: Content URI copied to: $tempPath');
          final tempFile = File(tempPath);
          final exists = await tempFile.exists()
              .timeout(const Duration(seconds: 2))
              .catchError((e) {
                print('PDFViewer: Error checking file existence: $e');
                return false;
              });
              
          if (exists) {
            print('PDFViewer: Setting _actualFilePath to cached path: $tempPath');
            if (mounted) {
              setState(() {
                _actualFilePath = tempPath;
              });
              // Load PDF info in background (non-blocking)
              _loadPDFInfo().catchError((e) {
                print('PDFViewer: Error loading PDF info: $e');
              });
            }
          } else {
            print('PDFViewer: Copied file does not exist at: $tempPath');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Failed to access PDF file. The file may have been moved or deleted.';
              });
            }
          }
        } else {
          print('PDFViewer: Failed to copy content URI to cache');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Failed to access PDF file. Please try selecting the file again.';
            });
          }
        }
      } else {
        // Regular file path - verify it exists (non-blocking)
        print('PDFViewer: Regular file path detected');
        final file = File(widget.filePath);
        
        // Check file existence with timeout
        final exists = await file.exists()
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
              print('PDFViewer: Error checking file existence: $e');
              return false;
            });
            
        if (exists) {
          // CRITICAL FIX: Don't read entire file with readAsBytes() - causes ANR!
          // Only read first 4 bytes to check header
          try {
            final randomAccessFile = await file.open()
                .timeout(const Duration(seconds: 2))
                .catchError((e) {
                  print('PDFViewer: Error opening file: $e');
                  return null;
                });
                
            if (randomAccessFile != null) {
              try {
                final bytes = await randomAccessFile.read(4)
                    .timeout(const Duration(seconds: 2))
                    .catchError((e) {
                      print('PDFViewer: Error reading header: $e');
                      return <int>[];
                    });
                await randomAccessFile.close();
                
                if (bytes.length >= 4) {
                  final header = String.fromCharCodes(bytes);
                  print('PDFViewer: File header: $header');
                  if (header == '%PDF') {
                    print('PDFViewer: Valid PDF file detected');
                    if (mounted) {
                      setState(() {
                        _actualFilePath = widget.filePath;
                      });
                      // Load PDF info in background (non-blocking)
                      _loadPDFInfo().catchError((e) {
                        print('PDFViewer: Error loading PDF info: $e');
                      });
                    }
                  } else {
                    print('PDFViewer: File is not a valid PDF (header: $header)');
                    if (mounted) {
                      setState(() {
                        _isLoading = false;
                        _errorMessage = 'The selected file is not a valid PDF file.';
                      });
                    }
                  }
                } else {
                  print('PDFViewer: File is too small or empty');
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _errorMessage = 'The PDF file appears to be empty or corrupted.';
                    });
                  }
                }
              } catch (readError) {
                await randomAccessFile.close().catchError((_) {});
                // If we can't read header, still try to load it (might be a permission issue)
                print('PDFViewer: Error reading header, proceeding anyway: $readError');
                if (mounted) {
                  setState(() {
                    _actualFilePath = widget.filePath;
                  });
                  _loadPDFInfo().catchError((e) {
                    print('PDFViewer: Error loading PDF info: $e');
                  });
                }
              }
            } else {
              // Can't open file, but try to load anyway
              print('PDFViewer: Could not open file, proceeding anyway');
              if (mounted) {
                setState(() {
                  _actualFilePath = widget.filePath;
                });
                _loadPDFInfo().catchError((e) {
                  print('PDFViewer: Error loading PDF info: $e');
                });
              }
            }
          } catch (e) {
            print('PDFViewer: Error reading file: $e');
            // Still try to load - might work even if header check fails
            if (mounted) {
              setState(() {
                _actualFilePath = widget.filePath;
              });
              _loadPDFInfo().catchError((e) {
                print('PDFViewer: Error loading PDF info: $e');
              });
            }
          }
        } else {
          print('PDFViewer: File does not exist at: ${widget.filePath}');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'PDF file not found. It may have been moved or deleted.';
            });
          }
        }
      }
    } catch (e, stackTrace) {
      print('PDFViewer: Error initializing PDF: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading PDF: ${e.toString()}';
        });
      }
    }
  }
  
  Future<String?> _copyContentUriToCache(String contentUri) async {
    try {
      print('PDFViewer: Copying content URI: $contentUri');
      // Add timeout to prevent hanging
      final String? result = await _fileChannel.invokeMethod('copyContentUriToCache', contentUri)
          .timeout(
            const Duration(seconds: 15), // Max 15 seconds for file copy
            onTimeout: () {
              print('PDFViewer: Content URI copy timeout');
              return null;
            },
          )
          .catchError((e) {
            print('PDFViewer: Error copying content URI: $e');
            return null;
          });
          
      if (result != null) {
        print('PDFViewer: Content URI copied successfully to: $result');
        final file = File(result);
        
        // Check existence with timeout
        final exists = await file.exists()
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
              print('PDFViewer: Error checking copied file: $e');
              return false;
            });
            
        if (exists) {
          // Get file size with timeout
          final size = await file.length()
              .timeout(const Duration(seconds: 2))
              .catchError((e) {
                print('PDFViewer: Error getting file size: $e');
                return 0;
              });
          print('PDFViewer: Copied file exists, size: $size bytes');
          return result;
        } else {
          print('PDFViewer: Copied file does not exist');
          return null;
        }
      } else {
        print('PDFViewer: Content URI copy returned null');
        return null;
      }
    } catch (e, stackTrace) {
      print('PDFViewer: Error copying content URI: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
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
    if (_actualFilePath == null || !mounted) return;
    
    try {
      final file = File(_actualFilePath!);
      
      // Check existence with timeout
      final exists = await file.exists()
          .timeout(const Duration(seconds: 2))
          .catchError((e) {
            print('PDFViewer: Error checking file in _loadPDFInfo: $e');
            return false;
          });
          
      if (exists) {
        // Get file stat with timeout
        final stat = await file.stat()
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
              print('PDFViewer: Error getting file stat: $e');
              return null;
            });
            
        if (stat != null && mounted) {
          final fileName = widget.fileName;
          final fileSize = PDFService.formatFileSize(stat.size);
          final modifiedDate = stat.modified;
          final date = PDFService.formatDate(modifiedDate);

          // Load bookmark status (use original filePath for bookmarking) - non-blocking
          final isBookmarked = await PDFPreferencesService.isBookmarked(widget.filePath)
              .timeout(const Duration(seconds: 1))
              .catchError((e) {
                print('PDFViewer: Error checking bookmark: $e');
                return false;
              });
        
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
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'PDF file not found. It may have been moved or deleted.';
        });
      }
    } catch (e) {
      print('Error loading PDF info: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error accessing PDF file: ${e.toString()}';
      });
    }
  }


  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    print('PDFViewer: Document loaded successfully, pages: ${details.document.pages.count}');
    _loadingTimeoutTimer?.cancel();
    if (mounted) {
      // Build per-page sizes list (supports varying page sizes)
      final pageSizes = <Size>[];
      for (int i = 0; i < details.document.pages.count; i++) {
        try {
          final page = details.document.pages[i];
          final size = Size(page.size.width, page.size.height);
          pageSizes.add(size);
        } catch (e) {
          // Fallback to default if page size unavailable
          pageSizes.add(const Size(612, 792));
        }
      }
      
      setState(() {
        _totalPages = details.document.pages.count;
        _isLoading = false;
        _errorMessage = null; // Clear any previous errors
        _pdfPageSizes = pageSizes; // Store per-page sizes
        
        // Get page size for annotation coordinate system (fallback for first page)
        if (pageSizes.isNotEmpty) {
          _pdfPageSize = pageSizes[0]; // Fallback for first page
        }
      });
      
      // Load saved annotations
      _loadSavedAnnotations();
      
      // Check if document is scanned (image-based, no extractable text)
      _checkIfScannedDocument();
      
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
  }
  
  /// Load saved annotations for current PDF
  Future<void> _loadSavedAnnotations() async {
    try {
      final annotations = await _annotationStorage.loadAnnotations(_actualFilePath ?? widget.filePath);
      if (mounted) {
        setState(() {
          _savedAnnotations = annotations;
        });
      }
    } catch (e) {
      print('Error loading annotations: $e');
    }
  }
  
  /// Check if PDF is a scanned document and disable text editing if so
  Future<void> _checkIfScannedDocument() async {
    try {
      final isScanned = await PDFTextSelectionService.isScannedDocument(
        _actualFilePath ?? widget.filePath,
      );
      
      if (mounted) {
        setState(() {
          _isScannedDocument = isScanned;
        });
        
        if (isScanned) {
          print('PDFViewer: Scanned document detected - text editing disabled');
        }
      }
    } catch (e) {
      print('Error checking if document is scanned: $e');
    }
  }
  
  void _onDocumentLoadFailed(PdfDocumentLoadFailedDetails details) {
    print('PDFViewer: Document load failed: ${details.error}');
    _loadingTimeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load PDF: ${details.error}\n\nThe file might be corrupted or in an unsupported format.';
      });
    }
  }

  Widget _buildPDFViewer() {
    // Show error if loading failed
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Color(0xFFE53935),
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to Load PDF',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF757575),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _isLoading = true;
                    _actualFilePath = null;
                  });
                  _initializePDF();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show loading indicator only if we don't have a file path yet
    // Once we have _actualFilePath, build the PDF viewer (it will show its own loading)
    if (_actualFilePath == null) {
      print('PDFViewer: Waiting for file path...');
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
        ),
      );
    }
    
    // Build PDF viewer with actual file path
    // Ensure we're using the cached file path, not the content URI
    final filePath = _actualFilePath!;
    print('PDFViewer: Building PDF viewer with file path: $filePath');
    
    // Double-check it's not a content URI
    if (filePath.startsWith('content://')) {
      print('PDFViewer: ERROR - Still using content URI! This should not happen.');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Color(0xFFE53935),
              ),
              const SizedBox(height: 16),
              const Text(
                'Configuration Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unable to process content URI. Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF757575),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // CRITICAL FIX: Don't check file.existsSync() or await file.exists() in build()!
    // Build method cannot be async and file checks block UI thread causing ANR
    // File existence was already verified in _initializePDF() - trust that result
    // Let the PDF viewer handle file errors itself if file doesn't exist
    
    print('PDFViewer: Building PDF viewer...');
    
    // Create File object - don't check existence here (already checked in _initializePDF)
    final file = File(filePath);
    
    // Wrap PDF viewer in RepaintBoundary to prevent full-screen repaints
    // Use LayoutBuilder so we get the ACTUAL PDF viewer size (not full screen)
    final pdfViewer = RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewerSize = constraints.biggest;
          
          // Store viewer size for overlay coordinate conversion
          // This ensures annotations use actual viewer dimensions, not full screen
          return _buildPdfViewerWithOverlay(file, viewerSize);
        },
      ),
    );
    
    return pdfViewer;
  }

  /// Build PDF viewer with overlay, using actual viewer size from LayoutBuilder
  Widget _buildPdfViewerWithOverlay(File file, Size viewerSize) {
    final pdfViewer = SfPdfViewer.file(
      file,
      key: ValueKey('pdf_viewer_${file.path}_$_viewMode$_pdfReloadKey'),
      controller: _pdfViewerController,
      pageSpacing: _pageSpacing,
      enableTextSelection: true,
      enableDoubleTapZooming: true,
      onDocumentLoaded: _onDocumentLoaded,
      onDocumentLoadFailed: _onDocumentLoadFailed,
      onPageChanged: _onPageChanged,
      scrollDirection: _getScrollDirection(),
      pageLayoutMode: _getPageLayoutMode(),
    );

    // Always use TextAwareAnnotationOverlay for custom tools (pen, highlight, underline, eraser)
    Widget overlay = TextAwareAnnotationOverlay(
      key: _textAwareOverlayKey,
      pdfPath: _actualFilePath ?? widget.filePath,
      currentPage: _currentPage - 1, // Convert to 0-based
      pageSizes: _pdfPageSizes.isNotEmpty ? _pdfPageSizes : [_pdfPageSize ?? const Size(612, 792)], // Per-page sizes
      zoomLevel: _zoomLevel,
      scrollOffsetY: _pdfScrollOffsetY, // Y offset from SfPdfViewer callback
      pageSpacing: _pageSpacing,
      viewerSize: viewerSize, // Actual viewer size from LayoutBuilder
      selectedTool: _selectedOverlayTool,
      toolColor: _selectedColor,
      strokeWidth: _strokeWidth,
      onAnnotationsChanged: (annotations) {
        setState(() {
          _savedAnnotations = annotations;
        });
      },
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
      child: pdfViewer,
    );
    
    // Add editable text highlights overlay when editText mode is active
    if (_selectedTool == PdfTool.editText && _allEditableTextObjects != null && _allEditableTextObjects!.isNotEmpty) {
      overlay = Stack(
        children: [
          overlay,
          // Editable text highlights overlay
          _buildEditableTextHighlightsOverlay(viewerSize),
        ],
      );
    }
    
    return overlay;
  }

  void _onPageChanged(PdfPageChangedDetails details) {
    final newPage = details.newPageNumber;
    if (newPage != _currentPage && mounted) {
      // CRITICAL FIX: Batch setState calls to prevent excessive updates
      // Use SchedulerBinding to batch updates and prevent ANR
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentPage = newPage;
            _showPageIndicator = true;
          });
          
          // Hide page indicator after delay
          _hidePageIndicatorTimer?.cancel();
          _hidePageIndicatorTimer = Timer(const Duration(seconds: 1), () {
            if (mounted) {
              setState(() {
                _showPageIndicator = false;
              });
            }
          });
          
          // Scroll to current page in preview bar (only if visible) - non-blocking
          if (_showPagePreview) {
            Future.microtask(() {
              if (mounted) {
                _scrollToCurrentPage();
              }
            });
          }
          
          // Reload editable text objects if editText mode is active
          if (_selectedTool == PdfTool.editText) {
            _loadAllTextObjectsForEditing();
          }
        }
      });
    }
  }
  
  /// Load all text objects from current page for highlighting in edit mode
  Future<void> _loadAllTextObjectsForEditing() async {
    if (_isLoadingEditableText) return; // Prevent duplicate loads
    
    final pageIndex = _currentPage - 1; // Convert to 0-based
    if (pageIndex < 0) return;
    
    // Skip if already loaded for this page
    if (_editableTextPageIndex == pageIndex && _allEditableTextObjects != null) {
      return;
    }
    
    setState(() {
      _isLoadingEditableText = true;
    });
    
    try {
      final pdfPath = _actualFilePath ?? widget.filePath;
      final textObjects = await PDFInlineTextEditorService.getAllTextObjects(pdfPath, pageIndex);
      
      if (mounted) {
        setState(() {
          _allEditableTextObjects = textObjects;
          _editableTextPageIndex = pageIndex;
          _isLoadingEditableText = false;
        });
        print('_loadAllTextObjectsForEditing: Loaded ${textObjects.length} text objects for page $pageIndex');
      }
    } catch (e) {
      print('_loadAllTextObjectsForEditing: Error loading text objects: $e');
      if (mounted) {
        setState(() {
          _isLoadingEditableText = false;
        });
      }
    }
  }
  
  /// Build overlay that highlights all editable text when editText mode is active
  Widget _buildEditableTextHighlightsOverlay(Size viewerSize) {
    if (_allEditableTextObjects == null || _allEditableTextObjects!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final pageIndex = _currentPage - 1;
    if (_editableTextPageIndex != pageIndex) {
      return const SizedBox.shrink();
    }
    
    // Get page size for coordinate conversion
    final pageSize = _pdfPageSizes.isNotEmpty && pageIndex < _pdfPageSizes.length
        ? _pdfPageSizes[pageIndex]
        : (_pdfPageSize ?? const Size(612, 792));
    
    return Positioned.fill(
      child: CustomPaint(
        painter: _EditableTextHighlightsPainter(
          textObjects: _allEditableTextObjects!,
          pageIndex: pageIndex,
          pageSize: pageSize,
          zoomLevel: _zoomLevel,
          scrollOffsetY: _pdfScrollOffsetY,
          pageSpacing: _pageSpacing,
          viewerSize: viewerSize,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
            // Find which text object was tapped
            final tapPoint = details.localPosition;
            _findTappedTextObject(tapPoint, viewerSize, pageSize);
          },
        ),
      ),
    );
  }
  
  /// Find which text object was tapped and open editor
  void _findTappedTextObject(Offset screenTap, Size viewerSize, Size pageSize) {
    if (_allEditableTextObjects == null || _allEditableTextObjects!.isEmpty) return;
    
    final pageIndex = _currentPage - 1;
    
    // Convert screen coordinates to PDF coordinates
    // Use same conversion logic as _handlePDFTextTap for consistency
    final scaleX = pageSize.width / viewerSize.width;
    final scaleY = pageSize.height / (viewerSize.height / _zoomLevel);
    
    // Account for scroll offset
    final pdfX = screenTap.dx * scaleX;
    final pdfY = (screenTap.dy + _pdfScrollOffsetY) * scaleY;
    
    // Text objects from PDFInlineTextEditorService use top-left origin
    // So pdfY is already in top-left coordinate system
    final pdfBoxY = pdfY;
    
    // Find closest text object
    PDFInlineTextObject? tappedObject;
    double minDistance = double.infinity;
    const tolerance = 30.0;
    
    for (final obj in _allEditableTextObjects!) {
      if (obj.pageIndex != pageIndex) continue;
      
      // Check if tap is within text bounds (with tolerance)
      final withinX = pdfX >= obj.x - tolerance && pdfX <= obj.x + obj.width + tolerance;
      final withinY = pdfBoxY >= obj.y - tolerance && pdfBoxY <= obj.y + obj.height + tolerance;
      
      if (withinX && withinY) {
        // Calculate distance from tap to text center
        final textCenterX = obj.x + obj.width / 2;
        final textCenterY = obj.y + obj.height / 2;
        final distance = math.sqrt(
          math.pow(textCenterX - pdfX, 2) + math.pow(textCenterY - pdfBoxY, 2)
        );
        
        if (distance < minDistance) {
          minDistance = distance;
          tappedObject = obj;
        }
      }
    }
    
    if (tappedObject != null) {
      _onEditableTextTap(tappedObject);
    }
  }
  
  /// Handle tap on editable text - open editor directly
  void _onEditableTextTap(PDFInlineTextObject textObject) {
    print('_onEditableTextTap: Tapped on text "${textObject.text}" at (${textObject.x}, ${textObject.y})');
    
    // Convert PDFInlineTextObject to SelectedPDFText
    final bounds = Rect.fromLTWH(
      textObject.x,
      textObject.y,
      textObject.width,
      textObject.height,
    );
    
    setState(() {
      _selectedPDFText = SelectedPDFText(
        text: textObject.text,
        bounds: bounds,
        pageIndex: textObject.pageIndex,
        position: bounds.topLeft,
        fontSize: textObject.fontSize,
        color: textObject.color,
        fontFamily: textObject.fontName,
        isBold: false, // Could parse from fontName
        isItalic: false,
        isUnderline: false,
      );
      _selectedPDFTextObjectId = textObject.objectId;
      
      // Initialize text editor controller
      _textEditorController.setInitialText(textObject.text);
      
      // Show formatting toolbar at bottom
      _showTextFormattingToolbar = true;
      _isTextEditMode = true;
      _selectedMode = 'text';
      
      // Update undo/redo state
      _canUndoText = _textEditorController.canUndo;
      _canRedoText = _textEditorController.canRedo;
    });
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
    // Use system theme instead of local state
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF424242);
    final iconColor = isDarkMode ? Colors.white : const Color(0xFF424242);
    
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
      // CRITICAL FIX: Wrap body in SafeArea to handle system insets (status bar, navigation bar)
      // This prevents content from being cut off by ~23px on gesture navigation devices (Android 13-14)
      body: SafeArea(
        // Only apply top safe area (status bar), bottom is handled by bottomNavigationBar
        top: true,
        bottom: false,
        child: Stack(
          children: [
            // PDF Viewer with text-aware annotation overlay
            // Overlay is built inside _buildPDFViewer() via LayoutBuilder to get viewerSize
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Only track scroll for page preview bar UI updates, NOT for annotation positioning
                // Annotation positioning uses SfPdfViewer.onScrollChanged callback
                if (notification is ScrollStartNotification) {
                  _isScrolling = true;
                  _startScrollCheckTimer();
                } else if (notification is ScrollUpdateNotification) {
                  _isScrolling = true;
                  // Update scroll offset for annotation positioning (fallback if callbacks don't exist)
                  if (mounted) {
                    setState(() {
                      _pdfScrollOffsetY = notification.metrics.pixels;
                    });
                  }
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (mounted) {
                      _updateCurrentPageFromScroll();
                    }
                  });
                } else if (notification is ScrollEndNotification) {
                  // Update final scroll offset
                  if (mounted) {
                    setState(() {
                      _pdfScrollOffsetY = notification.metrics.pixels;
                    });
                  }
                  _isScrolling = false;
                  _stopScrollCheckTimer();
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (mounted) {
                      _updateCurrentPageFromScroll();
                    }
                  });
                }
                return false; // Allow notification to continue propagating
              },
              child: MouseRegion(
                cursor: _getSystemCursorForType(),
                child: _selectedTool == PdfTool.editText
                    ? // When editText is active, use Listener to detect taps without blocking Syncfusion's text selection
                      Listener(
                        onPointerDown: (event) {
                          // Store tap position for later use
                          _lastTapPosition = event.localPosition;
                          _lastTapTime = DateTime.now();
                        },
                        onPointerUp: (event) {
                          // Only handle as tap if it was quick (not a long-press for selection)
                          final now = DateTime.now();
                          final tapPosition = _lastTapPosition; // Capture before clearing
                          final tapTime = _lastTapTime; // Capture before clearing
                          
                          // Clear immediately to avoid stale data
                          _lastTapPosition = null;
                          _lastTapTime = null;
                          
                          if (tapTime != null && 
                              tapPosition != null &&
                              now.difference(tapTime).inMilliseconds < 300) {
                            // Quick tap - check for text at this position
                            Future.delayed(const Duration(milliseconds: 100), () {
                              // Small delay to let Syncfusion's selection complete first
                              if (mounted && _selectedTool == PdfTool.editText) {
                                _handleTextEditTap(tapPosition);
                              }
                            });
                          }
                        },
                        child: _buildPDFViewer(),
                      )
                    : // For other tools, use GestureDetector for tap handling
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) {
                          final tapPos = details.localPosition;
                          if (_isAddTextToolActive && _selectedMode == 'text_add') {
                            // T tool active: add new text at tap position
                            _showTextEditDialog(
                              initialText: '',
                              position: tapPos,
                              isEditing: false,
                            );
                          } else {
                            // Default behavior: tap-to-edit existing text
                            _handleTextEditTap(tapPos);
                          }
                        },
                        child: _buildPDFViewer(),
                      ),
              ),
            ),
          // Floating toolbar (appears when text is selected via Syncfusion selection)
          if (_showFloatingTextToolbar && _syncfusionSelectedText != null && _floatingToolbarPosition != null)
            Positioned(
              left: _floatingToolbarPosition!.dx,
              top: _floatingToolbarPosition!.dy,
              child: _buildFloatingTextToolbar(),
            ),
          
          // Text formatting toolbar (appears when text is selected - Sejda-style)
          // Positioned at bottom to always be visible and accessible
          if (_showTextFormattingToolbar && _selectedPDFText != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).viewInsets.bottom, // Adjust for keyboard
              child: SafeArea(
                top: false,
                child: PDFTextFormattingToolbar(
                  text: _selectedPDFText!.text,
                  isBold: _selectedPDFText!.isBold,
                  isItalic: _selectedPDFText!.isItalic,
                  isUnderline: _selectedPDFText!.isUnderline,
                  fontFamily: _selectedPDFText!.fontFamily,
                  fontSize: _selectedPDFText!.fontSize,
                  textColor: _selectedPDFText!.color,
                  onTextChanged: (newText) => _updateTextContentPreview(newText), // Update preview only
                  onBoldChanged: (isBold) => _applyTextFormatting(isBold: isBold),
                  onItalicChanged: (isItalic) => _applyTextFormatting(isItalic: isItalic),
                  onUnderlineChanged: (isUnderline) => _applyTextFormatting(isUnderline: isUnderline),
                  onFontChanged: (font) => _applyTextFormatting(fontFamily: font),
                  onFontSizeChanged: (size) => _applyTextFormatting(fontSize: size),
                  onColorChanged: (color) => _applyTextFormatting(color: color),
                  onDelete: _deleteSelectedText,
                  onCopy: _copySelectedText,
                  onLink: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link feature coming soon')),
                    );
                  },
                  onClose: () {
                    _closeTextToolbar();
                  },
                  onDone: () async {
                    // Save text to PDF when user clicks "Done"
                    await _saveTextContent();
                    if (mounted) {
                      _closeTextToolbarAfterSave();
                    }
                  },
                  isLoading: _isSavingText, // Show loading state
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
                    color: Theme.of(context).brightness == Brightness.dark
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
      ),
      floatingActionButton: _isEditingMode
          ? null
          : FloatingActionButton(
              onPressed: _enableTextEditing,
              backgroundColor: const Color(0xFF1976D2),
              child: const Icon(Icons.edit, color: Colors.white),
            ),
      bottomNavigationBar: _isEditingMode
          ? _buildReferenceToolbar()
          : (_totalPages > 0 && _showPagePreview
              ? _buildPagePreviewBar()
              : null),
    );
  }

  Color _getToolColor() {
    switch (_selectedTool) {
      case PdfTool.highlight:
        return Colors.yellow.withOpacity(0.4);
      case PdfTool.underline:
        return Colors.blue;
      case PdfTool.strike:
        return Colors.redAccent;
      case PdfTool.eraser:
        return Colors.white;
      case PdfTool.pen:
      case PdfTool.copy:
      case PdfTool.editText:
      case PdfTool.none:
        return _selectedColor;
    }
  }

  double _getStrokeWidth() {
    switch (_selectedTool) {
      case PdfTool.highlight:
        return 15.0; // Thicker for highlight
      case PdfTool.underline:
        return 2.0; // Thin line for underline
      case PdfTool.strike:
        return 2.0; // Similar to underline
      case PdfTool.eraser:
        return 20.0; // Larger eraser
      case PdfTool.pen:
      case PdfTool.copy:
      case PdfTool.editText:
      case PdfTool.none:
        return _strokeWidth;
    }
  }

  /// New reference-style bottom toolbar (icon-only, matches provided design)
  Widget _buildReferenceToolbar() {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE0E0E0), width: 1), // subtle top divider
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      height: 56.0 + bottomPadding,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Center(
        // Wrap in horizontal scroll view to avoid overflow on small screens
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          // 1) Undo
          IconButton(
            iconSize: 26,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: Icon(
              Icons.undo,
              size: 26,
              color: _canUndo ? const Color(0xFF4A4A4A) : Colors.grey[300],
            ),
            onPressed: _canUndo ? _undo : null,
            tooltip: 'Undo',
          ),

          // 2) Redo
          IconButton(
            iconSize: 26,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: Icon(
              Icons.redo,
              size: 26,
              color: _canRedo ? const Color(0xFF4A4A4A) : Colors.grey[300],
            ),
            onPressed: _canRedo ? _redo : null,
            tooltip: 'Redo',
          ),

          // 3) Copy
          _buildRefToolIcon(
            icon: Icons.content_copy,
            tool: PdfTool.copy,
            onTap: () {
              if (_selectedPDFText != null) {
                _copySelectedText();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Long press to select text first'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
              _selectTool(PdfTool.copy);
            },
          ),

          // 4) Underline
          _buildRefToolIcon(
            icon: Icons.format_underline,
            tool: PdfTool.underline,
            onTap: () => _selectTool(PdfTool.underline),
          ),

          // 5) StrikeThrough
          _buildRefToolIcon(
            icon: Icons.format_strikethrough,
            tool: PdfTool.strike,
            onTap: () => _selectTool(PdfTool.strike),
          ),

          // 6) Highlight
          _buildRefToolIcon(
            icon: Icons.highlight,
            tool: PdfTool.highlight,
            onTap: () => _selectTool(PdfTool.highlight),
          ),

          // 7) Pen
          _buildRefToolIcon(
            icon: Icons.create,
            tool: PdfTool.pen,
            onTap: () => _selectTool(PdfTool.pen),
          ),

          // 8) Edit Text – select and edit existing text (using text_fields icon to distinguish from pen)
          _buildRefToolIcon(
            icon: Icons.text_fields,
            tool: PdfTool.editText,
            onTap: () {
              _selectTool(PdfTool.editText);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Long press and drag to select text, then tap to edit'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),

          // 9) Text (T) – add new text to PDF
          _buildAddTextToolIcon(),

          // 9) Done (check) – blue tick as in reference
          IconButton(
            iconSize: 26,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: Icon(
              Icons.check,
              size: 26,
              color: const Color(0xFF2F6BFF), // blue tick
            ),
            onPressed: _onDoneEditing,
            tooltip: 'Done',
          ),
            ],
          ),
        ),
      ),
    );
  }

  /// Single icon-only tool, matching reference style
  Widget _buildRefToolIcon({
    required IconData icon,
    required PdfTool tool,
    required VoidCallback onTap,
  }) {
    const double iconSize = 26.0;
    const Color defaultColor = Color(0xFF4A4A4A); // medium-dark gray as in reference
    const Color selectedColor = Color(0xFF2F6BFF); // blue when active

    final bool isSelected = _selectedTool == tool;

    return IconButton(
      onPressed: onTap,
      iconSize: iconSize,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(
        icon,
        size: iconSize,
        color: isSelected ? selectedColor : defaultColor,
      ),
    );
  }

  /// Build floating toolbar (Edit/Copy/Delete) that appears when text is selected
  Widget _buildFloatingTextToolbar() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: const Color(0xFF424242), // Dark gray like in the image
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Edit button
            _buildFloatingToolbarButton(
              icon: Icons.edit,
              label: 'Edit',
              onPressed: _onFloatingEditPressed,
            ),
            const SizedBox(width: 4),
            // Copy button
            _buildFloatingToolbarButton(
              icon: Icons.content_copy,
              label: 'Copy',
              onPressed: _onFloatingCopyPressed,
            ),
            const SizedBox(width: 4),
            // Delete button
            _buildFloatingToolbarButton(
              icon: Icons.delete,
              label: 'Delete',
              onPressed: _onFloatingDeletePressed,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  /// Build a single button for the floating toolbar
  Widget _buildFloatingToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDestructive ? Colors.red[300] : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isDestructive ? Colors.red[300] : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Icon for the "T" add-text tool (toggles add-text mode)
  Widget _buildAddTextToolIcon() {
    const double iconSize = 26.0;
    const Color defaultColor = Color(0xFF4A4A4A);
    const Color selectedColor = Color(0xFF2F6BFF);

    return IconButton(
      onPressed: () {
        setState(() {
          // Toggle add-text mode
          _isAddTextToolActive = !_isAddTextToolActive;
          _selectedMode = _isAddTextToolActive ? 'text_add' : 'none';
          _isTextEditMode = _isAddTextToolActive;
          if (_isAddTextToolActive) {
            _cursorType = CursorType.text;
          }
        });

        if (_isAddTextToolActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tap on the page where you want to add text'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      iconSize: iconSize,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(
        Icons.title, // Use "T" icon for adding new text (distinct from text_fields for editing)
        size: iconSize,
        color: _isAddTextToolActive ? selectedColor : defaultColor,
      ),
      tooltip: 'Add Text',
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : const Color(0xFF9E9E9E);
    
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
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

  void _toggleDarkMode() async {
    final currentTheme = Theme.of(context).brightness;
    final newThemeMode = currentTheme == Brightness.dark 
        ? ThemeMode.light 
        : ThemeMode.dark;
    
    await ThemeService.setThemeMode(newThemeMode);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newThemeMode == ThemeMode.dark 
              ? 'Dark mode enabled' 
              : 'Light mode enabled'),
          duration: const Duration(seconds: 1),
        ),
      );
      // Navigate back and forward to trigger theme rebuild
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PDFViewerScreen(
            filePath: widget.filePath,
            fileName: widget.fileName,
          ),
        ),
      );
    }
  }

  Future<void> _mergePDF() async {
    try {
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
      
      // Include current PDF in merge
      final pdfPaths = [widget.filePath, ...selectedFiles];

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

      // Merge PDFs
      final mergedPath = await PDFToolsService.mergePDFs(pdfPaths);

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
              content: Text('PDFs merged successfully! File saved in app storage. Returning to file list...'),
              duration: Duration(seconds: 2),
            ),
          );
          
          // Pop back to home screen so file list refreshes and shows the merged file
          // The merged file is already in cache, so it will appear in the list
          Navigator.of(context).pop(true); // Return true to indicate refresh needed
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
      // PHASE 5: Close loading dialog on error and show user-friendly message
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
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
          ),
        );
      }
    }
  }

  void _splitPDF() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    
    showDialog(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: backgroundColor,
        ),
        child: AlertDialog(
          title: Text('Split PDF', style: TextStyle(color: textColor)),
          content: Text(
            'This will split "${widget.fileName}" into $_totalPages separate page files. Continue?',
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: textColor)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _performSplitPDF();
              },
              child: const Text('Split', style: TextStyle(color: Color(0xFFE53935))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performSplitPDF() async {
    BuildContext? dialogContext;
    
    try {
      // Show loading indicator with progress message
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogContext = context;
          return PopScope(
            canPop: false, // Prevent dismissing during operation
            child: Dialog(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Splitting PDF into $_totalPages pages...',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This may take a moment for large PDFs',
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

      // Run split operation with timeout to prevent indefinite hanging
      final splitFiles = await PDFToolsService.splitPDF(widget.filePath)
          .timeout(
            const Duration(minutes: 5), // Max 5 minutes for very large PDFs
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
          widget.filePath,
          resultPath: splitFiles.first,
        );
        
        if (mounted) {
          // Small delay to ensure cache is fully updated before showing message
          await Future.delayed(const Duration(milliseconds: 100));
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF split successfully! ${splitFiles.length} file(s) saved automatically. Files are available in Recent and App Files.',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
          
          // Pop back to home screen - it will reload files automatically
          Navigator.of(context).pop(true); // Return true to indicate refresh needed
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
            ? 'Split operation timed out. The PDF may be too large. Please try with a smaller PDF.'
            : e.toString().contains('permission')
                ? 'Permission denied. Please grant storage access in settings.'
                : 'An error occurred while splitting the PDF. Please try again.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
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
      if (_actualFilePath == null) {
        throw Exception('PDF file not available');
      }
      final file = File(_actualFilePath!);
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
      final file = File(_actualFilePath ?? widget.filePath);
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

      // Get annotations from overlay
      final annotations = _annotationOverlayKey.currentState?.annotations ?? [];
      
      // Save PDF with annotations using MuPDF (true PDF content objects)
      final saveSuccess = await PDFSaveService.savePDFWithProgress(
        context: context,
        filePath: _actualFilePath ?? widget.filePath,
        annotations: annotations,
        successMessage: 'PDF saved with annotations',
      );
      
      if (!saveSuccess) {
        return; // Error already shown in savePDFWithProgress
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not access device storage'),
            ),
          );
        }
        return;
      }

      // Copy file (with annotations already saved) to target directory
      final targetPath = path.join(targetDirectory!.path, fileName);
      final targetFile = File(targetPath);
      await file.copy(targetPath);
      
      // Show success message and offer to share
      if (mounted) {
        final shouldShare = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('PDF Saved'),
            content: Text('PDF with annotations saved to:\n${targetDirectory!.path}\n\nWould you like to share it to save to Downloads?'),
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
              content: Text('PDF with annotations saved to: ${targetDirectory!.path}'),
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
      if (_actualFilePath == null) {
        throw Exception('PDF file not available');
      }
      final file = File(_actualFilePath!);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(_actualFilePath!)],
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

  void _copySelectedText() {
    if (_selectedPDFText == null) return;
    
    Clipboard.setData(ClipboardData(text: _selectedPDFText!.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Text copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleTextEditTap(Offset position) async {
    print('_handleTextEditTap: Called with position=$position, _selectedTool=$_selectedTool');
    
    // Don't allow text editing on scanned documents
    if (_isScannedDocument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text editing is not available for scanned documents. This PDF contains only images.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // If editText tool is not active, auto-enable it for better UX
    if (_selectedTool != PdfTool.editText) {
      print('_handleTextEditTap: Auto-enabling editText tool');
      setState(() {
        _selectedMode = 'text';
        _isTextEditMode = true;
        _selectedTool = PdfTool.editText;
        _cursorType = CursorType.text;
      });
    }
    
    // Sejda-style: Try to find existing text first
    // If text found → toolbar appears automatically (NO DIALOG)
    // If no text found → just show hint, NO DIALOG
    // Use full screen size here as an approximation of viewer size
    try {
      await _handlePDFTextTap(position, MediaQuery.of(context).size);
    } catch (e) {
      print('_handleTextEditTap: Error detecting text: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error detecting text: $e'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    // Sejda-style: NO DIALOG when clicking on text or empty space
    // The toolbar handles all editing inline
  }
  
  Future<void> _addTextToPDF(String text, Offset screenPosition) async {
    if (text.isEmpty) return;
    
    // Don't allow adding text to scanned documents
    if (_isScannedDocument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text editing is not available for scanned documents. This PDF contains only images.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Get PDF page size and convert screen position to PDF coordinates
      final file = File(_actualFilePath ?? widget.filePath);
      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (_currentPage - 1 >= 0 && _currentPage - 1 < document.pages.count) {
        final page = document.pages[_currentPage - 1];
        final pageSize = page.size;
        final screenSize = MediaQuery.of(context).size;
        
        // Convert screen position to PDF coordinates
        // Syncfusion PDF viewer renders pages scaled to fit screen width
        // We need to account for scroll offset and calculate which page we're on
        
        // Calculate rendered PDF dimensions
        // PDF is scaled to fit screen width, height scales proportionally
        final pdfAspectRatio = pageSize.height / pageSize.width;
        final renderedPdfWidth = screenSize.width;
        final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;
        
        // Account for scroll - screen position is relative to visible viewport
        final absoluteDocumentY = screenPosition.dy + _pdfScrollOffsetY;
        
        // Calculate which page this position belongs to (for multi-page vertical scroll)
        final pageIndex = (absoluteDocumentY / renderedPdfHeight).floor();
        final pageStartY = pageIndex * renderedPdfHeight;
        final relativeYInPage = absoluteDocumentY - pageStartY;
        
        // Convert to PDF page coordinates (points, not pixels)
        // X: screen X position maps directly to PDF X (both scale with width)
        final pdfX = (screenPosition.dx / renderedPdfWidth) * pageSize.width;
        // Y: relative position in page maps to PDF Y
        final pdfY = (relativeYInPage / renderedPdfHeight) * pageSize.height;
        
        // Clamp to page bounds
        final clampedX = pdfX.clamp(0.0, pageSize.width);
        final clampedY = pdfY.clamp(0.0, pageSize.height);
        
        // Add text to PDF
        final graphics = page.graphics;
        final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12);
        final brush = sf.PdfSolidBrush(sf.PdfColor(
          _selectedColor.red,
          _selectedColor.green,
          _selectedColor.blue,
        ));
        
        final stringFormat = sf.PdfStringFormat();
        stringFormat.alignment = sf.PdfTextAlignment.left;
        stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
        
        graphics.drawString(
          text,
          font,
          brush: brush,
          format: stringFormat,
          bounds: Rect.fromLTWH(
            clampedX,
            clampedY,
            pageSize.width - clampedX,
            100, // Allow multi-line text
          ),
        );
        
        // Save PDF
        final modifiedBytes = await document.save();
        await file.writeAsBytes(modifiedBytes);
        document.dispose();
        
        // Don't reload PDF immediately - it causes hangs
        if (mounted) {
          Navigator.pop(context); // Close loading
          setState(() {
            // Changes will be visible when PDF is reopened or when exiting edit mode
            _isTextEditMode = false;
            _selectedMode = 'none';
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Text added to PDF'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        document.dispose();
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding text: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  void _editTextAnnotation(TextAnnotation textAnnotation) {
    _showTextEditDialog(
      initialText: textAnnotation.id, // Use ID to identify which annotation to edit
      position: Offset(
        textAnnotation.position.dx * MediaQuery.of(context).size.width,
        textAnnotation.documentY != null
            ? textAnnotation.documentY! - _pdfScrollOffsetY
            : textAnnotation.position.dy * MediaQuery.of(context).size.height,
      ),
      isEditing: true,
      existingAnnotation: textAnnotation,
    );
  }
  
  /// Save annotation directly to PDF content when drawing completes (non-blocking)
  void _saveAnnotationToPDF(List<AnnotationPoint> path) {
    if (path.isEmpty) return;
    
    // Prevent multiple simultaneous saves
    if (_isSavingAnnotation) {
      print('Annotation save already in progress, skipping...');
      return;
    }
    
    // Run save operation in background without blocking UI
    Future<void>.microtask(() async {
      if (_isSavingAnnotation) return; // Double check
      _isSavingAnnotation = true;
      
      try {
        final firstPoint = path.first;
        final pageIndex = firstPoint.pageNumber - 1; // Convert to 0-based
        final pdfPath = _actualFilePath ?? widget.filePath;
        
        // Get PDF page size for coordinate conversion (non-blocking with timeout)
        Size? pageSize;
        try {
          final file = File(pdfPath);
          if (!await file.exists().timeout(const Duration(seconds: 2))) {
            print('PDF file does not exist');
            return;
          }
          
          final bytes = await file.readAsBytes().timeout(const Duration(seconds: 5));
          final document = sf.PdfDocument(inputBytes: bytes);
          
          if (pageIndex < 0 || pageIndex >= document.pages.count) {
            document.dispose();
            print('Invalid page index: $pageIndex');
            return;
          }
          
          final page = document.pages[pageIndex];
          pageSize = Size(page.size.width, page.size.height);
          document.dispose();
        } catch (e) {
          print('Error getting page size: $e');
          return;
        }
        
        if (pageSize == null) {
          print('Failed to get page size');
          return;
        }
        
        // At this point, pageSize is guaranteed to be non-null
        final nonNullPageSize = pageSize!;
        
        // Convert normalized coordinates (0-1) to PDF coordinates (points)
        bool success = false;
        
        if (firstPoint.toolType == 'pen') {
          // Pen annotation - freehand path
          // Convert normalized coordinates (0-1, top-left origin) to PDF coordinates (points, bottom-left origin)
          final pdfPoints = path.map((p) {
            return Offset(
              p.normalizedPoint.dx * nonNullPageSize.width,
              nonNullPageSize.height - (p.normalizedPoint.dy * nonNullPageSize.height), // Invert Y-axis
            );
          }).toList();
          
          if (pdfPoints.length >= 2) {
            success = await MuPDFEditorService.addPenAnnotation(
              pdfPath,
              pageIndex,
              pdfPoints,
              firstPoint.color,
              firstPoint.strokeWidth,
            );
          }
        } else if (firstPoint.toolType == 'highlight') {
          // Highlight annotation - filled rectangle
          // Convert normalized coordinates (0-1, top-left origin) to PDF coordinates (points, bottom-left origin)
          final pdfPoints = path.map((p) {
            return Offset(
              p.normalizedPoint.dx * nonNullPageSize.width,
              nonNullPageSize.height - (p.normalizedPoint.dy * nonNullPageSize.height), // Invert Y-axis
            );
          }).toList();
          
          if (pdfPoints.length >= 2) {
            final minX = pdfPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
            final maxX = pdfPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
            final minY = pdfPoints.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
            final maxY = pdfPoints.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
            
            // PDF rectangle: (x, y, width, height) where (x,y) is bottom-left corner
            // After Y inversion: minY is the bottom Y, maxY is the top Y
            // So: x = minX, y = minY (bottom), width = maxX - minX, height = maxY - minY
            // The service expects rect.left, rect.top, rect.width, rect.height
            // But PDF needs bottom-left, so we pass: left=minX, top=minY (which is bottom in PDF), width, height
            final rect = Rect.fromLTWH(minX, minY, maxX - minX, maxY - minY);
            success = await MuPDFEditorService.addHighlightAnnotation(
              pdfPath,
              pageIndex,
              rect,
              firstPoint.color,
              0.4, // Default highlight opacity
            );
          }
        } else if (firstPoint.toolType == 'underline') {
          // Underline annotation - line
          // Convert normalized coordinates (0-1, top-left origin) to PDF coordinates (points, bottom-left origin)
          final pdfPoints = path.map((p) {
            return Offset(
              p.normalizedPoint.dx * nonNullPageSize.width,
              nonNullPageSize.height - (p.normalizedPoint.dy * nonNullPageSize.height), // Invert Y-axis
            );
          }).toList();
          
          if (pdfPoints.length >= 2) {
            final minX = pdfPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
            final maxX = pdfPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
            final y = pdfPoints.first.dy; // All points have same Y for underline
            
            success = await MuPDFEditorService.addUnderlineAnnotation(
              pdfPath,
              pageIndex,
              Offset(minX, y),
              Offset(maxX, y),
              firstPoint.color,
              firstPoint.strokeWidth,
            );
          }
        }
        
        // Skip saving if eraser tool (eraser doesn't add content, it removes overlay)
        if (firstPoint.isEraser) {
          // Eraser just removes from overlay, doesn't modify PDF
          if (mounted) {
            _annotationOverlayKey.currentState?.removeLastPath();
          }
          return;
        }
        
        // Save PDF and update UI only if successful
        if (success) {
          // Save PDF (with timeout to prevent hanging)
          try {
            await MuPDFEditorService.savePdf(pdfPath).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                print('PDF save timed out');
                return false;
              },
            );
          } catch (e) {
            print('Error saving PDF: $e');
            return;
          }
          
          // Update UI on main thread after save completes
          if (mounted) {
            // Remove the path from overlay immediately (annotation is saved)
            _annotationOverlayKey.currentState?.removeLastPath();
            
            // Reload PDF after a short delay to show changes (debounced to prevent hangs)
            _pdfReloadDebounceTimer?.cancel();
            _pdfReloadDebounceTimer = Timer(const Duration(milliseconds: 800), () {
              if (mounted) {
                setState(() {
                  _pdfReloadKey++; // Force PDF viewer to reload
                });
                print('PDF reloaded to show annotation changes');
              }
            });
          }
        } else {
          // Save failed - show error message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to save annotation. Please try again.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        print('Error saving annotation to PDF: $e');
      } finally {
        _isSavingAnnotation = false;
      }
    });
  }
  
  /// Handle tap on PDF to detect and select text (Sejda-style) using MuPDF
  ///
  /// IMPORTANT:
  /// - [screenPosition] is in the same coordinate space as the PDF viewer /
  ///   text-aware overlay (top-left origin, already includes zoom).
  /// - Coordinate conversion MUST match `_screenToPdf` in
  ///   `text_aware_annotation_overlay.dart` so taps, highlights, and
  ///   editing all hit the same text.
  Future<void> _handlePDFTextTap(Offset screenPosition, Size viewerSize) async {
    // Don't allow text editing on scanned documents
    if (_isScannedDocument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text editing is not available for scanned documents. This PDF contains only images.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      final file = File(_actualFilePath ?? widget.filePath);
      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (document.pages.count == 0) {
        document.dispose();
        return;
      }
      
      // Convert screen position to PDF coordinates
      // This logic is intentionally kept IDENTICAL to _screenToPdf() in
      // text_aware_annotation_overlay.dart so all tools agree.

      // Use PDF page size (all pages assumed same size for scaling)
      final firstPage = document.pages[0];
      final pageSize = firstPage.size;

      // Use viewerSize (actual PDF viewer widget size) for scaling
      // This matches the coordinate system of details.localPosition
      final screenSize = viewerSize;

      // Rendered PDF dimensions (scaled to fit viewer width)
      final pdfAspectRatio = pageSize.height / pageSize.width;
      final renderedPdfWidth = screenSize.width;
      final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;

      // 1) Absolute Y in document space (includes scroll)
      final absoluteDocumentY = screenPosition.dy + _pdfScrollOffsetY;

      // 2) Page index from absolute Y (continuous vertical layout)
      int tappedPageIndex = (absoluteDocumentY / renderedPdfHeight).floor();
      tappedPageIndex = tappedPageIndex.clamp(0, document.pages.count - 1);

      // 3) Y relative to that page
      final pageStartY = tappedPageIndex * renderedPdfHeight;
      final relativeYInPage = absoluteDocumentY - pageStartY;

      // 4) Convert to PDF page coordinates (points)
      // PDF uses bottom-left origin where Y=0 is at bottom, Y increases upward
      // MuPDF text coordinates are in this native system
      final pdfX = (screenPosition.dx / renderedPdfWidth) * pageSize.width;
      
      // Convert screen Y to PDF Y (both measured from bottom)
      // Screen: Y=0 at top, Y=renderedHeight at bottom
      // PDF: Y=0 at bottom, Y=pageHeight at top
      // Screen Y from top = relativeYInPage
      // Screen Y from bottom = renderedPdfHeight - relativeYInPage
      // PDF Y from bottom = (screen Y from bottom / renderedPdfHeight) * pageSize.height
      final screenYFromBottom = renderedPdfHeight - relativeYInPage;
      final pdfY = (screenYFromBottom / renderedPdfHeight) * pageSize.height;
      
      final pdfTapPoint = Offset(pdfX, pdfY);
      
      // DEBUG: Log coordinate conversion values
      print('PDFTextTap DEBUG: screenPosition=(${screenPosition.dx}, ${screenPosition.dy}), '
          'scrollOffset=$_pdfScrollOffsetY, '
          'absoluteDocumentY=$absoluteDocumentY, '
          'renderedPdfHeight=$renderedPdfHeight, '
          'tappedPageIndex=$tappedPageIndex, '
          'pageStartY=$pageStartY, '
          'relativeYInPage=$relativeYInPage, '
          'screenYFromBottom=$screenYFromBottom, '
          'pdfY=$pdfY, '
          'pageSize.height=${pageSize.height}, '
          'pdfTapPoint=($pdfX, $pdfY)');

      // Keep document alive while we use pageSize for tolerance calculations

      // Use MuPDF to get word quads at this position (same pipeline as highlight)
      final pdfPath = _actualFilePath ?? widget.filePath;
      final wordQuad = await _hitTestWordQuadAt(
        pdfPath: pdfPath,
        pageIndex: tappedPageIndex,
        pdfTapPoint: pdfTapPoint,
        pageSize: Size(pageSize.width, pageSize.height),
        renderedPdfWidth: renderedPdfWidth,
        renderedPdfHeight: renderedPdfHeight,
      );

      document.dispose();

      if (wordQuad == null || wordQuad.text == null || wordQuad.text!.isEmpty) {
        // No word found at this position
        print('PDFTextTap: No word found at position ($screenPosition)');
        
        // Only clear selection if text tool is active, otherwise allow other tools to work
        if (_selectedMode == 'text' || _isTextEditMode) {
          setState(() {
            _selectedPDFText = null;
            _selectedPDFTextObjectId = null;
            _showTextFormattingToolbar = false;
          });
          
          // Show helpful message if text tool is active but no text found
          if (_selectedMode == 'text') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No text found at this position. Tap on text to edit it.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
        return;
      }
      
      // Validate that we have an objectId (required for text replacement)
      if (wordQuad.objectId == null || wordQuad.objectId!.isEmpty) {
        print('PDFTextTap: Warning - Text found but no objectId available. Text editing may not work correctly.');
        // Still show toolbar but warn user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Text found but editing may be limited. Try using full document editing instead.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }

      print('PDFTextTap: Found word "${wordQuad.text}" at page ${wordQuad.pageIndex}');

      // If highlight or underline tool is selected, we rely on the overlay-based
      // drag selection to create annotations. Tapping on text is reserved for
      // inline text editing only.

      // Text and objectId come directly from the MuPDF quad extraction.
      // This is the SINGLE source of truth for selection; no second lookup.
      final bounds = wordQuad.bounds;

      // If editText tool is active, show floating toolbar first (like in the image)
      if (_selectedTool == PdfTool.editText) {
        setState(() {
          _syncfusionSelectedText = wordQuad.text;
          _syncfusionSelectionBounds = bounds;
          _syncfusionSelectionPage = wordQuad.pageIndex;
          // Store objectId for later editing
          _selectedPDFTextObjectId = wordQuad.objectId;
          _showFloatingTextToolbar = true;
          // Position floating toolbar near the selected text
          final screenSize = MediaQuery.of(context).size;
          _floatingToolbarPosition = Offset(
            (screenPosition.dx - 100).clamp(16.0, screenSize.width - 250),
            (screenPosition.dy - 80).clamp(16.0, screenSize.height - 200),
          );
        });
        return; // Don't show formatting toolbar yet, wait for Edit button
      }

      // Default behavior: show formatting toolbar directly
      setState(() {
        // Automatically enable text mode when text is found (even if text tool wasn't selected)
        _selectedMode = 'text';
        _isTextEditMode = true;
        _isEditingMode = true;
        
        _selectedPDFText = SelectedPDFText(
          text: wordQuad.text!,
          bounds: bounds,
          pageIndex: wordQuad.pageIndex,
          position: bounds.topLeft,
          // Use sensible defaults for formatting; actual formatting updates
          // come from the toolbar and are applied via replaceText.
          fontSize: 12.0,
          color: Colors.black,
          fontFamily: null,
          isBold: false,
          isItalic: false,
          isUnderline: false,
        );
        // Store MuPDF objectId for later replacement
        _selectedPDFTextObjectId = wordQuad.objectId;
        // Position toolbar above the selected text (Sejda-style: near but not blocking)
        final screenSize = MediaQuery.of(context).size;
        _textSelectionToolbarPosition = Offset(
          (screenPosition.dx - 150).clamp(16.0, screenSize.width - 320), // Keep toolbar on screen
          (screenPosition.dy - 100).clamp(16.0, screenSize.height - 200), // Above tap, but visible
        );
        _showTextFormattingToolbar = true;
        // Show visual feedback (Sejda-style: brief highlight)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.edit, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Text selected - Edit inline in toolbar'),
              ],
            ),
            backgroundColor: const Color(0xFF2196F3),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
          ),
        );
      });
    } catch (e) {
      print('Error handling PDF text tap: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error detecting text: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Shared word hit-test using Java PDFBox implementation
  ///
  /// - [pdfTapPoint] is in PDF coordinates (page space, bottom-left origin).
  /// - Returns the TextQuad whose bounds contain the tap, with a small
  ///   tolerance equivalent to ~20 PDF units.
  Future<app_models.TextQuad?> _hitTestWordQuadAt({
    required String pdfPath,
    required int pageIndex,
    required Offset pdfTapPoint,
    required Size pageSize,
    required double renderedPdfWidth,
    required double renderedPdfHeight,
  }) async {
    try {
      // Use Java PDFBox implementation to get text at tap position
      // PDFBox uses top-left origin (Y=0 at top), but PDF coordinates use bottom-left (Y=0 at bottom)
      // Convert from bottom-left to top-left for PDFBox
      final pdfBoxY = pageSize.height - pdfTapPoint.dy;
      
      print('_hitTestWordQuadAt: Calling PDFBox getTextAt at PDF ($pdfTapPoint), converted to PDFBox Y=$pdfBoxY');
      
      PDFInlineTextObject? textObject;
      try {
        textObject = await PDFInlineTextEditorService.getTextAt(
          pdfPath,
          pageIndex,
          pdfTapPoint.dx,
          pdfBoxY, // Convert to top-left origin for PDFBox
        );
      } catch (e) {
        print('_hitTestWordQuadAt: Error calling PDFBox getTextAt: $e');
        // If AWT classes are missing, return null gracefully instead of crashing
        if (e.toString().contains('AWT') || e.toString().contains('NoClassDefFoundError')) {
          print('_hitTestWordQuadAt: AWT classes missing - PDFBox not available on this device');
          return null;
        }
        rethrow;
      }

      if (textObject == null) {
        print('_hitTestWordQuadAt: No text object found at position');
        return null;
      }

      print('_hitTestWordQuadAt: Found text object "${textObject.text}" at (${textObject.x}, ${textObject.y}) [top-left origin]');

      // Convert PDFInlineTextObject to TextQuad
      // textObject coordinates are in top-left origin (Y=0 at top)
      // TextQuad needs bottom-left origin (Y=0 at bottom) for PDF coordinate system
      // textObject.y is distance from top, textObject.height is the height
      final topY = textObject.y; // Already from top
      final bottomY = textObject.y + textObject.height; // Bottom from top
      
      // Convert to bottom-left origin for TextQuad
      final quadTopY = pageSize.height - bottomY; // Top in bottom-left system
      final quadBottomY = pageSize.height - topY; // Bottom in bottom-left system
      
      // Create quad corners from text object bounds (in bottom-left origin)
      final topLeft = Offset(textObject.x, quadTopY);
      final topRight = Offset(textObject.x + textObject.width, quadTopY);
      final bottomLeft = Offset(textObject.x, quadBottomY);
      final bottomRight = Offset(textObject.x + textObject.width, quadBottomY);

      final quad = app_models.TextQuad(
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
        pageIndex: pageIndex,
        text: textObject.text,
        objectId: textObject.objectId,
      );

      // Check if tap point is within the quad bounds (with some tolerance)
      final tolerance = 20.0; // PDF units
      final expandedBounds = quad.bounds.inflate(tolerance);
      
      if (expandedBounds.contains(pdfTapPoint)) {
        print('_hitTestWordQuadAt: Selected text "${quad.text}" (tap point within bounds)');
        return quad;
      }

      // If tap point is close but not exactly within bounds, still return it
      // (this handles coordinate rounding issues)
      final distance = (quad.bounds.center - pdfTapPoint).distance;
      final maxDistance = math.max(pageSize.width * 0.1, tolerance * 2.0);
      
      if (distance < maxDistance) {
        print('_hitTestWordQuadAt: Selected text "${quad.text}" (distance: ${distance.toStringAsFixed(2)})');
        return quad;
      }

      print('_hitTestWordQuadAt: Text found but too far from tap point (distance: ${distance.toStringAsFixed(2)})');
      return null;
    } catch (e) {
      print('Error in _hitTestWordQuadAt: $e');
      return null;
    }
  }
  
  // Debounce timer for text preview updates
  Timer? _textPreviewDebounceTimer;
  
  /// Update text content preview (UI only - doesn't save to PDF)
  /// Text is only saved when user clicks "Done"
  /// Optimized with debouncing to reduce setState calls
  /// Now includes undo/redo support
  void _updateTextContentPreview(String newText) {
    if (_selectedPDFText == null) return;
    
    // Save current text to undo stack before making changes
    _textEditorController.onTextChanged(_selectedPDFText!.text);
    
    // Cancel previous debounce timer
    _textPreviewDebounceTimer?.cancel();
    
    // Debounce UI updates to reduce setState calls (improves performance)
    _textPreviewDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted && _selectedPDFText != null) {
        setState(() {
          _selectedPDFText = _selectedPDFText!.copyWith(text: newText);
          // Update undo/redo state
          _canUndoText = _textEditorController.canUndo;
          _canRedoText = _textEditorController.canRedo;
        });
      }
    });
  }
  
  /// Undo last text change
  void _undoTextChange() {
    if (!_textEditorController.canUndo || _selectedPDFText == null) return;
    
    final previousText = _textEditorController.undo();
    if (previousText != null) {
      setState(() {
        _selectedPDFText = _selectedPDFText!.copyWith(text: previousText);
        _canUndoText = _textEditorController.canUndo;
        _canRedoText = _textEditorController.canRedo;
      });
    }
  }
  
  /// Redo last undone text change
  void _redoTextChange() {
    if (!_textEditorController.canRedo || _selectedPDFText == null) return;
    
    final nextText = _textEditorController.redo();
    if (nextText != null) {
      setState(() {
        _selectedPDFText = _selectedPDFText!.copyWith(text: nextText);
        _canUndoText = _textEditorController.canUndo;
        _canRedoText = _textEditorController.canRedo;
      });
    }
  }
  
  // Loading state for text save operation
  bool _isSavingText = false;
  
  /// Save text content to PDF (called when user clicks "Done")
  /// Optimized with immediate UI feedback and async save
  Future<void> _saveTextContent() async {
    if (_selectedPDFText == null || _selectedPDFTextObjectId == null) return;
    if (_isSavingText) return; // Prevent multiple simultaneous saves
    
    // Cancel any pending preview updates
    _textPreviewDebounceTimer?.cancel();
    
    // Show loading indicator immediately
    setState(() {
      _isSavingText = true;
    });
    
    try {
      // Save the current text to PDF (non-blocking)
      await _saveTextChangeToPDF(_selectedPDFText!.text);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingText = false;
        });
      }
    }
  }
  
  /// Save text content change to PDF (background operation)
  /// Optimized with faster reload and better error handling
  Future<void> _saveTextChangeToPDF(String newText) async {
    if (_selectedPDFText == null) {
      print('_saveTextChangeToPDF: No text selected');
      return;
    }
    
    if (_selectedPDFTextObjectId == null || _selectedPDFTextObjectId!.isEmpty) {
      print('_saveTextChangeToPDF: No objectId available, using Syncfusion fallback');
      // Try Syncfusion fallback if no objectId
      final success = await _replaceTextWithSyncfusion(newText);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Text editing failed. This PDF may not support inline editing. Try using "Extract All Text" for full document editing.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
      return;
    }
    
    try {
      final pdfPath = _actualFilePath ?? widget.filePath;
      final pageIndex = _selectedPDFText!.pageIndex;
      
      print('_saveTextChangeToPDF: Attempting to replace text with objectId: ${_selectedPDFTextObjectId}');
      print('_saveTextChangeToPDF: Old text: "${_selectedPDFText!.text}" -> New text: "$newText"');
      
      // Get coordinates from selected text for fallback mechanism
      double? x, y;
      if (_selectedPDFText!.position != null) {
        x = _selectedPDFText!.position!.dx;
        y = _selectedPDFText!.position!.dy;
        print('_saveTextChangeToPDF: Using coordinates for fallback: x=$x, y=$y');
      }
      
      // Try Java iText service first (handles float coordinates in objectId)
      // Pass coordinates for automatic fallback if objectId fails
      print('_saveTextChangeToPDF: Calling PDFInlineTextEditorService.replaceText (iText)');
      bool success = await PDFInlineTextEditorService.replaceText(
        pdfPath,
        pageIndex,
        _selectedPDFTextObjectId!,
        newText,
        x: x,
        y: y,
      );
      
      if (success) {
        print('_saveTextChangeToPDF: ✓ iText replacement successful!');
      } else {
        // Fallback to Syncfusion if iText fails
        print('_saveTextChangeToPDF: ✗ iText replacement failed, trying Syncfusion fallback');
        success = await _replaceTextWithSyncfusion(newText);
      }
      
      if (success) {
        // Optimized: Reload faster (reduced from 800ms to 200ms)
        // Also navigate to the edited page to show changes immediately
        if (mounted) {
          _pdfReloadDebounceTimer?.cancel();
          
          // Navigate to the edited page first (faster visual feedback)
          if (_pdfViewerController.pageNumber != pageIndex + 1) {
            _pdfViewerController.jumpToPage(pageIndex + 1);
          }
          
          // Reload PDF after minimal delay
          _pdfReloadDebounceTimer = Timer(const Duration(milliseconds: 200), () {
            if (mounted) {
              setState(() {
                _pdfReloadKey++; // Force PDF viewer to reload
              });
              
              // Show success message (non-blocking)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Text updated'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update text. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('Error saving text change: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  /// Fallback: Replace text using Syncfusion (works but less precise)
  Future<bool> _replaceTextWithSyncfusion(String newText) async {
    try {
      final file = File(_actualFilePath ?? widget.filePath);
      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (_selectedPDFText!.pageIndex >= 0 && _selectedPDFText!.pageIndex < document.pages.count) {
        final page = document.pages[_selectedPDFText!.pageIndex];
        final graphics = page.graphics;
        
        // Draw white rectangle to "erase" old text
        final bounds = _selectedPDFText!.bounds;
        graphics.drawRectangle(
          brush: sf.PdfSolidBrush(sf.PdfColor(255, 255, 255)),
          bounds: Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.width,
            bounds.height,
          ),
        );
        
        // Draw new text at same position
        final font = sf.PdfStandardFont(
          sf.PdfFontFamily.helvetica,
          _selectedPDFText!.fontSize,
        );
        final brush = sf.PdfSolidBrush(sf.PdfColor(
          _selectedPDFText!.color.red,
          _selectedPDFText!.color.green,
          _selectedPDFText!.color.blue,
        ));
        
        final stringFormat = sf.PdfStringFormat();
        stringFormat.alignment = sf.PdfTextAlignment.left;
        stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
        
        graphics.drawString(
          newText,
          font,
          brush: brush,
          format: stringFormat,
          bounds: Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.width,
            bounds.height + 20, // Allow for text expansion
          ),
        );
        
        // Save PDF
        final modifiedBytes = await document.save();
        await file.writeAsBytes(modifiedBytes);
        document.dispose();
        
        return true;
      }
      document.dispose();
      return false;
    } catch (e) {
      print('Error in Syncfusion text replacement: $e');
      return false;
    }
  }
  
  /// Close text toolbar (without saving - used when user clicks Close)
  void _closeTextToolbar() {
    // Cancel any pending debounced reloads
    _pdfReloadDebounceTimer?.cancel();
    
    // Close toolbar immediately (don't reload PDF since no changes were saved)
    setState(() {
      _showTextFormattingToolbar = false;
      _selectedPDFText = null;
      _selectedPDFTextObjectId = null;
    });
  }
  
  /// Close text toolbar and reload PDF to show saved changes
  /// Optimized: Reload is already handled in _saveTextChangeToPDF
  void _closeTextToolbarAfterSave() {
    // Cancel any pending debounced reloads
    _pdfReloadDebounceTimer?.cancel();
    _textPreviewDebounceTimer?.cancel();
    
    // Close toolbar immediately (reload is handled by save operation)
    setState(() {
      _showTextFormattingToolbar = false;
      _selectedPDFText = null;
      _selectedPDFTextObjectId = null;
    });
    
    // Note: PDF reload is already scheduled in _saveTextChangeToPDF
    // No need to reload again here
  }
  
  // Debounce timer for formatting updates
  Timer? _formattingDebounceTimer;
  
  /// Apply text formatting to selected text using MuPDF (Sejda-style: immediate feedback)
  /// Optimized with debouncing to batch formatting changes
  Future<void> _applyTextFormatting({
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    String? fontFamily,
    double? fontSize,
    Color? color,
  }) async {
    if (_selectedPDFText == null || _selectedPDFTextObjectId == null) return;
    
    // Update UI immediately (Sejda-style immediate feedback)
    final updatedText = _selectedPDFText!.copyWith(
      isBold: isBold ?? _selectedPDFText!.isBold,
      isItalic: isItalic ?? _selectedPDFText!.isItalic,
      isUnderline: isUnderline ?? _selectedPDFText!.isUnderline,
      fontFamily: fontFamily ?? _selectedPDFText!.fontFamily,
      fontSize: fontSize ?? _selectedPDFText!.fontSize,
      color: color ?? _selectedPDFText!.color,
    );
    
    setState(() {
      _selectedPDFText = updatedText;
    });
    
    // Debounce formatting saves to batch multiple changes
    _formattingDebounceTimer?.cancel();
    _formattingDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      // Save to PDF in background (non-blocking, no loading dialog)
      _saveTextFormattingToPDF(updatedText);
    });
  }
  
  /// Save text formatting to PDF (background operation)
  Future<void> _saveTextFormattingToPDF(SelectedPDFText updatedText) async {
    if (_selectedPDFTextObjectId == null) return;
    
    try {
      final pdfPath = _actualFilePath ?? widget.filePath;
      // Note: Formatting changes require content stream editing which is complex
      // For now, we update the text with formatting applied
      // Full implementation would require parsing and modifying PDF content streams
      final success = await MuPDFEditorService.replaceText(
        pdfPath,
        updatedText.pageIndex,
        _selectedPDFTextObjectId!,
        updatedText.text,
      );
      
      if (success) {
        await MuPDFEditorService.savePdf(pdfPath);
        
        // Reload PDF after a short delay to show changes (debounced to prevent hangs)
        if (mounted) {
          _pdfReloadDebounceTimer?.cancel();
          _pdfReloadDebounceTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _pdfReloadKey++; // Force PDF viewer to reload
              });
              print('PDF reloaded to show formatting changes');
            }
          });
        }
      }
    } catch (e) {
      print('Error saving text formatting: $e');
    }
  }
  
  /// Delete selected text using MuPDF
  Future<void> _deleteSelectedText() async {
    if (_selectedPDFText == null || _selectedPDFTextObjectId == null) return;
    
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Replace text with empty string (effectively deletes it)
      final pdfPath = _actualFilePath ?? widget.filePath;
      final success = await MuPDFEditorService.replaceText(
        pdfPath,
        _selectedPDFText!.pageIndex,
        _selectedPDFTextObjectId!,
        '', // Empty string = delete
      );
      
      // Save PDF after modification
      if (success) {
        final saveSuccess = await MuPDFEditorService.savePdf(pdfPath);
        if (!saveSuccess) {
          print('Warning: Text deleted but save failed');
        }
      }
      
      if (mounted) {
        Navigator.pop(context);
        
        if (success) {
          setState(() {
            _selectedPDFText = null;
            _selectedPDFTextObjectId = null;
            _showTextFormattingToolbar = false;
            // Don't reload PDF immediately - it causes hangs
            // Changes will be visible when PDF is reopened or when exiting edit mode
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Text deleted'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error deleting text. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting text: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                _selectedMode = 'none';
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
                // Add new text directly to PDF (true content editing)
                _addTextToPDF(newText, position);
              }
              
              // Reset text edit mode
              setState(() {
                _isTextEditMode = false;
                _selectedMode = 'none';
                _isAddTextToolActive = false;
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


  void _showViewModeBottomSheet() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final unselectedColor = isDarkMode ? Colors.grey[400] : const Color(0xFF9E9E9E);
    
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
    // CRITICAL FIX: Get system insets to account for navigation bar height
    // On gesture navigation devices (Android 13-14), this is typically ~23px
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom; // System navigation bar height
    
    // Show all pages that can fit in the screen width
    final thumbnailWidth = 60.0; // Width of each thumbnail
    
    // Show all pages in a scrollable list
    return Container(
      // Dynamic height: base height (100) + system navigation bar padding
      // This ensures preview bar is never cut off on any Android version
      padding: EdgeInsets.only(bottom: bottomPadding),
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
      child: SizedBox(
        // Base preview bar height (100) - padding is already applied to parent Container
        height: 100,
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
                filePath: _actualFilePath ?? widget.filePath,
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
/// Custom painter to draw highlighted text overlays for edit mode
class _EditableTextHighlightsPainter extends CustomPainter {
  final List<PDFInlineTextObject> textObjects;
  final int pageIndex;
  final Size pageSize;
  final double zoomLevel;
  final double scrollOffsetY;
  final double pageSpacing;
  final Size viewerSize;
  
  _EditableTextHighlightsPainter({
    required this.textObjects,
    required this.pageIndex,
    required this.pageSize,
    required this.zoomLevel,
    required this.scrollOffsetY,
    required this.pageSpacing,
    required this.viewerSize,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Convert PDF coordinates to screen coordinates
    final scaleX = viewerSize.width / pageSize.width;
    final scaleY = (viewerSize.height / zoomLevel) / pageSize.height;
    
    // Highlight color (semi-transparent blue)
    final highlightPaint = Paint()
      ..color = const Color(0x330096FF) // Light blue with transparency
      ..style = PaintingStyle.fill;
    
    // Border color
    final borderPaint = Paint()
      ..color = const Color(0x660096FF) // Slightly darker blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    for (final textObj in textObjects) {
      if (textObj.pageIndex != pageIndex) continue;
      
      // Convert PDF coordinates (top-left origin) to screen coordinates
      final screenX = textObj.x * scaleX;
      final screenY = textObj.y * scaleY - scrollOffsetY;
      final screenWidth = textObj.width * scaleX;
      final screenHeight = textObj.height * scaleY;
      
      // Draw highlight rectangle
      final rect = Rect.fromLTWH(screenX, screenY, screenWidth, screenHeight);
      canvas.drawRect(rect, highlightPaint);
      canvas.drawRect(rect, borderPaint);
    }
  }
  
  @override
  bool shouldRepaint(_EditableTextHighlightsPainter oldDelegate) {
    return oldDelegate.textObjects.length != textObjects.length ||
           oldDelegate.zoomLevel != zoomLevel ||
           oldDelegate.scrollOffsetY != scrollOffsetY ||
           oldDelegate.pageIndex != pageIndex;
  }
}

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

/// Controller for text editing undo/redo functionality
class _TextEditorController {
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  String _currentText = '';

  /// Call this method when the user makes a text change
  void onTextChanged(String newText) {
    if (newText != _currentText) {
      _undoStack.add(_currentText);
      _currentText = newText;
      _redoStack.clear(); // Clear redo stack whenever a new change is made
    }
  }

  /// Undo last change
  String? undo() {
    if (_undoStack.isEmpty) return null;
    
    _redoStack.add(_currentText);
    _currentText = _undoStack.removeLast();
    return _currentText;
  }

  /// Redo last undone change
  String? redo() {
    if (_redoStack.isEmpty) return null;
    
    _undoStack.add(_currentText);
    _currentText = _redoStack.removeLast();
    return _currentText;
  }

  /// Get current text
  String get currentText => _currentText;

  /// Check if undo is available
  bool get canUndo => _undoStack.isNotEmpty;

  /// Check if redo is available
  bool get canRedo => _redoStack.isNotEmpty;

  /// Clear all history
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _currentText = '';
  }

  /// Set initial text
  void setInitialText(String text) {
    _currentText = text;
    _undoStack.clear();
    _redoStack.clear();
  }
}

