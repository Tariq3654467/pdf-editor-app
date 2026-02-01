import 'package:flutter/material.dart';

// Text annotation for instant text overlay (Sejda-style)
class TextAnnotation {
  final String text;
  final Offset position; // Normalized position (0-1 range)
  final Color color;
  final double fontSize;
  final int pageNumber;
  final double? documentY; // Absolute Y position in document
  final String id; // Unique identifier for editing/deleting

  TextAnnotation({
    required this.text,
    required this.position,
    required this.color,
    this.fontSize = 12.0,
    required this.pageNumber,
    this.documentY,
    String? id,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();
}

class AnnotationPoint {
  final Offset point;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final String toolType; // 'pen', 'highlight', 'underline'
  final int pageNumber; // Page number this annotation belongs to
  final Offset normalizedPoint; // Normalized coordinates (0-1 range) relative to overlay

  AnnotationPoint({
    required this.point,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
    this.toolType = 'pen',
    required this.pageNumber,
    required this.normalizedPoint,
  });
}

class PDFAnnotationOverlay extends StatefulWidget {
  final Widget child;
  final Color drawingColor;
  final double strokeWidth;
  final bool isDrawing;
  final bool isEraser;
  final String toolType; // 'pen', 'highlight', 'underline'
  final int currentPage; // Current page number
  final double scrollOffset; // Current scroll offset
  final VoidCallback? onClear;
  final Function(bool)? onUndoStateChanged;
  final Function(bool)? onRedoStateChanged;
  final List<TextAnnotation>? textAnnotations; // Text overlays
  final Function(TextAnnotation)? onTextTap; // Callback when text is tapped
  final Function(List<AnnotationPoint>)? onAnnotationComplete; // Callback when annotation is completed (to save to PDF)
  final String? pdfPath; // PDF file path for saving annotations

  const PDFAnnotationOverlay({
    super.key,
    required this.child,
    required this.drawingColor,
    required this.strokeWidth,
    required this.isDrawing,
    required this.isEraser,
    this.toolType = 'pen',
    required this.currentPage,
    this.scrollOffset = 0.0,
    this.onClear,
    this.onUndoStateChanged,
    this.onRedoStateChanged,
    this.textAnnotations,
    this.onTextTap,
    this.onAnnotationComplete,
    this.pdfPath,
  });

  @override
  State<PDFAnnotationOverlay> createState() => PDFAnnotationOverlayState();
}

class PDFAnnotationOverlayState extends State<PDFAnnotationOverlay> {
  List<List<AnnotationPoint>> _paths = [];
  List<AnnotationPoint> _currentPath = [];
  List<List<AnnotationPoint>> _redoStack = []; // For redo functionality

  void _onPanStart(DragStartDetails details) {
    if (widget.isDrawing) {
      // Get the size of the overlay to normalize coordinates
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      final size = renderBox?.size ?? Size.zero;
      
      // Normalize coordinates (0-1 range) relative to overlay size
      // These coordinates stay consistent regardless of scroll
      final normalizedPoint = size.width > 0 && size.height > 0
          ? Offset(
              details.localPosition.dx / size.width,
              details.localPosition.dy / size.height,
            )
          : Offset.zero;
      
      setState(() {
        _currentPath = [
          AnnotationPoint(
            point: details.localPosition,
            color: widget.isEraser ? Colors.white : widget.drawingColor,
            strokeWidth: widget.strokeWidth,
            isEraser: widget.isEraser,
            toolType: widget.toolType,
            pageNumber: widget.currentPage,
            normalizedPoint: normalizedPoint,
          ),
        ];
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.isDrawing && _currentPath.isNotEmpty) {
      // Get the size of the overlay to normalize coordinates
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      final size = renderBox?.size ?? Size.zero;
      
      // Normalize coordinates (0-1 range) relative to overlay size
      final normalizedPoint = size.width > 0 && size.height > 0
          ? Offset(
              details.localPosition.dx / size.width,
              details.localPosition.dy / size.height,
            )
          : Offset.zero;
      
      setState(() {
        // For underline, only update X position to keep horizontal line
        if (widget.toolType == 'underline') {
          final startY = _currentPath.first.point.dy;
          final startNormalizedY = _currentPath.first.normalizedPoint.dy;
          _currentPath.add(
            AnnotationPoint(
              point: Offset(details.localPosition.dx, startY),
              color: widget.drawingColor,
              strokeWidth: widget.strokeWidth,
              toolType: widget.toolType,
              pageNumber: widget.currentPage,
              normalizedPoint: Offset(normalizedPoint.dx, startNormalizedY),
            ),
          );
        } else {
          _currentPath.add(
            AnnotationPoint(
              point: details.localPosition,
              color: widget.isEraser ? Colors.white : widget.drawingColor,
              strokeWidth: widget.strokeWidth,
              isEraser: widget.isEraser,
              toolType: widget.toolType,
              pageNumber: widget.currentPage,
              normalizedPoint: normalizedPoint,
            ),
          );
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.isDrawing && _currentPath.isNotEmpty) {
      final completedPath = List<AnnotationPoint>.from(_currentPath);
      
      setState(() {
        _paths.add(completedPath);
        _currentPath = [];
        _redoStack.clear(); // Clear redo stack when new action is performed
        widget.onUndoStateChanged?.call(true);
        widget.onRedoStateChanged?.call(false);
      });
      
      // Save annotation directly to PDF content (not just overlay)
      if (widget.onAnnotationComplete != null) {
        widget.onAnnotationComplete!(completedPath);
      }
    }
  }

  void clearAll() {
    setState(() {
      _paths.clear();
      _currentPath.clear();
      _redoStack.clear();
    });
    widget.onClear?.call();
    widget.onUndoStateChanged?.call(false);
    widget.onRedoStateChanged?.call(false);
  }

  void undo() {
    if (_paths.isNotEmpty) {
      setState(() {
        final removedPath = _paths.removeLast();
        _redoStack.add(removedPath);
        widget.onUndoStateChanged?.call(_paths.isNotEmpty);
        widget.onRedoStateChanged?.call(_redoStack.isNotEmpty);
      });
    }
  }

  void redo() {
    if (_redoStack.isNotEmpty) {
      setState(() {
        final restoredPath = _redoStack.removeLast();
        _paths.add(restoredPath);
        widget.onUndoStateChanged?.call(true);
        widget.onRedoStateChanged?.call(_redoStack.isNotEmpty);
      });
    }
  }

  bool get canUndo => _paths.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  
  // Remove last path (used when annotation is saved to PDF)
  void removeLastPath() {
    if (_paths.isNotEmpty) {
      setState(() {
        _paths.removeLast();
        widget.onUndoStateChanged?.call(_paths.isNotEmpty);
      });
    }
  }

  Widget _buildTextOverlays(Size overlaySize) {
    if (widget.textAnnotations == null || widget.textAnnotations!.isEmpty) {
      return Container();
    }

    return Stack(
      children: widget.textAnnotations!
          .where((textAnnotation) => textAnnotation.pageNumber == widget.currentPage)
          .map((textAnnotation) {
        // Convert normalized position to screen coordinates
        final screenX = textAnnotation.position.dx * overlaySize.width;
        final screenY = textAnnotation.documentY != null
            ? textAnnotation.documentY! - widget.scrollOffset
            : textAnnotation.position.dy * overlaySize.height;

        return Positioned(
          left: screenX,
          top: screenY,
          child: GestureDetector(
            onTap: () => widget.onTextTap?.call(textAnnotation),
            child: Text(
              textAnnotation.text,
              style: TextStyle(
                color: textAnnotation.color,
                fontSize: textAnnotation.fontSize,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if we have any annotations to display or if we're currently drawing
    final hasAnnotations = _paths.isNotEmpty || _currentPath.isNotEmpty;
    final hasTextAnnotations = widget.textAnnotations != null && widget.textAnnotations!.isNotEmpty;
    final shouldShowOverlay = widget.isDrawing || hasAnnotations || hasTextAnnotations;

    // If not drawing and no annotations, return child directly without overlay
    if (!shouldShowOverlay) {
      return widget.child;
    }

    // Build the annotation painter that displays all annotations
    // Use LayoutBuilder to get the current size for coordinate transformation
    final annotationPainter = LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: AnnotationPainter(
            paths: _paths,
            currentPath: _currentPath,
            overlaySize: constraints.biggest,
            currentPage: widget.currentPage,
            scrollOffset: widget.scrollOffset,
            textAnnotations: widget.textAnnotations ?? [],
          ),
          child: _buildTextOverlays(constraints.biggest),
        );
      },
    );

    // When drawing, wrap with GestureDetector to capture drawing gestures
    final overlayWidget = widget.isDrawing
        ? GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            behavior: HitTestBehavior.opaque,
            child: annotationPainter,
          )
        : IgnorePointer(
            ignoring: true, // Ignore all touches - let them pass through to PDF viewer
            child: annotationPainter, // Still visible but doesn't block scrolling
          );

    // The overlay is positioned on top of the PDF viewer
    // Annotations are stored with normalized coordinates (0-1) relative to overlay size
    // These stay consistent regardless of scroll - overlay size represents visible PDF area
    return Stack(
      children: [
        widget.child, // PDF viewer - receives all gestures normally
        // Only add overlay if we need to show something
        if (shouldShowOverlay)
          Positioned.fill(
            child: overlayWidget, // Annotation overlay
          ),
      ],
    );
  }

  List<List<AnnotationPoint>> get annotations => _paths;
}

class AnnotationPainter extends CustomPainter {
  final List<List<AnnotationPoint>> paths;
  final List<AnnotationPoint> currentPath;
  final Size overlaySize;
  final int currentPage;
  final double scrollOffset;
  final List<TextAnnotation> textAnnotations;

  AnnotationPainter({
    required this.paths,
    required this.currentPath,
    required this.overlaySize,
    required this.currentPage,
    required this.scrollOffset,
    this.textAnnotations = const [],
  });

  // Convert normalized coordinates (0-1) to screen coordinates
  // Normalized coordinates are relative to page size, not document size
  // We need to account for scroll offset to position annotations correctly
  Offset _normalizedToScreen(Offset normalizedPoint, int pageNumber) {
    // Calculate page height (assuming all pages have same aspect ratio)
    // For vertical scrolling, each page has the same width as overlay
    final pageHeight = overlaySize.height; // This should be single page height, not document height
    
    // For now, use overlay size directly (assuming overlay represents single page viewport)
    // If overlay represents entire document, we'd need to calculate page offset
    return Offset(
      normalizedPoint.dx * overlaySize.width,
      normalizedPoint.dy * pageHeight,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Use overlaySize for coordinate conversion (represents PDF viewport)
    final effectiveSize = overlaySize.width > 0 && overlaySize.height > 0 
        ? overlaySize 
        : size;
    
    // Draw all completed paths - only show annotations for current page
    for (var path in paths) {
      if (path.isEmpty) continue;
      
      // Only draw annotations for the current page
      if (path.first.pageNumber != currentPage) continue;
      
      final firstPoint = path.first;
      final paint = Paint()
        ..color = firstPoint.color
        ..strokeWidth = firstPoint.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (firstPoint.toolType == 'highlight') {
        paint.style = PaintingStyle.fill;
        paint.color = firstPoint.color.withOpacity(0.4);
      } else {
        paint.style = PaintingStyle.stroke;
      }

      if (firstPoint.isEraser) {
        paint.blendMode = BlendMode.clear;
      }

      if (path.length >= 2) {
        // Convert normalized coordinates to screen coordinates
        // Normalized coordinates are relative to the page, not document
        final screenPoints = path.map((p) => _normalizedToScreen(p.normalizedPoint, p.pageNumber)).toList();
        
        if (firstPoint.toolType == 'underline') {
          // Draw horizontal line for underline
          final minX = screenPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
          final maxX = screenPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
          final y = screenPoints.first.dy;
          canvas.drawLine(Offset(minX, y), Offset(maxX, y), paint);
        } else if (firstPoint.toolType == 'highlight') {
          // Draw filled rectangle for highlight
          final minX = screenPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
          final maxX = screenPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
          final minY = screenPoints.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
          final maxY = screenPoints.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
          canvas.drawRect(
            Rect.fromLTRB(minX, minY - firstPoint.strokeWidth / 2, maxX, maxY + firstPoint.strokeWidth / 2),
            paint,
          );
        } else {
          // Draw freehand path for pen
          final drawingPath = Path();
          drawingPath.moveTo(screenPoints[0].dx, screenPoints[0].dy);
          for (int i = 1; i < screenPoints.length; i++) {
            drawingPath.lineTo(screenPoints[i].dx, screenPoints[i].dy);
          }
          canvas.drawPath(drawingPath, paint);
        }
      }
    }

    // Draw current path being drawn (always on current page)
    if (currentPath.length >= 2) {
      final firstPoint = currentPath.first;
      final paint = Paint()
        ..color = firstPoint.color
        ..strokeWidth = firstPoint.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (firstPoint.toolType == 'highlight') {
        paint.style = PaintingStyle.fill;
        paint.color = firstPoint.color.withOpacity(0.4);
      } else {
        paint.style = PaintingStyle.stroke;
      }

      if (firstPoint.isEraser) {
        paint.blendMode = BlendMode.clear;
      }

      // Convert normalized coordinates to screen coordinates
      // Normalized coordinates are relative to the page, not document
      final screenPoints = currentPath.map((p) => _normalizedToScreen(p.normalizedPoint, p.pageNumber)).toList();

      if (firstPoint.toolType == 'underline') {
        // Draw horizontal line for underline
        final minX = screenPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
        final maxX = screenPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
        final y = screenPoints.first.dy;
        canvas.drawLine(Offset(minX, y), Offset(maxX, y), paint);
      } else if (firstPoint.toolType == 'highlight') {
        // Draw filled rectangle for highlight
        final minX = screenPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
        final maxX = screenPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
        final minY = screenPoints.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
        final maxY = screenPoints.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
        canvas.drawRect(
          Rect.fromLTRB(minX, minY - firstPoint.strokeWidth / 2, maxX, maxY + firstPoint.strokeWidth / 2),
          paint,
        );
      } else {
        // Draw freehand path for pen
        final drawingPath = Path();
        drawingPath.moveTo(screenPoints[0].dx, screenPoints[0].dy);
        for (int i = 1; i < screenPoints.length; i++) {
          drawingPath.lineTo(screenPoints[i].dx, screenPoints[i].dy);
        }
        canvas.drawPath(drawingPath, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is AnnotationPainter) {
      return oldDelegate.overlaySize != overlaySize ||
          oldDelegate.currentPage != currentPage ||
          oldDelegate.scrollOffset != scrollOffset ||
          oldDelegate.paths.length != paths.length ||
          oldDelegate.currentPath.length != currentPath.length;
    }
    return true;
  }
}
