import 'package:flutter/material.dart';

class AnnotationPoint {
  final Offset point;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final String toolType; // 'pen', 'highlight', 'underline'

  AnnotationPoint({
    required this.point,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
    this.toolType = 'pen',
  });
}

class PDFAnnotationOverlay extends StatefulWidget {
  final Widget child;
  final Color drawingColor;
  final double strokeWidth;
  final bool isDrawing;
  final bool isEraser;
  final String toolType; // 'pen', 'highlight', 'underline'
  final VoidCallback? onClear;
  final Function(bool)? onUndoStateChanged;

  const PDFAnnotationOverlay({
    super.key,
    required this.child,
    required this.drawingColor,
    required this.strokeWidth,
    required this.isDrawing,
    required this.isEraser,
    this.toolType = 'pen',
    this.onClear,
    this.onUndoStateChanged,
  });

  @override
  State<PDFAnnotationOverlay> createState() => PDFAnnotationOverlayState();
}

class PDFAnnotationOverlayState extends State<PDFAnnotationOverlay> {
  List<List<AnnotationPoint>> _paths = [];
  List<AnnotationPoint> _currentPath = [];


  void _onPanStart(DragStartDetails details) {
    if (widget.isDrawing) {
      setState(() {
        _currentPath = [
          AnnotationPoint(
            point: details.localPosition,
            color: widget.isEraser ? Colors.white : widget.drawingColor,
            strokeWidth: widget.strokeWidth,
            isEraser: widget.isEraser,
            toolType: widget.toolType,
          ),
        ];
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.isDrawing && _currentPath.isNotEmpty) {
      setState(() {
        // For underline, only update Y position to keep horizontal line
        if (widget.toolType == 'underline') {
          final startY = _currentPath.first.point.dy;
          _currentPath.add(
            AnnotationPoint(
              point: Offset(details.localPosition.dx, startY),
              color: widget.drawingColor,
              strokeWidth: widget.strokeWidth,
              toolType: widget.toolType,
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
        widget.onUndoStateChanged?.call(true);
      });
    }
  }

  void clearAll() {
    setState(() {
      _paths.clear();
      _currentPath.clear();
    });
    widget.onClear?.call();
  }

  void undo() {
    if (_paths.isNotEmpty) {
      setState(() {
        _paths.removeLast();
        widget.onUndoStateChanged?.call(_paths.isNotEmpty);
      });
    }
  }

  bool get canUndo => _paths.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // Build the annotation painter that displays all annotations
    final annotationPainter = CustomPaint(
      painter: AnnotationPainter(
        paths: _paths,
        currentPath: _currentPath,
      ),
      child: Container(),
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

    return Stack(
      children: [
        widget.child, // PDF viewer
        overlayWidget, // Annotation overlay (interactive only when drawing)
      ],
    );
  }

  List<List<AnnotationPoint>> get annotations => _paths;
}

class AnnotationPainter extends CustomPainter {
  final List<List<AnnotationPoint>> paths;
  final List<AnnotationPoint> currentPath;

  AnnotationPainter({
    required this.paths,
    required this.currentPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw all completed paths
    for (var path in paths) {
      if (path.isEmpty) continue;
      
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
        if (firstPoint.toolType == 'underline') {
          // Draw horizontal line for underline
          final minX = path.map((p) => p.point.dx).reduce((a, b) => a < b ? a : b);
          final maxX = path.map((p) => p.point.dx).reduce((a, b) => a > b ? a : b);
          final y = path.first.point.dy;
          canvas.drawLine(Offset(minX, y), Offset(maxX, y), paint);
        } else if (firstPoint.toolType == 'highlight') {
          // Draw filled rectangle for highlight
          final minX = path.map((p) => p.point.dx).reduce((a, b) => a < b ? a : b);
          final maxX = path.map((p) => p.point.dx).reduce((a, b) => a > b ? a : b);
          final minY = path.map((p) => p.point.dy).reduce((a, b) => a < b ? a : b);
          final maxY = path.map((p) => p.point.dy).reduce((a, b) => a > b ? a : b);
          canvas.drawRect(
            Rect.fromLTRB(minX, minY - firstPoint.strokeWidth / 2, maxX, maxY + firstPoint.strokeWidth / 2),
            paint,
          );
        } else {
          // Draw freehand path for pen
          final drawingPath = Path();
          drawingPath.moveTo(path[0].point.dx, path[0].point.dy);
          for (int i = 1; i < path.length; i++) {
            drawingPath.lineTo(path[i].point.dx, path[i].point.dy);
          }
          canvas.drawPath(drawingPath, paint);
        }
      }
    }

    // Draw current path being drawn
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

      if (firstPoint.toolType == 'underline') {
        // Draw horizontal line for underline
        final minX = currentPath.map((p) => p.point.dx).reduce((a, b) => a < b ? a : b);
        final maxX = currentPath.map((p) => p.point.dx).reduce((a, b) => a > b ? a : b);
        final y = currentPath.first.point.dy;
        canvas.drawLine(Offset(minX, y), Offset(maxX, y), paint);
      } else if (firstPoint.toolType == 'highlight') {
        // Draw filled rectangle for highlight
        final minX = currentPath.map((p) => p.point.dx).reduce((a, b) => a < b ? a : b);
        final maxX = currentPath.map((p) => p.point.dx).reduce((a, b) => a > b ? a : b);
        final minY = currentPath.map((p) => p.point.dy).reduce((a, b) => a < b ? a : b);
        final maxY = currentPath.map((p) => p.point.dy).reduce((a, b) => a > b ? a : b);
        canvas.drawRect(
          Rect.fromLTRB(minX, minY - firstPoint.strokeWidth / 2, maxX, maxY + firstPoint.strokeWidth / 2),
          paint,
        );
      } else {
        // Draw freehand path for pen
        final drawingPath = Path();
        drawingPath.moveTo(currentPath[0].point.dx, currentPath[0].point.dy);
        for (int i = 1; i < currentPath.length; i++) {
          drawingPath.lineTo(currentPath[i].point.dx, currentPath[i].point.dy);
        }
        canvas.drawPath(drawingPath, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

