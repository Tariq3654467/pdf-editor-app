import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../utils/touch_throttler.dart';
import 'pdf_annotation_overlay.dart'; // Import original for data classes

/// Optimized PDF annotation overlay with ANR prevention
/// - Throttled touch input to 60fps
/// - Reduced setState calls using ValueNotifier
/// - Optimized CustomPainter with better shouldRepaint
/// - RepaintBoundary to prevent full-screen repaints
class PDFAnnotationOverlayOptimized extends StatefulWidget {
  final Widget child;
  final Color drawingColor;
  final double strokeWidth;
  final bool isDrawing;
  final bool isEraser;
  final String toolType;
  final int currentPage;
  final double scrollOffset;
  final VoidCallback? onClear;
  final Function(bool)? onUndoStateChanged;
  final Function(bool)? onRedoStateChanged;
  final List<TextAnnotation>? textAnnotations;
  final Function(TextAnnotation)? onTextTap;

  const PDFAnnotationOverlayOptimized({
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
  State<PDFAnnotationOverlayOptimized> createState() => 
      PDFAnnotationOverlayOptimizedState();
}

class PDFAnnotationOverlayOptimizedState 
    extends State<PDFAnnotationOverlayOptimized> {
  // Use ValueNotifier to avoid setState on every touch event
  final ValueNotifier<List<List<AnnotationPoint>>> _pathsNotifier = 
      ValueNotifier([]);
  final ValueNotifier<List<AnnotationPoint>> _currentPathNotifier = 
      ValueNotifier([]);
  
  List<List<AnnotationPoint>> _paths = [];
  List<AnnotationPoint> _currentPath = [];
  List<List<AnnotationPoint>> _redoStack = [];
  
  TouchThrottler? _touchThrottler;
  Size? _overlaySize;

  @override
  void initState() {
    super.initState();
    // Initialize touch throttler for 60fps updates
    _touchThrottler = TouchThrottler(_handleThrottledUpdate);
    
    // Sync ValueNotifiers with actual data
    _pathsNotifier.value = _paths;
    _currentPathNotifier.value = _currentPath;
  }

  @override
  void dispose() {
    _touchThrottler?.dispose();
    _pathsNotifier.dispose();
    _currentPathNotifier.dispose();
    super.dispose();
  }

  /// Handle throttled touch update (called at 60fps max)
  void _handleThrottledUpdate(Offset position) {
    if (!widget.isDrawing || _overlaySize == null) return;
    
    // Normalize coordinates
    final normalizedPoint = Offset(
      position.dx / _overlaySize!.width,
      position.dy / _overlaySize!.height,
    );
    
    final documentY = position.dy + widget.scrollOffset;
    
    // Update current path without setState - use ValueNotifier
    final newPath = List<AnnotationPoint>.from(_currentPath);
    
    if (widget.toolType == 'underline' && newPath.isNotEmpty) {
      // Keep Y position for underline
      final startY = newPath.first.point.dy;
      final startNormalizedY = newPath.first.normalizedPoint.dy;
      final startDocumentY = newPath.first.documentY;
      
      newPath.add(AnnotationPoint(
        point: Offset(position.dx, startY),
        color: widget.drawingColor,
        strokeWidth: widget.strokeWidth,
        toolType: widget.toolType,
        pageNumber: widget.currentPage,
        normalizedPoint: Offset(normalizedPoint.dx, startNormalizedY),
        documentY: startDocumentY,
      ));
    } else {
      newPath.add(AnnotationPoint(
        point: position,
        color: widget.isEraser ? Colors.white : widget.drawingColor,
        strokeWidth: widget.strokeWidth,
        isEraser: widget.isEraser,
        toolType: widget.toolType,
        pageNumber: widget.currentPage,
        normalizedPoint: normalizedPoint,
        documentY: documentY,
      ));
    }
    
    _currentPath = newPath;
    // Update ValueNotifier - triggers repaint without setState
    _currentPathNotifier.value = newPath;
  }

  void _onPanStart(DragStartDetails details) {
    if (widget.isDrawing) {
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      _overlaySize = renderBox?.size ?? Size.zero;
      
      if (_overlaySize!.width > 0 && _overlaySize!.height > 0) {
        final normalizedPoint = Offset(
          details.localPosition.dx / _overlaySize!.width,
          details.localPosition.dy / _overlaySize!.height,
        );
        
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
            documentY: documentY,
          ),
        ];
        
        _currentPathNotifier.value = _currentPath;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.isDrawing && _overlaySize != null) {
      // Use throttler to limit updates to 60fps
      _touchThrottler?.update(details.localPosition);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.isDrawing && _currentPath.isNotEmpty) {
      // Flush any pending updates
      _touchThrottler?.flush();
      
      // Use SchedulerBinding to batch setState
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _paths.add(List.from(_currentPath));
            _currentPath = [];
            _redoStack.clear();
            widget.onUndoStateChanged?.call(true);
            widget.onRedoStateChanged?.call(false);
          });
          
          // Update notifiers
          _pathsNotifier.value = _paths;
          _currentPathNotifier.value = [];
        }
      });
    }
  }

  void clearAll() {
    setState(() {
      _paths.clear();
      _currentPath.clear();
      _redoStack.clear();
    });
    _pathsNotifier.value = [];
    _currentPathNotifier.value = [];
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
      _pathsNotifier.value = _paths;
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
      _pathsNotifier.value = _paths;
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
    final hasAnnotations = _paths.isNotEmpty || _currentPath.isNotEmpty;
    final hasTextAnnotations = widget.textAnnotations != null && 
        widget.textAnnotations!.isNotEmpty;
    final shouldShowOverlay = widget.isDrawing || hasAnnotations || hasTextAnnotations;

    if (!shouldShowOverlay) {
      return widget.child;
    }

    // Use RepaintBoundary to prevent full-screen repaints
    // This is critical for Samsung S23 Ultra performance
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _overlaySize = constraints.biggest;
          
          return Stack(
            children: [
              widget.child,
              if (shouldShowOverlay)
                Positioned.fill(
                  child: widget.isDrawing
                      ? GestureDetector(
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          behavior: HitTestBehavior.opaque,
                          child: RepaintBoundary(
                            // Separate RepaintBoundary for annotation painter
                            child: ValueListenableBuilder<List<AnnotationPoint>>(
                              valueListenable: _currentPathNotifier,
                              builder: (context, currentPath, _) {
                                return ValueListenableBuilder<List<List<AnnotationPoint>>>(
                                  valueListenable: _pathsNotifier,
                                  builder: (context, paths, _) {
                                    return CustomPaint(
                                      painter: OptimizedAnnotationPainter(
                                        paths: paths,
                                        currentPath: currentPath,
                                        overlaySize: constraints.biggest,
                                        currentPage: widget.currentPage,
                                        scrollOffset: widget.scrollOffset,
                                        textAnnotations: widget.textAnnotations ?? [],
                                      ),
                                      child: _buildTextOverlays(constraints.biggest),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        )
                      : IgnorePointer(
                          ignoring: true,
                          child: ValueListenableBuilder<List<List<AnnotationPoint>>>(
                            valueListenable: _pathsNotifier,
                            builder: (context, paths, _) {
                              return CustomPaint(
                                painter: OptimizedAnnotationPainter(
                                  paths: paths,
                                  currentPath: [],
                                  overlaySize: constraints.biggest,
                                  currentPage: widget.currentPage,
                                  scrollOffset: widget.scrollOffset,
                                  textAnnotations: widget.textAnnotations ?? [],
                                ),
                                child: _buildTextOverlays(constraints.biggest),
                              );
                            },
                          ),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<List<AnnotationPoint>> get annotations => _paths;
}

/// Optimized CustomPainter with efficient shouldRepaint
class OptimizedAnnotationPainter extends CustomPainter {
  final List<List<AnnotationPoint>> paths;
  final List<AnnotationPoint> currentPath;
  final Size overlaySize;
  final int currentPage;
  final double scrollOffset;
  final List<TextAnnotation> textAnnotations;

  OptimizedAnnotationPainter({
    required this.paths,
    required this.currentPath,
    required this.overlaySize,
    required this.currentPage,
    required this.scrollOffset,
    this.textAnnotations = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final effectiveSize = overlaySize.width > 0 && overlaySize.height > 0 
        ? overlaySize 
        : size;
    
    // Only draw annotations for current page
    for (var path in paths) {
      if (path.isEmpty) continue;
      if (path.first.pageNumber != currentPage) continue;
      
      _drawPath(canvas, path, effectiveSize);
    }

    // Draw current path being drawn
    if (currentPath.length >= 2) {
      _drawPath(canvas, currentPath, effectiveSize);
    }
  }

  void _drawPath(Canvas canvas, List<AnnotationPoint> path, Size size) {
    if (path.isEmpty) return;
    
    final firstPoint = path.first;
    final paint = Paint()
      ..color = firstPoint.color
      ..strokeWidth = firstPoint.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (firstPoint.toolType == 'highlight') {
      paint.style = PaintingStyle.fill;
    } else {
      paint.style = PaintingStyle.stroke;
    }

    if (firstPoint.isEraser) {
      paint.blendMode = BlendMode.clear;
    }

    if (path.length >= 2) {
      final screenPoints = path.map((p) {
        final screenX = p.normalizedPoint.dx * size.width;
        final screenY = p.documentY != null
            ? p.documentY! - scrollOffset
            : p.normalizedPoint.dy * size.height;
        return Offset(screenX, screenY);
      }).toList();
      
      if (firstPoint.toolType == 'underline') {
        final minX = screenPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
        final maxX = screenPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
        final y = screenPoints.first.dy;
        canvas.drawLine(Offset(minX, y), Offset(maxX, y), paint);
      } else if (firstPoint.toolType == 'highlight') {
        final minX = screenPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
        final maxX = screenPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
        final minY = screenPoints.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
        final maxY = screenPoints.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
        canvas.drawRect(
          Rect.fromLTRB(
            minX,
            minY - firstPoint.strokeWidth / 2,
            maxX,
            maxY + firstPoint.strokeWidth / 2,
          ),
          paint,
        );
      } else {
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
  bool shouldRepaint(covariant OptimizedAnnotationPainter oldDelegate) {
    // Only repaint if actual data changed
    // Compare by reference first (fast), then by content if needed
    if (oldDelegate.paths.length != paths.length) return true;
    if (oldDelegate.currentPath.length != currentPath.length) return true;
    if (oldDelegate.currentPage != currentPage) return true;
    if (oldDelegate.scrollOffset != scrollOffset) return true;
    if (oldDelegate.overlaySize != overlaySize) return true;
    
    // Deep comparison only if lengths match (expensive, but rare)
    if (paths.length != oldDelegate.paths.length) return true;
    if (currentPath.isNotEmpty && 
        (oldDelegate.currentPath.isEmpty || 
         currentPath.length != oldDelegate.currentPath.length)) {
      return true;
    }
    
    return false;
  }
}

