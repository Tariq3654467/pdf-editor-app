import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/pdf_annotation.dart';
import '../services/annotation_storage_service.dart';
import '../services/mupdf_editor_service.dart';

/// Overlay widget for text-aware PDF annotations
/// Handles drawing, erasing, and transformations for all annotation types
class TextAwareAnnotationOverlay extends StatefulWidget {
  final Widget child;
  final String pdfPath;
  final int currentPage;
  final Size pageSize; // PDF page size in points
  final double zoomLevel;
  final Offset scrollOffset;
  final Size? screenSize; // Screen size for coordinate conversion
  final String? selectedTool; // 'pen', 'highlight', 'underline', 'eraser', null
  final Color? toolColor;
  final double? strokeWidth;
  final Function(List<PDFAnnotation>)? onAnnotationsChanged;
  final Function(bool)? onUndoStateChanged;
  final Function(bool)? onRedoStateChanged;

  const TextAwareAnnotationOverlay({
    super.key,
    required this.child,
    required this.pdfPath,
    required this.currentPage,
    required this.pageSize,
    this.zoomLevel = 1.0,
    this.scrollOffset = Offset.zero,
    this.screenSize,
    this.selectedTool,
    this.toolColor,
    this.strokeWidth,
    this.onAnnotationsChanged,
    this.onUndoStateChanged,
    this.onRedoStateChanged,
  });

  @override
  State<TextAwareAnnotationOverlay> createState() => TextAwareAnnotationOverlayState();
}

class TextAwareAnnotationOverlayState extends State<TextAwareAnnotationOverlay> {
  final AnnotationStorageService _storage = AnnotationStorageService();
  List<PDFAnnotation> _annotations = [];
  List<Offset> _currentPenPath = [];
  Offset? _selectionStart;
  Offset? _selectionEnd;
  bool _isLoading = false;
  
  // Undo/Redo stacks - store annotation snapshots
  final List<List<PDFAnnotation>> _undoStack = [];
  final List<List<PDFAnnotation>> _redoStack = [];
  
  // Debug logging
  void _debugLog(String message) {
    print('TextAwareAnnotationOverlay: $message');
  }
  
  /// Get current annotations list (for external access)
  List<PDFAnnotation> get annotations => List.unmodifiable(_annotations);
  
  /// Check if undo is available
  bool get canUndo => _undoStack.isNotEmpty;
  
  /// Check if redo is available
  bool get canRedo => _redoStack.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadAnnotations();
  }
  
  /// Save current state to undo stack before making changes
  void _saveToUndoStack() {
    // Create a deep copy of current annotations
    final snapshot = _annotations.map((a) => _copyAnnotation(a)).toList();
    _undoStack.add(snapshot);
    
    // Limit undo stack size to prevent memory issues
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    
    // Clear redo stack when new action is performed
    _redoStack.clear();
    
    // Notify parent about state changes
    widget.onUndoStateChanged?.call(_undoStack.isNotEmpty);
    widget.onRedoStateChanged?.call(false);
  }
  
  /// Create a deep copy of an annotation
  PDFAnnotation _copyAnnotation(PDFAnnotation annotation) {
    if (annotation is PenAnnotation) {
      return PenAnnotation(
        id: annotation.id,
        pageIndex: annotation.pageIndex,
        points: List.from(annotation.points),
        color: annotation.color,
        strokeWidth: annotation.strokeWidth,
      );
    } else if (annotation is HighlightAnnotation) {
      return HighlightAnnotation(
        id: annotation.id,
        pageIndex: annotation.pageIndex,
        quads: annotation.quads.map((q) => TextQuad(
          topLeft: q.topLeft,
          topRight: q.topRight,
          bottomLeft: q.bottomLeft,
          bottomRight: q.bottomRight,
          pageIndex: q.pageIndex,
          text: q.text,
        )).toList(),
        color: annotation.color,
        opacity: annotation.opacity,
      );
    } else if (annotation is UnderlineAnnotation) {
      return UnderlineAnnotation(
        id: annotation.id,
        pageIndex: annotation.pageIndex,
        quads: annotation.quads.map((q) => TextQuad(
          topLeft: q.topLeft,
          topRight: q.topRight,
          bottomLeft: q.bottomLeft,
          bottomRight: q.bottomRight,
          pageIndex: q.pageIndex,
          text: q.text,
        )).toList(),
        color: annotation.color,
        strokeWidth: annotation.strokeWidth,
      );
    }
    return annotation;
  }
  
  /// Undo last action
  void undo() {
    if (_undoStack.isEmpty) return;
    
    // Save current state to redo stack
    final currentSnapshot = _annotations.map((a) => _copyAnnotation(a)).toList();
    _redoStack.add(currentSnapshot);
    
    // Restore previous state
    final previousSnapshot = _undoStack.removeLast();
    
    // Sync storage with previous state
    _syncStorageWithState(previousSnapshot);
    
    setState(() {
      _annotations = previousSnapshot.map((a) => _copyAnnotation(a)).toList();
    });
    
    // Notify parent about state changes
    widget.onUndoStateChanged?.call(_undoStack.isNotEmpty);
    widget.onRedoStateChanged?.call(_redoStack.isNotEmpty);
    widget.onAnnotationsChanged?.call(_annotations);
  }
  
  /// Redo last undone action
  void redo() {
    if (_redoStack.isEmpty) return;
    
    // Save current state to undo stack
    final currentSnapshot = _annotations.map((a) => _copyAnnotation(a)).toList();
    _undoStack.add(currentSnapshot);
    
    // Restore next state
    final nextSnapshot = _redoStack.removeLast();
    
    // Sync storage with next state
    _syncStorageWithState(nextSnapshot);
    
    setState(() {
      _annotations = nextSnapshot.map((a) => _copyAnnotation(a)).toList();
    });
    
    // Notify parent about state changes
    widget.onUndoStateChanged?.call(true);
    widget.onRedoStateChanged?.call(_redoStack.isNotEmpty);
    widget.onAnnotationsChanged?.call(_annotations);
  }
  
  /// Sync storage with a given annotation state
  Future<void> _syncStorageWithState(List<PDFAnnotation> targetState) async {
    try {
      final storedAnnotations = await _storage.loadAnnotations(widget.pdfPath);
      final storedIds = storedAnnotations.map((a) => a.id).toSet();
      final targetIds = targetState.map((a) => a.id).toSet();
      
      // Remove annotations that shouldn't be there
      for (var storedId in storedIds) {
        if (!targetIds.contains(storedId)) {
          await _storage.removeAnnotation(widget.pdfPath, storedId);
        }
      }
      
      // Add or update annotations that should be there
      for (var annotation in targetState) {
        if (!storedIds.contains(annotation.id)) {
          await _storage.addAnnotation(widget.pdfPath, annotation);
        }
      }
    } catch (e) {
      print('Error syncing storage with state: $e');
    }
  }

  @override
  void didUpdateWidget(TextAwareAnnotationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath || oldWidget.currentPage != widget.currentPage) {
      _debugLog('Widget updated: pdfPath changed=${oldWidget.pdfPath != widget.pdfPath}, page changed=${oldWidget.currentPage != widget.currentPage}');
      _loadAnnotations();
    }
    // Also reload if annotations list changed externally
    if (widget.onAnnotationsChanged != null) {
      // Force repaint when widget updates
      setState(() {});
    }
  }

  /// Load annotations for current PDF
  Future<void> _loadAnnotations() async {
    setState(() => _isLoading = true);
    try {
      final annotations = await _storage.loadAnnotations(widget.pdfPath);
      _debugLog('Loaded ${annotations.length} annotations from storage');
      _debugLog('Annotations for page ${widget.currentPage}: ${annotations.where((a) => a.pageIndex == widget.currentPage).length}');
      setState(() {
        _annotations = annotations;
        _isLoading = false;
      });
      // Update undo/redo state after loading
      widget.onUndoStateChanged?.call(_undoStack.isNotEmpty);
      widget.onRedoStateChanged?.call(_redoStack.isNotEmpty);
    } catch (e) {
      print('Error loading annotations: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Convert screen coordinates to PDF page coordinates (page-space)
  /// Formula: pPage = (pScreen + scroll - pageOriginScreen) / zoom
  /// This ensures annotations are stored in page-space and don't move with scroll/zoom
  Offset _screenToPdf(Offset screenPoint, {bool useCurrentPage = false}) {
    // Get screen size for scaling calculation
    final screenSize = widget.screenSize ?? MediaQuery.of(context).size;
    
    // Calculate rendered PDF dimensions (PDF is scaled to fit screen width)
    final pdfAspectRatio = widget.pageSize.height / widget.pageSize.width;
    final renderedPdfWidth = screenSize.width;
    final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;
    
    // Calculate page origin on screen (where current page starts in viewport)
    // For multi-page vertical scroll, each page starts at pageIndex * renderedPdfHeight
    final pageIndex = useCurrentPage 
        ? widget.currentPage 
        : ((screenPoint.dy + widget.scrollOffset.dy) / renderedPdfHeight).floor();
    final pageOriginScreen = Offset(0, pageIndex * renderedPdfHeight);
    
    // Account for scroll - screen position is relative to visible viewport
    final absoluteDocumentY = screenPoint.dy + widget.scrollOffset.dy;
    final relativeYInPage = absoluteDocumentY - pageOriginScreen.dy;
    
    // Convert to PDF page coordinates using proper formula:
    // pPage = (pScreen + scroll - pageOriginScreen) / zoom
    // Effective zoom = baseScale * widget.zoomLevel, where baseScale fits page width
    final baseScale = renderedPdfWidth / widget.pageSize.width;
    final effectiveZoom = baseScale * widget.zoomLevel;
    
    // X: Convert screen X to PDF X (accounting for zoom)
    final pdfX = (screenPoint.dx - pageOriginScreen.dx) / effectiveZoom;
    
    // Y: Convert screen Y to PDF Y (accounting for zoom and Y-axis inversion)
    // Screen: Y=0 at top, increases downward
    // PDF: Y=0 at bottom, increases upward
    // First convert to relative position in page, then invert Y-axis
    final relativeYInPageNormalized = relativeYInPage / effectiveZoom;
    final renderedPdfHeightInPageSpace = widget.pageSize.height * widget.zoomLevel;
    final screenYFromBottom = renderedPdfHeightInPageSpace - relativeYInPageNormalized;
    final pdfY = (screenYFromBottom / renderedPdfHeightInPageSpace) * widget.pageSize.height;
    
    // Clamp coordinates to page boundaries to prevent drawing outside the page
    final clampedX = pdfX.clamp(0.0, widget.pageSize.width);
    final clampedY = pdfY.clamp(0.0, widget.pageSize.height);
    
    return Offset(clampedX, clampedY);
  }

  /// Handle pan start (begin drawing/selection)
  void _onPanStart(DragStartDetails details) {
    if (widget.selectedTool == null) {
      _debugLog('No tool selected, ignoring gesture');
      return;
    }

    _debugLog('Pan start: tool=${widget.selectedTool}, position=${details.localPosition}');
    // For pen, highlight, and underline, use current page to prevent page boundary issues
    final useCurrentPage = widget.selectedTool == 'pen' || 
                          widget.selectedTool == 'highlight' || 
                          widget.selectedTool == 'underline';
    final pdfPoint = _screenToPdf(details.localPosition, useCurrentPage: useCurrentPage);
    _debugLog('Converted to PDF: $pdfPoint');

    if (widget.selectedTool == 'pen') {
      setState(() {
        _currentPenPath = [pdfPoint];
      });
      _debugLog('Started pen path with ${_currentPenPath.length} points');
    } else if (widget.selectedTool == 'highlight' || widget.selectedTool == 'underline') {
      setState(() {
        _selectionStart = pdfPoint;
        _selectionEnd = pdfPoint;
      });
      _debugLog('Started ${widget.selectedTool} selection');
    } else if (widget.selectedTool == 'eraser') {
      _eraseAtPoint(pdfPoint);
    }
  }

  /// Handle pan update (continue drawing/selection)
  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.selectedTool == null) return;

    // For pen, highlight, and underline, use current page to prevent page boundary issues
    final useCurrentPage = widget.selectedTool == 'pen' || 
                          widget.selectedTool == 'highlight' || 
                          widget.selectedTool == 'underline';
    final pdfPoint = _screenToPdf(details.localPosition, useCurrentPage: useCurrentPage);

    if (widget.selectedTool == 'pen') {
      // Prevent adding duplicate or very close points to avoid vertical lines
      if (_currentPenPath.isNotEmpty) {
        final lastPoint = _currentPenPath.last;
        final dx = (pdfPoint.dx - lastPoint.dx).abs();
        final dy = (pdfPoint.dy - lastPoint.dy).abs();
        final distance = (pdfPoint - lastPoint).distance;
        
        // Only add point if it's at least 0.5 points away (prevents vertical line artifacts)
        // Also check if movement is primarily vertical (which could cause unwanted vertical lines)
        if (distance < 0.5 || (dx < 0.1 && dy > 1.0)) {
          return;
        }
      }
      setState(() {
        _currentPenPath.add(pdfPoint);
      });
    } else if (widget.selectedTool == 'highlight' || widget.selectedTool == 'underline') {
      setState(() {
        _selectionEnd = pdfPoint;
      });
    } else if (widget.selectedTool == 'eraser') {
      // Erase continuously while dragging
      _eraseAtPoint(pdfPoint);
    }
  }

  /// Handle pan end (complete drawing/selection)
  void _onPanEnd(DragEndDetails details) async {
    if (widget.selectedTool == null) return;

    _debugLog('Pan end: tool=${widget.selectedTool}');

    if (widget.selectedTool == 'pen' && _currentPenPath.length >= 2) {
      _debugLog('Saving pen annotation with ${_currentPenPath.length} points');
      await _savePenAnnotation();
    } else if ((widget.selectedTool == 'highlight' || widget.selectedTool == 'underline') &&
               _selectionStart != null && _selectionEnd != null) {
      _debugLog('Saving ${widget.selectedTool} annotation from $_selectionStart to $_selectionEnd');
      await _saveTextAwareAnnotation();
    }

    setState(() {
      _currentPenPath.clear();
      _selectionStart = null;
      _selectionEnd = null;
    });
  }

  /// Save pen annotation
  Future<void> _savePenAnnotation() async {
    if (_currentPenPath.length < 2) return;

    // Save state to undo stack before adding annotation
    _saveToUndoStack();

    final annotation = PenAnnotation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      pageIndex: widget.currentPage,
      points: List.from(_currentPenPath), // Create copy to avoid clearing
      color: widget.toolColor ?? Colors.black,
      strokeWidth: widget.strokeWidth ?? 2.0,
    );

    _debugLog('Adding pen annotation: ${annotation.points.length} points, page=${annotation.pageIndex}');
    await _storage.addAnnotation(widget.pdfPath, annotation);
    setState(() {
      _annotations.add(annotation);
      _debugLog('Total annotations: ${_annotations.length}, for page ${widget.currentPage}: ${_annotations.where((a) => a.pageIndex == widget.currentPage).length}');
    });
    widget.onAnnotationsChanged?.call(_annotations);
  }

  /// Save text-aware highlight/underline annotation
  Future<void> _saveTextAwareAnnotation() async {
    if (_selectionStart == null || _selectionEnd == null) return;

    // Normalize selection rectangle (ensure start is top-left, end is bottom-right)
    final minX = math.min(_selectionStart!.dx, _selectionEnd!.dx);
    final maxX = math.max(_selectionStart!.dx, _selectionEnd!.dx);
    final minY = math.min(_selectionStart!.dy, _selectionEnd!.dy);
    final maxY = math.max(_selectionStart!.dy, _selectionEnd!.dy);
    
    // Calculate selection size
    final selectionWidth = maxX - minX;
    final selectionHeight = maxY - minY;
    final selectionSize = math.sqrt(selectionWidth * selectionWidth + selectionHeight * selectionHeight);
    
    // If selection is very small (like a tap), use a generous expansion
    // Otherwise, use a smaller expansion for drag selections
    final expansion = selectionSize < 20.0 ? 20.0 : 10.0; // PDF units
    
    final normalizedStart = Offset(minX - expansion, minY - expansion);
    final normalizedEnd = Offset(maxX + expansion, maxY + expansion);

    _debugLog('Getting text quads for selection: start=$normalizedStart, end=$normalizedEnd, size=$selectionSize');

    // Get text quads from MuPDF
    final jsonString = await MuPDFEditorService.getTextQuadsForSelection(
      widget.pdfPath,
      widget.currentPage,
      normalizedStart,
      normalizedEnd,
    );

    if (jsonString == null || jsonString.isEmpty) {
      _debugLog('No text quads found for selection');
      return;
    }

    try {
      final quadsJson = jsonDecode(jsonString) as List;
      if (quadsJson.isEmpty) {
        _debugLog('Empty quads array');
        return;
      }

      final quads = quadsJson.map((q) => TextQuad.fromJson(q as Map<String, dynamic>)).toList();
      _debugLog('Found ${quads.length} text quads for annotation');

      PDFAnnotation annotation;
      if (widget.selectedTool == 'highlight') {
        annotation = HighlightAnnotation(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          pageIndex: widget.currentPage,
          quads: quads,
          color: widget.toolColor ?? Colors.yellow,
          opacity: 0.4,
        );
      } else {
        annotation = UnderlineAnnotation(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          pageIndex: widget.currentPage,
          quads: quads,
          color: widget.toolColor ?? Colors.blue,
          strokeWidth: widget.strokeWidth ?? 2.0,
        );
      }

      // Save state to undo stack before adding annotation
      _saveToUndoStack();

      await _storage.addAnnotation(widget.pdfPath, annotation);
      setState(() {
        _annotations.add(annotation);
      });
      widget.onAnnotationsChanged?.call(_annotations);
      _debugLog('Successfully created ${widget.selectedTool} annotation with ${quads.length} quads');
    } catch (e) {
      _debugLog('Error parsing text quads: $e');
      print('Error parsing text quads: $e');
    }
  }

  /// Erase annotation at point
  void _eraseAtPoint(Offset pdfPoint) {
    final erasedIds = <String>[];

    _debugLog('Erasing at PDF point: $pdfPoint, checking ${_annotations.length} annotations');

    for (var annotation in _annotations) {
      // Check annotations on current page and nearby pages (for multi-page documents)
      // Allow erasing annotations that are visible in viewport
      if (annotation.pageIndex != widget.currentPage) continue;

      bool shouldErase = false;

      if (annotation is HighlightAnnotation || annotation is UnderlineAnnotation) {
        // Check if point intersects any quad
        for (var quad in (annotation is HighlightAnnotation
                ? (annotation as HighlightAnnotation).quads
                : (annotation as UnderlineAnnotation).quads)) {
          if (quad.containsPoint(pdfPoint)) {
            shouldErase = true;
            _debugLog('Found ${annotation.type} annotation to erase: ${annotation.id}');
            break;
          }
        }
      } else if (annotation is PenAnnotation) {
        // Check if point is near path - use larger tolerance for better usability
        // Tolerance is in PDF points, so 20 points ≈ 0.28 inches
        shouldErase = annotation.containsPoint(pdfPoint, tolerance: 20.0);
        if (shouldErase) {
          _debugLog('Found pen annotation to erase: ${annotation.id}');
        }
      }

      if (shouldErase) {
        erasedIds.add(annotation.id);
      }
    }

    if (erasedIds.isNotEmpty) {
      // Save state to undo stack before erasing
      _saveToUndoStack();
      
      _debugLog('Erasing ${erasedIds.length} annotation(s)');
      setState(() {
        _annotations.removeWhere((a) => erasedIds.contains(a.id));
      });
      
      // Remove from storage
      for (var id in erasedIds) {
        _storage.removeAnnotation(widget.pdfPath, id);
      }
      
      widget.onAnnotationsChanged?.call(_annotations);
    } else {
      _debugLog('No annotations found to erase at point: $pdfPoint');
    }
  }

  @override
  Widget build(BuildContext context) {
    final painter = _AnnotationPainter(
      annotations: _annotations,
      currentPage: widget.currentPage,
      currentPenPath: _currentPenPath,
      selectionStart: _selectionStart,
      selectionEnd: _selectionEnd,
      pageSize: widget.pageSize,
      zoomLevel: widget.zoomLevel,
      scrollOffset: widget.scrollOffset,
      screenSize: widget.screenSize,
      selectedTool: widget.selectedTool,
      toolColor: widget.toolColor,
      strokeWidth: widget.strokeWidth,
    );
    
    // Use Stack to ensure annotations are drawn on top of PDF viewer
    // Use Transform.translate to make annotations scroll with the PDF content
    // The overlay uses absolute document coordinates, and we translate by scroll offset
    Widget overlay = Transform.translate(
      offset: Offset(0, -widget.scrollOffset.dy),
      child: CustomPaint(
        painter: painter,
        size: Size.infinite, // Fill available space
        child: Container(), // Empty container to fill space
      ),
    );
    
    // Wrap overlay with gesture detector if tool is selected
    // Note: 'text' tool should allow taps to pass through to PDF viewer for EditText
    if (widget.selectedTool != null && widget.selectedTool != 'text') {
      overlay = Listener(
        onPointerDown: (event) {
          _onPanStart(DragStartDetails(
            globalPosition: event.position,
            localPosition: event.localPosition,
          ));
        },
        onPointerMove: (event) {
          // For eraser, always process move events to erase continuously
          // For other tools, only process if drawing/selecting
          if (widget.selectedTool == 'eraser' || 
              _currentPenPath.isNotEmpty || 
              _selectionStart != null) {
            _onPanUpdate(DragUpdateDetails(
              globalPosition: event.position,
              localPosition: event.localPosition,
              delta: event.delta,
            ));
          }
        },
        onPointerUp: (event) {
          _onPanEnd(DragEndDetails(
            velocity: Velocity.zero,
          ));
        },
        behavior: HitTestBehavior.translucent,
        child: overlay,
      );
    } else {
      // When no tool selected or text tool is selected, make overlay ignore pointer events
      // This allows EditText to work by letting taps pass through to the PDF viewer
      overlay = IgnorePointer(
        child: overlay,
      );
    }
    
    return Stack(
      children: [
        // PDF viewer as base layer
        widget.child,
        // Annotation overlay on top - scrolls with PDF content via Transform.translate
        Positioned.fill(
          child: overlay,
        ),
      ],
    );
  }
}

/// Custom painter for annotations
class _AnnotationPainter extends CustomPainter {
  final List<PDFAnnotation> annotations;
  final int currentPage;
  final List<Offset> currentPenPath;
  final Offset? selectionStart;
  final Offset? selectionEnd;
  final Size pageSize;
  final double zoomLevel;
  final Offset scrollOffset;
  final Size? screenSize;
  final String? selectedTool;
  final Color? toolColor;
  final double? strokeWidth;
  final bool debugVisuals = false; // toggle to true to visualize mapping

  _AnnotationPainter({
    required this.annotations,
    required this.currentPage,
    required this.currentPenPath,
    this.selectionStart,
    this.selectionEnd,
    required this.pageSize,
    required this.zoomLevel,
    required this.scrollOffset,
    this.screenSize,
    this.selectedTool,
    this.toolColor,
    this.strokeWidth,
  });

  /// Convert PDF page coordinates (page-space) to screen coordinates
  /// Formula: pScreen = (pPage * zoom) + pageOriginScreen - scroll
  /// Since Transform.translate handles scroll, this returns: (pPage * zoom) + pageOriginScreen
  /// Must match the inverse of _screenToPdf conversion
  /// @param pdfPoint: PDF coordinates (page-relative, bottom-left origin, in points)
  /// @param canvasSize: Size of the canvas
  /// @param annotationPageIndex: The page index where this annotation is located
  Offset _pdfToScreen(Offset pdfPoint, Size canvasSize, int annotationPageIndex) {
    // Get screen size (use canvas size if screenSize not provided)
    final screenSize = this.screenSize ?? canvasSize;
    
    // Calculate rendered PDF dimensions (PDF is scaled to fit screen width)
    final pdfAspectRatio = pageSize.height / pageSize.width;
    final renderedPdfWidth = screenSize.width;
    final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;
    
    // Calculate page origin on screen (where this page starts in viewport)
    final pageOriginScreen = Offset(0, annotationPageIndex * renderedPdfHeight);
    
    // Effective zoom = baseScale * zoomLevel, where baseScale fits page width
    final baseScale = renderedPdfWidth / pageSize.width;
    final effectiveZoom = baseScale * zoomLevel;
    
    // Convert PDF Y to screen Y (accounting for Y-axis inversion)
    // PDF: Y=0 at bottom, increases upward
    // Screen: Y=0 at top, increases downward
    final screenYFromBottom = pdfPoint.dy; // PDF Y is already from bottom
    final renderedPdfHeightInPageSpace = pageSize.height * zoomLevel;
    final relativeYInPage = (screenYFromBottom / pageSize.height) * renderedPdfHeightInPageSpace;
    final screenYFromTop = renderedPdfHeightInPageSpace - relativeYInPage;
    
    // Apply formula: pScreen = (pPage * zoom) + pageOriginScreen
    // X: PDF X to screen X
    final x = (pdfPoint.dx * effectiveZoom) + pageOriginScreen.dx;
    
    // Y: PDF Y to screen Y (with Y-axis inversion)
    final y = (screenYFromTop * effectiveZoom) + pageOriginScreen.dy;
    
    // The Transform.translate in build() will subtract scroll offset
    return Offset(x, y);
  }

  /// Draw text quad
  void _drawQuad(Canvas canvas, TextQuad quad, Paint paint, Size canvasSize, int annotationPageIndex) {
    final topLeft = _pdfToScreen(quad.topLeft, canvasSize, annotationPageIndex);
    final topRight = _pdfToScreen(quad.topRight, canvasSize, annotationPageIndex);
    final bottomLeft = _pdfToScreen(quad.bottomLeft, canvasSize, annotationPageIndex);
    final bottomRight = _pdfToScreen(quad.bottomRight, canvasSize, annotationPageIndex);

    final path = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Draw all annotations that are visible in the current viewport
    // Annotations should stay anchored to their page content, so we render all visible ones
    int drawnCount = 0;
    for (var annotation in annotations) {
      final annotationPageIndex = annotation.pageIndex;
      
      // Calculate if annotation is visible in viewport
      final screenSize = this.screenSize ?? size;
      final pdfAspectRatio = pageSize.height / pageSize.width;
      final renderedPdfWidth = screenSize.width;
      final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;
      
      final annotationPageStartY = annotationPageIndex * renderedPdfHeight;
      final annotationPageEndY = annotationPageStartY + renderedPdfHeight;
      final viewportTop = scrollOffset.dy;
      final viewportBottom = scrollOffset.dy + size.height;
      
      // Skip if annotation is completely outside viewport
      if (annotationPageEndY < viewportTop || annotationPageStartY > viewportBottom) {
        continue;
      }
      
      drawnCount++;

      if (annotation is HighlightAnnotation) {
        final paint = Paint()
          ..color = annotation.color.withOpacity(annotation.opacity)
          ..style = PaintingStyle.fill;

        for (var quad in annotation.quads) {
          _drawQuad(canvas, quad, paint, size, annotationPageIndex);
        }
      } else if (annotation is UnderlineAnnotation) {
        final paint = Paint()
          ..color = annotation.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = annotation.strokeWidth * zoomLevel;

        for (var quad in annotation.quads) {
          final start = _pdfToScreen(quad.bottomLeft, size, annotationPageIndex);
          final end = _pdfToScreen(quad.bottomRight, size, annotationPageIndex);
          canvas.drawLine(start, end, paint);
        }
      } else if (annotation is PenAnnotation) {
        if (annotation.points.length < 2) continue;

        final paint = Paint()
          ..color = annotation.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = annotation.strokeWidth * zoomLevel
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        final path = Path();
        final firstPoint = _pdfToScreen(annotation.points.first, size, annotationPageIndex);
        path.moveTo(firstPoint.dx, firstPoint.dy);

        for (var i = 1; i < annotation.points.length; i++) {
          final point = _pdfToScreen(annotation.points[i], size, annotationPageIndex);
          path.lineTo(point.dx, point.dy);
        }

        canvas.drawPath(path, paint);
      }
    }
    
    if (drawnCount > 0) {
      print('_AnnotationPainter: Drew $drawnCount annotations for page $currentPage');
    } else if (annotations.isNotEmpty) {
      print('_AnnotationPainter: No annotations for page $currentPage (total: ${annotations.length}, pages: ${annotations.map((a) => a.pageIndex).toSet()})');
    }

    // Draw current pen path (use currentPage for in-progress drawings)
    if (selectedTool == 'pen' && currentPenPath.length >= 2) {
      final paint = Paint()
        ..color = toolColor ?? Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = (strokeWidth ?? 2.0) * zoomLevel
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final firstPoint = _pdfToScreen(currentPenPath.first, size, currentPage);
      path.moveTo(firstPoint.dx, firstPoint.dy);

      for (var i = 1; i < currentPenPath.length; i++) {
        final point = _pdfToScreen(currentPenPath[i], size, currentPage);
        path.lineTo(point.dx, point.dy);
      }

      canvas.drawPath(path, paint);
    }

    // Draw selection rectangle (use currentPage for in-progress selections)
    if ((selectedTool == 'highlight' || selectedTool == 'underline') &&
        selectionStart != null && selectionEnd != null) {
      final start = _pdfToScreen(selectionStart!, size, currentPage);
      final end = _pdfToScreen(selectionEnd!, size, currentPage);

      final rect = Rect.fromPoints(start, end);
      final paint = Paint()
        ..color = (toolColor ?? Colors.yellow).withOpacity(0.3)
        ..style = PaintingStyle.fill;

      canvas.drawRect(rect, paint);

      if (selectedTool == 'underline') {
        final linePaint = Paint()
          ..color = toolColor ?? Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = (strokeWidth ?? 2.0) * zoomLevel;

        canvas.drawLine(
          Offset(rect.left, rect.bottom),
          Offset(rect.right, rect.bottom),
          linePaint,
        );
      }
    }

    // Optional debug visuals for coordinate mapping
    if (debugVisuals) {
      final debugPaint = Paint()
        ..color = const Color(0xFF00E676).withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      // Draw current page border in screen space
      final effectiveScreenSize = this.screenSize ?? size;
      final pdfAspectRatio = pageSize.height / pageSize.width;
      final renderedPdfWidth = effectiveScreenSize.width;
      final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;
      final pageOriginScreen = Offset(0, currentPage * renderedPdfHeight);
      final pageRect = Rect.fromLTWH(
        pageOriginScreen.dx,
        pageOriginScreen.dy,
        renderedPdfWidth,
        renderedPdfHeight,
      );
      canvas.drawRect(pageRect, debugPaint);

      // Sample roundtrip for a mid-page point
      final samplePdfPoint = Offset(pageSize.width / 2, pageSize.height / 2);
      final sampleScreen = _pdfToScreen(samplePdfPoint, size, currentPage);
      final roundtripBack = _screenToPdfDebug(sampleScreen, size, currentPage);
      print('DEBUG mapping: pdf=$samplePdfPoint -> screen=$sampleScreen -> pdfBack=$roundtripBack');

      // Mark the sample point
      canvas.drawCircle(sampleScreen, 4, debugPaint..style = PaintingStyle.fill);
    }
  }

  /// Debug helper: approximate inverse of _pdfToScreen for roundtrip logging only
  Offset _screenToPdfDebug(Offset screenPoint, Size canvasSize, int pageIndex) {
    final effectiveScreenSize = screenSize ?? canvasSize;
    final pdfAspectRatio = pageSize.height / pageSize.width;
    final renderedPdfWidth = effectiveScreenSize.width;
    final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;

    final pageOriginScreen = Offset(0, pageIndex * renderedPdfHeight);
    final baseScale = renderedPdfWidth / pageSize.width;
    final effectiveZoom = baseScale * zoomLevel;

    final localX = (screenPoint.dx - pageOriginScreen.dx) / effectiveZoom;

    final renderedPdfHeightInPageSpace = pageSize.height * zoomLevel;
    final localYInPage = (screenPoint.dy - pageOriginScreen.dy) / effectiveZoom;
    final screenYFromBottom = renderedPdfHeightInPageSpace - localYInPage;
    final pdfY = (screenYFromBottom / renderedPdfHeightInPageSpace) * pageSize.height;

    return Offset(localX, pdfY);
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) {
    final shouldRepaint = oldDelegate.annotations.length != annotations.length ||
        oldDelegate.annotations != annotations ||
        oldDelegate.currentPenPath != currentPenPath ||
        oldDelegate.selectionStart != selectionStart ||
        oldDelegate.selectionEnd != selectionEnd ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.selectedTool != selectedTool ||
        oldDelegate.currentPage != currentPage;
    
    if (shouldRepaint) {
      print('_AnnotationPainter: shouldRepaint=true (annotations: ${oldDelegate.annotations.length} -> ${annotations.length}, page: ${oldDelegate.currentPage} -> $currentPage)');
    }
    
    return shouldRepaint;
  }
}

