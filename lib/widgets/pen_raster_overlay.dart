import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Stroke data stored in normalized coordinates (0..1) relative to viewer
class PenStroke {
  final List<Offset> points; // Normalized coordinates (0..1)
  final Color color;
  final double strokeWidth; // In normalized units (will be scaled to page size)

  PenStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

/// Overlay widget for pen drawing using normalized coordinates
/// Stores strokes per page in normalized coordinates (0..1) relative to viewer
class PenRasterOverlay extends StatefulWidget {
  final Widget child;
  final int currentPage;
  final bool isActive; // True when pen tool is selected
  final Color penColor;
  final double penStrokeWidth;
  final Function(Map<int, List<PenStroke>>)? onStrokesChanged;

  const PenRasterOverlay({
    super.key,
    required this.child,
    required this.currentPage,
    required this.isActive,
    required this.penColor,
    required this.penStrokeWidth,
    this.onStrokesChanged,
  });

  @override
  State<PenRasterOverlay> createState() => PenRasterOverlayState();
}

class PenRasterOverlayState extends State<PenRasterOverlay> {
  // Strokes per page: pageIndex -> list of strokes
  final Map<int, List<PenStroke>> _pageStrokes = {};
  List<Offset> _currentStroke = []; // Current stroke being drawn (normalized coords)
  Size? _viewerSize; // Viewer size for normalization

  /// Get all strokes for all pages
  Map<int, List<PenStroke>> getAllStrokes() {
    return Map.from(_pageStrokes);
  }

  /// Clear all strokes
  void clearAllStrokes() {
    setState(() {
      _pageStrokes.clear();
      _currentStroke.clear();
    });
    widget.onStrokesChanged?.call(_pageStrokes);
  }

  /// Clear strokes for a specific page
  void clearPageStrokes(int pageIndex) {
    setState(() {
      _pageStrokes.remove(pageIndex);
      if (pageIndex == widget.currentPage) {
        _currentStroke.clear();
      }
    });
    widget.onStrokesChanged?.call(_pageStrokes);
  }

  /// Normalize screen coordinates to (0..1) relative to viewer
  Offset _normalizePoint(Offset screenPoint) {
    if (_viewerSize == null) {
      return Offset.zero;
    }
    return Offset(
      screenPoint.dx / _viewerSize!.width,
      screenPoint.dy / _viewerSize!.height,
    );
  }

  /// Denormalize (0..1) coordinates to screen coordinates
  Offset _denormalizePoint(Offset normalizedPoint) {
    if (_viewerSize == null) {
      return Offset.zero;
    }
    return Offset(
      normalizedPoint.dx * _viewerSize!.width,
      normalizedPoint.dy * _viewerSize!.height,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    print('PenRasterOverlay: _onPointerDown - isActive=${widget.isActive}, localPosition=${event.localPosition}');
    if (!widget.isActive) {
      print('PenRasterOverlay: Ignoring pointer down - tool not active');
      return;
    }

    final normalizedPoint = _normalizePoint(event.localPosition);
    print('PenRasterOverlay: Normalized point=$normalizedPoint');
    
    // Only update state if we actually have a valid point
    if (normalizedPoint.dx >= 0 && normalizedPoint.dy >= 0 && 
        normalizedPoint.dx <= 1 && normalizedPoint.dy <= 1) {
      print('PenRasterOverlay: Starting new stroke');
      setState(() {
        _currentStroke = [normalizedPoint];
      });
    } else {
      print('PenRasterOverlay: Invalid normalized point, ignoring');
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!widget.isActive || _currentStroke.isEmpty) return;

    final normalizedPoint = _normalizePoint(event.localPosition);
    
    // Only add point if it's far enough from last point
    if (_currentStroke.isNotEmpty) {
      final lastPoint = _currentStroke.last;
      final distance = (normalizedPoint - lastPoint).distance;
      if (distance < 0.001) return; // Skip very close points
    }

    setState(() {
      _currentStroke.add(normalizedPoint);
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.isActive || _currentStroke.length < 2) {
      _currentStroke.clear();
      return;
    }

    // Save stroke to current page
    final stroke = PenStroke(
      points: List.from(_currentStroke),
      color: widget.penColor,
      strokeWidth: widget.penStrokeWidth,
    );

    setState(() {
      _pageStrokes.putIfAbsent(widget.currentPage, () => []).add(stroke);
      _currentStroke.clear();
    });

    widget.onStrokesChanged?.call(_pageStrokes);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewerSize = constraints.biggest;

        return Stack(
          children: [
            // PDF viewer as base layer
            widget.child,
            // Pen overlay - only when active
            if (widget.isActive)
              Positioned.fill(
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  behavior: HitTestBehavior.translucent,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _PenRasterPainter(
                        pageStrokes: _pageStrokes,
                        currentPage: widget.currentPage,
                        currentStroke: _currentStroke,
                        penColor: widget.penColor,
                        penStrokeWidth: widget.penStrokeWidth,
                        viewerSize: _viewerSize ?? Size.zero,
                      ),
                      // CustomPaint is transparent by default - no child needed
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Painter for pen strokes using normalized coordinates
class _PenRasterPainter extends CustomPainter {
  final Map<int, List<PenStroke>> pageStrokes;
  final int currentPage;
  final List<Offset> currentStroke; // Normalized coordinates
  final Color penColor;
  final double penStrokeWidth;
  final Size viewerSize;

  _PenRasterPainter({
    required this.pageStrokes,
    required this.currentPage,
    required this.currentStroke,
    required this.penColor,
    required this.penStrokeWidth,
    required this.viewerSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // IMPORTANT: CustomPaint is transparent by default - we only draw strokes
    // Do NOT draw any background, fill, or rectangle - only draw the actual pen strokes
    
    // Debug: Log when painter is called
    print('_PenRasterPainter: paint() called - size=$size, currentPage=$currentPage, currentStroke.length=${currentStroke.length}, pageStrokes count=${pageStrokes[currentPage]?.length ?? 0}');
    
    // Draw strokes for current page
    final pageStrokesList = pageStrokes[currentPage] ?? [];
    
    for (final stroke in pageStrokesList) {
      _drawStroke(canvas, stroke);
    }

    // Draw current stroke being drawn (only if it has at least 2 points)
    if (currentStroke.length >= 2) {
      print('_PenRasterPainter: Drawing current stroke with ${currentStroke.length} points, color=$penColor');
      final tempStroke = PenStroke(
        points: currentStroke,
        color: penColor,
        strokeWidth: penStrokeWidth,
      );
      _drawStroke(canvas, tempStroke);
    } else if (currentStroke.length == 1) {
      print('_PenRasterPainter: Current stroke has only 1 point, not drawing yet');
    }
    
    // Do NOT draw anything else - canvas must remain transparent
    // No background, no fill, no rectangle - only stroke paths
    print('_PenRasterPainter: paint() completed - no background drawn, canvas should be transparent');
  }

  void _drawStroke(Canvas canvas, PenStroke stroke) {
    if (stroke.points.length < 2) return;

    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke // IMPORTANT: Use stroke, not fill
      ..strokeWidth = stroke.strokeWidth * viewerSize.width // Scale to viewer
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.srcOver; // Ensure proper blending

    final path = Path();
    
    // Convert normalized coordinates to screen coordinates
    final firstPoint = Offset(
      stroke.points.first.dx * viewerSize.width,
      stroke.points.first.dy * viewerSize.height,
    );
    path.moveTo(firstPoint.dx, firstPoint.dy);

    for (var i = 1; i < stroke.points.length; i++) {
      final point = Offset(
        stroke.points[i].dx * viewerSize.width,
        stroke.points[i].dy * viewerSize.height,
      );
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PenRasterPainter oldDelegate) {
    return oldDelegate.pageStrokes != pageStrokes ||
        oldDelegate.currentPage != currentPage ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.penColor != penColor ||
        oldDelegate.penStrokeWidth != penStrokeWidth ||
        oldDelegate.viewerSize != viewerSize;
  }
}

/// Render strokes for a page into a transparent PNG
/// Returns PNG bytes ready for PDF stamping
Future<Uint8List?> renderStrokesToPng(
  List<PenStroke> strokes,
  Size pageSize, // PDF page size in points
) async {
  if (strokes.isEmpty) return null;

  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, pageSize.width, pageSize.height));

    // Draw all strokes
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;

      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.strokeWidth * pageSize.width // Scale to page size
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      
      // Convert normalized coordinates to page coordinates
      final firstPoint = Offset(
        stroke.points.first.dx * pageSize.width,
        stroke.points.first.dy * pageSize.height,
      );
      path.moveTo(firstPoint.dx, firstPoint.dy);

      for (var i = 1; i < stroke.points.length; i++) {
        final point = Offset(
          stroke.points[i].dx * pageSize.width,
          stroke.points[i].dy * pageSize.height,
        );
        path.lineTo(point.dx, point.dy);
      }

      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      pageSize.width.toInt(),
      pageSize.height.toInt(),
    );

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (byteData != null) {
      return byteData.buffer.asUint8List();
    }
  } catch (e) {
    print('Error rendering strokes to PNG: $e');
  }

  return null;
}

