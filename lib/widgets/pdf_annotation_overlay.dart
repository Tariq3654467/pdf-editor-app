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
  final Offset normalizedPoint; // Normalized coordinates (0-1 range) relative to page
  final double? documentY; // Absolute Y position in document (screen Y + scroll offset when drawn)

  AnnotationPoint({
    required this.point,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
    this.toolType = 'pen',
    required this.pageNumber,
    required this.normalizedPoint,
    this.documentY, // Store absolute document position (nullable for backward compatibility)
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
      final normalizedPoint = size.width > 0 && size.height > 0
          ? Offset(
              details.localPosition.dx / size.width,
              details.localPosition.dy / size.height,
            )
          : Offset.zero;
      
      setState(() {
        // Store absolute document position (screen Y + scroll offset)
        final documentY = details.localPosition.dy + widget.scrollOffset;
        _currentPath = [
          AnnotationPoint(
            point: details.localPosition,
            color: widget.isEraser ? Colors.white : widget.drawingColor,
            strokeWidth: widget.strokeWidth,
            isEraser: widget.isEraser,
            toolType: widget.toolType,
            pageNumber: widget.currentPage,
            normalizedPoint: normalizedPoint,
            documentY: documentY, // Store absolute position in document
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
        // Store absolute document position (screen Y + scroll offset)
        final documentY = details.localPosition.dy + widget.scrollOffset;
        
        // For underline, only update X position to keep horizontal line
        if (widget.toolType == 'underline') {
          final startY = _currentPath.first.point.dy;
          final startNormalizedY = _currentPath.first.normalizedPoint.dy;
          final startDocumentY = _currentPath.first.documentY;
          _currentPath.add(
            AnnotationPoint(
              point: Offset(details.localPosition.dx, startY),
              color: widget.drawingColor,
              strokeWidth: widget.strokeWidth,
              toolType: widget.toolType,
              pageNumber: widget.currentPage,
              normalizedPoint: Offset(normalizedPoint.dx, startNormalizedY),
              documentY: startDocumentY, // Keep same document Y for underline
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
              documentY: documentY, // Store absolute position in document
            ),
          );
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.isDrawing && _currentPath.isNotEmpty) {
      setState(() {
        _paths.add(List.from(_currentPath));
        _currentPath = [];
        _redoStack.clear(); // Clear redo stack when new action is performed
        widget.onUndoStateChanged?.call(true);
        widget.onRedoStateChanged?.call(false);
      });
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
    // When not drawing, use IgnorePointer to let all touches pass through to PDF viewer
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
    // Annotations are stored with normalized coordinates and will render
    // at their correct positions relative to the PDF content
    return Stack(
      children: [
        widget.child, // PDF viewer
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

  // Convert document coordinates to screen coordinates
  // documentY is the absolute position in the document
  // screenY = documentY - currentScrollOffset
  // If documentY is null (old annotations), use normalized coordinates
  Offset _documentToScreen(Offset normalizedPoint, double? documentY) {
    final screenX = normalizedPoint.dx * overlaySize.width;
    final screenY = documentY != null
        ? documentY - scrollOffset // Convert document position to screen position
        : normalizedPoint.dy * overlaySize.height; // Fallback for old annotations
    return Offset(screenX, screenY);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Update overlay size if it changed
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
        paint.color = firstPoint.color;
      } else {
        paint.style = PaintingStyle.stroke;
      }

      if (firstPoint.isEraser) {
        paint.blendMode = BlendMode.clear;
      }

      if (path.length >= 2) {
        // Convert document coordinates to screen coordinates
        final screenPoints = path.map((p) => _documentToScreen(p.normalizedPoint, p.documentY)).toList();
        
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
        paint.color = firstPoint.color;
      } else {
        paint.style = PaintingStyle.stroke;
      }

      if (firstPoint.isEraser) {
        paint.blendMode = BlendMode.clear;
      }

      // Convert document coordinates to screen coordinates
      final screenPoints = currentPath.map((p) => _documentToScreen(p.normalizedPoint, p.documentY)).toList();

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
          oldDelegate.paths.length != paths.length ||
          oldDelegate.currentPath.length != currentPath.length;
    }
    return true;
  }
}

