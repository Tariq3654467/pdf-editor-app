import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/pdf_annotation.dart';
import '../services/annotation_storage_service.dart';
import '../services/mupdf_editor_service.dart';

/// Overlay widget for text-aware PDF annotations
/// Handles drawing, erasing, and transformations for all annotation types
class TextAwareAnnotationOverlay extends StatefulWidget {
  final Widget child;
  final String pdfPath;
  final int currentPage;
  final List<Size> pageSizes; // Per-page sizes in points (supports varying page sizes)
  final double zoomLevel;
  final double scrollOffsetY; // Y scroll offset in pixels (from SfPdfViewer callback)
  final double pageSpacing; // Page spacing in pixels (must match SfPdfViewer.pageSpacing)
  final Size viewerSize; // Actual viewer size from LayoutBuilder
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
    required this.pageSizes, // Per-page sizes
    required this.zoomLevel,
    required this.scrollOffsetY,
    required this.pageSpacing,
    required this.viewerSize,
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
    
    // No special handling needed for tool changes
    
    // Also reload if annotations list changed externally
    if (widget.onAnnotationsChanged != null) {
      // Force repaint when widget updates
      setState(() {});
    }
  }
  
  @override
  void dispose() {
    super.dispose();
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
  /// Uses per-page sizes with cumulative offsets to support varying page sizes
  Offset _screenToPdf(Offset screenPoint) {
    if (widget.pageSizes.isEmpty) {
      return Offset.zero; // Safety check
    }
    
    // Convert screen point to document space (add scroll offset)
    final docY = screenPoint.dy + widget.scrollOffsetY;
    
    // Find which page this point belongs to using cumulative offsets
    int pageIndex = 0;
    double cumulativeY = 0.0;
    
    for (int i = 0; i < widget.pageSizes.length; i++) {
      final pageSize = widget.pageSizes[i];
      final scale = (widget.viewerSize.width / pageSize.width) * widget.zoomLevel;
      final renderedPageHeight = pageSize.height * scale;
      final pageStride = renderedPageHeight + (widget.pageSpacing * widget.zoomLevel);
      
      if (docY < cumulativeY + pageStride) {
        pageIndex = i;
        break;
      }
      cumulativeY += pageStride;
    }
    
    // Clamp pageIndex to valid range
    pageIndex = pageIndex.clamp(0, widget.pageSizes.length - 1);
    final pageSize = widget.pageSizes[pageIndex];
    
    // Recalculate cumulative Y up to this page
    cumulativeY = 0.0;
    for (int i = 0; i < pageIndex; i++) {
      final prevPageSize = widget.pageSizes[i];
      final prevScale = (widget.viewerSize.width / prevPageSize.width) * widget.zoomLevel;
      final prevRenderedHeight = prevPageSize.height * prevScale;
      cumulativeY += prevRenderedHeight + (widget.pageSpacing * widget.zoomLevel);
    }
    
    // Calculate Y position within the current page
    final yInPageScreen = docY - cumulativeY;
    
    // Get scale for current page
    final scale = (widget.viewerSize.width / pageSize.width) * widget.zoomLevel;
    
    // Convert to PDF coordinates
    final pdfX = screenPoint.dx / scale;
    final pdfY = pageSize.height - (yInPageScreen / scale);
    
    return Offset(
      pdfX.clamp(0.0, pageSize.width),
      pdfY.clamp(0.0, pageSize.height),
    );
  }
  
  /// Convert PDF page-space point to DOCUMENT-space screen coords (not yet scrolled)
  /// Returns coordinates in document space (before scroll is applied)
  /// Uses per-page sizes with cumulative offsets to support varying page sizes
  Offset _pdfToScreenDoc(Offset pdfPoint, int pageIndex) {
    if (widget.pageSizes.isEmpty || pageIndex < 0 || pageIndex >= widget.pageSizes.length) {
      return Offset.zero; // Safety check
    }
    
    final pageSize = widget.pageSizes[pageIndex];
    final scale = (widget.viewerSize.width / pageSize.width) * widget.zoomLevel;
    
    // Calculate cumulative Y offset up to this page
    double cumulativeY = 0.0;
    for (int i = 0; i < pageIndex; i++) {
      final prevPageSize = widget.pageSizes[i];
      final prevScale = (widget.viewerSize.width / prevPageSize.width) * widget.zoomLevel;
      final prevRenderedHeight = prevPageSize.height * prevScale;
      cumulativeY += prevRenderedHeight + (widget.pageSpacing * widget.zoomLevel);
    }
    
    // Convert PDF X to screen X
    final x = pdfPoint.dx * scale;
    
    // Convert PDF Y to screen Y (accounting for Y-axis inversion)
    // PDF: Y=0 at bottom, increases upward
    // Screen: Y=0 at top, increases downward
    final yFromTopInPage = (pageSize.height - pdfPoint.dy) * scale;
    
    // Calculate document-space Y (cumulative offset + offset within page)
    final docY = cumulativeY + yFromTopInPage;
    
    return Offset(x, docY);
  }

  /// Handle pan start (begin drawing/selection)
  void _onPanStart(DragStartDetails details) {
    if (widget.selectedTool == null) {
      _debugLog('No tool selected, ignoring gesture');
      return;
    }

    _debugLog('Pan start: tool=${widget.selectedTool}, position=${details.localPosition}');
    // Convert screen point to PDF page-space coordinates
    final pdfPoint = _screenToPdf(details.localPosition);
    _debugLog('Converted to PDF: $pdfPoint');

    if (widget.selectedTool == 'pen') {
      // Start a new pen stroke on the current page
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

    // Convert screen point to PDF page-space coordinates
    final pdfPoint = _screenToPdf(details.localPosition);

    if (widget.selectedTool == 'pen') {
      // Continue current pen stroke, avoid adding too many points
      if (_currentPenPath.isNotEmpty) {
        final lastPoint = _currentPenPath.last;
        final distance = (pdfPoint - lastPoint).distance;
        // Only add point if it moved enough to avoid noisy points
        if (distance < 0.5) {
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

    if (widget.selectedTool == 'pen') {
      // Finish pen stroke and save annotation
      if (_currentPenPath.length >= 2) {
        _debugLog('Saving pen annotation with ${_currentPenPath.length} points');
        await _savePenAnnotation();
      }
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
      pageSizes: widget.pageSizes,
      zoomLevel: widget.zoomLevel,
      scrollOffsetY: widget.scrollOffsetY,
      pageSpacing: widget.pageSpacing,
      viewerSize: widget.viewerSize,
      selectedTool: widget.selectedTool,
      toolColor: widget.toolColor,
      strokeWidth: widget.strokeWidth,
    );
    
    // Use Stack to ensure annotations are drawn on top of PDF viewer
    // NO Transform.translate - scroll is applied ONCE in the painter
    Widget overlay = CustomPaint(
      painter: painter,
      size: Size.infinite, // Fill available space
      child: Container(), // Empty container to fill space
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
        // Annotation overlay on top - scroll is applied ONCE in the painter (no Transform.translate)
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
  final List<Size> pageSizes; // Per-page sizes (supports varying page sizes)
  final double zoomLevel;
  final double scrollOffsetY; // Y scroll offset in pixels
  final double pageSpacing; // Page spacing in pixels
  final Size viewerSize; // Actual viewer size
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
    required this.pageSizes, // Per-page sizes
    required this.zoomLevel,
    required this.scrollOffsetY,
    required this.pageSpacing,
    required this.viewerSize,
    this.selectedTool,
    this.toolColor,
    this.strokeWidth,
  });
  
  /// Convert PDF page-space point to DOCUMENT-space screen coords (not yet scrolled)
  /// Returns coordinates in document space (before scroll is applied)
  /// Convert PDF page-space point to DOCUMENT-space screen coords (not yet scrolled)
  /// Returns coordinates in document space (before scroll is applied)
  /// Uses per-page sizes with cumulative offsets to support varying page sizes
  Offset _pdfToScreenDoc(Offset pdfPoint, int pageIndex) {
    if (pageSizes.isEmpty || pageIndex < 0 || pageIndex >= pageSizes.length) {
      return Offset.zero; // Safety check
    }
    
    final pageSize = pageSizes[pageIndex];
    final scale = (viewerSize.width / pageSize.width) * zoomLevel;
    
    // Calculate cumulative Y offset up to this page
    double cumulativeY = 0.0;
    for (int i = 0; i < pageIndex; i++) {
      final prevPageSize = pageSizes[i];
      final prevScale = (viewerSize.width / prevPageSize.width) * zoomLevel;
      final prevRenderedHeight = prevPageSize.height * prevScale;
      cumulativeY += prevRenderedHeight + (pageSpacing * zoomLevel);
    }
    
    // Convert PDF X to screen X
    final x = pdfPoint.dx * scale;
    
    // Convert PDF Y to screen Y (accounting for Y-axis inversion)
    // PDF: Y=0 at bottom, increases upward
    // Screen: Y=0 at top, increases downward
    final yFromTopInPage = (pageSize.height - pdfPoint.dy) * scale;
    
    // Calculate document-space Y (cumulative offset + offset within page)
    final docY = cumulativeY + yFromTopInPage;
    
    return Offset(x, docY);
  }


  /// Draw text quad
  void _drawQuad(Canvas canvas, TextQuad quad, Paint paint, Size canvasSize, int annotationPageIndex) {
    // Convert to document space, then apply scroll once
    final docTopLeft = _pdfToScreenDoc(quad.topLeft, annotationPageIndex);
    final docTopRight = _pdfToScreenDoc(quad.topRight, annotationPageIndex);
    final docBottomLeft = _pdfToScreenDoc(quad.bottomLeft, annotationPageIndex);
    final docBottomRight = _pdfToScreenDoc(quad.bottomRight, annotationPageIndex);
    
    // Apply scroll ONCE to convert document space to screen space
    final topLeft = Offset(docTopLeft.dx, docTopLeft.dy - scrollOffsetY);
    final topRight = Offset(docTopRight.dx, docTopRight.dy - scrollOffsetY);
    final bottomLeft = Offset(docBottomLeft.dx, docBottomLeft.dy - scrollOffsetY);
    final bottomRight = Offset(docBottomRight.dx, docBottomRight.dy - scrollOffsetY);

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
      
      // Calculate if annotation is visible in viewport using per-page sizes with cumulative offsets
      if (annotationPageIndex < 0 || annotationPageIndex >= pageSizes.length) {
        continue; // Invalid page index
      }
      
      final annotationPageSize = pageSizes[annotationPageIndex];
      final scale = (viewerSize.width / annotationPageSize.width) * zoomLevel;
      final renderedPageHeight = annotationPageSize.height * scale;
      
      // Calculate cumulative Y offset up to this page
      double cumulativeY = 0.0;
      for (int i = 0; i < annotationPageIndex; i++) {
        final prevPageSize = pageSizes[i];
        final prevScale = (viewerSize.width / prevPageSize.width) * zoomLevel;
        final prevRenderedHeight = prevPageSize.height * prevScale;
        cumulativeY += prevRenderedHeight + (pageSpacing * zoomLevel);
      }
      
      final annotationPageStartY = cumulativeY;
      final annotationPageEndY = cumulativeY + renderedPageHeight;
      final viewportTop = scrollOffsetY;
      final viewportBottom = scrollOffsetY + size.height;
      
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
          // Convert to document space, then apply scroll once
          final docStart = _pdfToScreenDoc(quad.bottomLeft, annotationPageIndex);
          final docEnd = _pdfToScreenDoc(quad.bottomRight, annotationPageIndex);
          final start = Offset(docStart.dx, docStart.dy - scrollOffsetY);
          final end = Offset(docEnd.dx, docEnd.dy - scrollOffsetY);
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
        // Convert to document space, then apply scroll once
        final docFirstPoint = _pdfToScreenDoc(annotation.points.first, annotationPageIndex);
        final firstPoint = Offset(docFirstPoint.dx, docFirstPoint.dy - scrollOffsetY);
        path.moveTo(firstPoint.dx, firstPoint.dy);

        for (var i = 1; i < annotation.points.length; i++) {
          final docPoint = _pdfToScreenDoc(annotation.points[i], annotationPageIndex);
          final point = Offset(docPoint.dx, docPoint.dy - scrollOffsetY);
          path.lineTo(point.dx, point.dy);
        }

        canvas.drawPath(path, paint);
      }
    }
    
    // Debug logging removed to prevent log spam during scrolling
    // Uncomment if needed for debugging:
    // if (drawnCount > 0) {
    //   print('_AnnotationPainter: Drew $drawnCount annotations for page $currentPage');
    // }

    // Draw current pen path (use currentPage for in-progress drawings)
    // Note: Pen tool is now handled by PenRasterOverlay, this is legacy code
    if (selectedTool == 'pen' && currentPenPath.length >= 2) {
      final paint = Paint()
        ..color = toolColor ?? Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = (strokeWidth ?? 2.0) * zoomLevel
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      // Convert to document space, then apply scroll once
      final docFirstPoint = _pdfToScreenDoc(currentPenPath.first, currentPage);
      final firstPoint = Offset(docFirstPoint.dx, docFirstPoint.dy - scrollOffsetY);
      path.moveTo(firstPoint.dx, firstPoint.dy);

      for (var i = 1; i < currentPenPath.length; i++) {
        final docPoint = _pdfToScreenDoc(currentPenPath[i], currentPage);
        final point = Offset(docPoint.dx, docPoint.dy - scrollOffsetY);
        path.lineTo(point.dx, point.dy);
      }

      canvas.drawPath(path, paint);
    }

    // Draw selection rectangle (use currentPage for in-progress selections)
    if ((selectedTool == 'highlight' || selectedTool == 'underline') &&
        selectionStart != null && selectionEnd != null) {
      // Convert to document space, then apply scroll once
      final docStart = _pdfToScreenDoc(selectionStart!, currentPage);
      final docEnd = _pdfToScreenDoc(selectionEnd!, currentPage);
      final start = Offset(docStart.dx, docStart.dy - scrollOffsetY);
      final end = Offset(docEnd.dx, docEnd.dy - scrollOffsetY);

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

      // Draw current page border in screen space using per-page sizes with cumulative offsets
      if (currentPage >= 0 && currentPage < pageSizes.length) {
        final currentPageSize = pageSizes[currentPage];
        final scale = (viewerSize.width / currentPageSize.width) * zoomLevel;
        final renderedPageHeight = currentPageSize.height * scale;
        
        // Calculate cumulative Y offset up to this page
        double cumulativeY = 0.0;
        for (int i = 0; i < currentPage; i++) {
          final prevPageSize = pageSizes[i];
          final prevScale = (viewerSize.width / prevPageSize.width) * zoomLevel;
          final prevRenderedHeight = prevPageSize.height * prevScale;
          cumulativeY += prevRenderedHeight + (pageSpacing * zoomLevel);
        }
        
        final pageRect = Rect.fromLTWH(
          0,
          cumulativeY - scrollOffsetY, // Apply scroll to convert to screen space
          viewerSize.width,
          renderedPageHeight,
        );
        canvas.drawRect(pageRect, debugPaint);

        // Sample roundtrip for a mid-page point
        final samplePdfPoint = Offset(currentPageSize.width / 2, currentPageSize.height / 2);
        final docSample = _pdfToScreenDoc(samplePdfPoint, currentPage);
        final sampleScreen = Offset(docSample.dx, docSample.dy - scrollOffsetY);
        print('DEBUG mapping: pdf=$samplePdfPoint -> doc=$docSample -> screen=$sampleScreen');
        
        // Mark the sample point
        canvas.drawCircle(sampleScreen, 4, debugPaint..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) {
    // Check for significant changes that require repaint
    // Use tolerance for scrollOffsetY to avoid repainting on every tiny scroll change
    const scrollTolerance = 0.5; // Only repaint if scroll changed by more than 0.5 pixels
    
    return oldDelegate.annotations.length != annotations.length ||
        oldDelegate.annotations != annotations ||
        oldDelegate.currentPenPath != currentPenPath ||
        oldDelegate.selectionStart != selectionStart ||
        oldDelegate.selectionEnd != selectionEnd ||
        (oldDelegate.zoomLevel - zoomLevel).abs() > 0.001 || // Zoom tolerance
        (oldDelegate.scrollOffsetY - scrollOffsetY).abs() > scrollTolerance || // Scroll tolerance
        oldDelegate.selectedTool != selectedTool ||
        oldDelegate.currentPage != currentPage;
  }
}

