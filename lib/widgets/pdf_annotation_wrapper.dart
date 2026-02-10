import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'freehand_painter.dart';

/// Lightweight PDF annotation wrapper
/// Provides: Freehand, Highlight, Underline annotations
/// Uses Syncfusion PDF Viewer with CustomPainter overlay
class PDFAnnotationViewer extends StatefulWidget {
  final String filePath;
  final Color? freehandColor;
  final double? freehandStrokeWidth;
  final Color? highlightColor;
  final Color? underlineColor;
  final Function(List<Offset?>)? onAnnotationChanged;

  const PDFAnnotationViewer({
    super.key,
    required this.filePath,
    this.freehandColor,
    this.freehandStrokeWidth,
    this.highlightColor,
    this.underlineColor,
    this.onAnnotationChanged,
  });

  @override
  State<PDFAnnotationViewer> createState() => _PDFAnnotationViewerState();
}

class _PDFAnnotationViewerState extends State<PDFAnnotationViewer> {
  final PdfViewerController _controller = PdfViewerController();
  
  // Freehand drawing
  List<Offset?> _freehandPoints = [];
  List<List<Offset?>> _freehandStrokes = [];
  
  // Highlight annotations (rectangles)
  List<Rect> _highlights = [];
  Offset? _highlightStart;
  
  // Underline annotations (lines)
  List<Offset> _underlineStarts = [];
  List<Offset> _underlineEnds = [];
  Offset? _underlineStart;
  
  String _currentTool = 'none'; // 'freehand', 'highlight', 'underline', 'none'

  void setTool(String tool) {
    setState(() {
      _currentTool = tool;
      // Clear any in-progress annotations
      _highlightStart = null;
      _underlineStart = null;
    });
  }

  void clearAll() {
    setState(() {
      _freehandPoints.clear();
      _freehandStrokes.clear();
      _highlights.clear();
      _underlineStarts.clear();
      _underlineEnds.clear();
    });
    widget.onAnnotationChanged?.call([]);
  }

  void undoLast() {
    setState(() {
      if (_freehandStrokes.isNotEmpty) {
        _freehandStrokes.removeLast();
        _freehandPoints.clear();
        for (var stroke in _freehandStrokes) {
          _freehandPoints.addAll(stroke);
        }
      } else if (_highlights.isNotEmpty) {
        _highlights.removeLast();
      } else if (_underlineStarts.isNotEmpty) {
        _underlineStarts.removeLast();
        _underlineEnds.removeLast();
      }
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (_currentTool == 'none') return;
    
    setState(() {
      if (_currentTool == 'freehand') {
        _freehandPoints.add(details.localPosition);
      } else if (_currentTool == 'highlight') {
        _highlightStart = details.localPosition;
      } else if (_currentTool == 'underline') {
        _underlineStart = details.localPosition;
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentTool == 'none') return;
    
    setState(() {
      if (_currentTool == 'freehand') {
        _freehandPoints.add(details.localPosition);
      } else if (_currentTool == 'highlight' && _highlightStart != null) {
        // Update highlight rectangle
        final end = details.localPosition;
        final rect = Rect.fromPoints(_highlightStart!, end);
        // Remove old highlight and add new one (for preview)
        if (_highlights.isNotEmpty && _highlights.last.topLeft == _highlightStart) {
          _highlights.removeLast();
        }
        _highlights.add(rect);
      } else if (_currentTool == 'underline' && _underlineStart != null) {
        // Update underline end point
        final end = details.localPosition;
        if (_underlineStarts.isNotEmpty && _underlineStarts.last == _underlineStart) {
          _underlineStarts.removeLast();
          _underlineEnds.removeLast();
        }
        _underlineStarts.add(_underlineStart!);
        _underlineEnds.add(end);
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentTool == 'none') return;
    
    setState(() {
      if (_currentTool == 'freehand') {
        _freehandPoints.add(null); // Separate strokes
        _freehandStrokes.add(List.from(_freehandPoints));
      }
      // Highlight and underline are already added in panUpdate
    });
    
    widget.onAnnotationChanged?.call(_freehandPoints);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // PDF Viewer
        SfPdfViewer.file(
          widget.filePath as dynamic,
          controller: _controller,
        ),
        
        // Annotation overlay
        if (_currentTool != 'none')
          GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: CustomPaint(
              painter: _AnnotationPainter(
                freehandPoints: _freehandPoints,
                highlights: _highlights,
                underlines: _underlineStarts.asMap().entries.map((e) {
                  return Offset(_underlineStarts[e.key].dx, _underlineStarts[e.key].dy);
                }).toList(),
                underlineEnds: _underlineEnds,
                freehandColor: widget.freehandColor ?? Colors.red,
                freehandStrokeWidth: widget.freehandStrokeWidth ?? 3.0,
                highlightColor: widget.highlightColor ?? Colors.yellow.withOpacity(0.3),
                underlineColor: widget.underlineColor ?? Colors.blue,
              ),
              size: Size.infinite,
            ),
          ),
      ],
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<Offset?> freehandPoints;
  final List<Rect> highlights;
  final List<Offset> underlines;
  final List<Offset> underlineEnds;
  final Color freehandColor;
  final double freehandStrokeWidth;
  final Color highlightColor;
  final Color underlineColor;

  _AnnotationPainter({
    required this.freehandPoints,
    required this.highlights,
    required this.underlines,
    required this.underlineEnds,
    required this.freehandColor,
    required this.freehandStrokeWidth,
    required this.highlightColor,
    required this.underlineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw freehand
    if (freehandPoints.isNotEmpty) {
      final paint = Paint()
        ..color = freehandColor
        ..strokeWidth = freehandStrokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < freehandPoints.length - 1; i++) {
        if (freehandPoints[i] != null && freehandPoints[i + 1] != null) {
          canvas.drawLine(freehandPoints[i]!, freehandPoints[i + 1]!, paint);
        }
      }
    }

    // Draw highlights
    final highlightPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.fill;
    for (var rect in highlights) {
      canvas.drawRect(rect, highlightPaint);
    }

    // Draw underlines
    final underlinePaint = Paint()
      ..color = underlineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < underlines.length && i < underlineEnds.length; i++) {
      canvas.drawLine(underlines[i], underlineEnds[i], underlinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return oldDelegate.freehandPoints.length != freehandPoints.length ||
        oldDelegate.highlights.length != highlights.length ||
        oldDelegate.underlines.length != underlines.length;
  }
}

