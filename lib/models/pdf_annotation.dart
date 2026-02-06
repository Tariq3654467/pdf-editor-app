import 'package:flutter/material.dart';

/// Text quad (bounding rectangle) for text-aware annotations
/// PDF coordinates use bottom-left origin
class TextQuad {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomLeft;
  final Offset bottomRight;
  final int pageIndex;
  final String? text; // Optional: the actual text content
  final String? objectId; // Optional: MuPDF text object identifier for editing

  TextQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.pageIndex,
    this.text,
    this.objectId,
  });
  
  /// Create from JSON
  factory TextQuad.fromJson(Map<String, dynamic> json) {
    return TextQuad(
      topLeft: Offset(
        (json['topLeft']?['x'] ?? json['topLeft']?['dx'] ?? 0.0).toDouble(),
        (json['topLeft']?['y'] ?? json['topLeft']?['dy'] ?? 0.0).toDouble(),
      ),
      topRight: Offset(
        (json['topRight']?['x'] ?? json['topRight']?['dx'] ?? 0.0).toDouble(),
        (json['topRight']?['y'] ?? json['topRight']?['dy'] ?? 0.0).toDouble(),
      ),
      bottomLeft: Offset(
        (json['bottomLeft']?['x'] ?? json['bottomLeft']?['dx'] ?? 0.0).toDouble(),
        (json['bottomLeft']?['y'] ?? json['bottomLeft']?['dy'] ?? 0.0).toDouble(),
      ),
      bottomRight: Offset(
        (json['bottomRight']?['x'] ?? json['bottomRight']?['dx'] ?? 0.0).toDouble(),
        (json['bottomRight']?['y'] ?? json['bottomRight']?['dy'] ?? 0.0).toDouble(),
      ),
      pageIndex: json['pageIndex'] ?? json['page'] ?? 0,
      text: json['text'],
      objectId: json['objectId'],
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'topLeft': {'x': topLeft.dx, 'y': topLeft.dy},
      'topRight': {'x': topRight.dx, 'y': topRight.dy},
      'bottomLeft': {'x': bottomLeft.dx, 'y': bottomLeft.dy},
      'bottomRight': {'x': bottomRight.dx, 'y': bottomRight.dy},
      'pageIndex': pageIndex,
      'text': text,
      'objectId': objectId,
    };
  }

  /// Get bounding rectangle
  Rect get bounds {
    final minX = [topLeft.dx, topRight.dx, bottomLeft.dx, bottomRight.dx].reduce((a, b) => a < b ? a : b);
    final maxX = [topLeft.dx, topRight.dx, bottomLeft.dx, bottomRight.dx].reduce((a, b) => a > b ? a : b);
    final minY = [topLeft.dy, topRight.dy, bottomLeft.dy, bottomRight.dy].reduce((a, b) => a < b ? a : b);
    final maxY = [topLeft.dy, topRight.dy, bottomLeft.dy, bottomRight.dy].reduce((a, b) => a > b ? a : b);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Check if point intersects this quad
  bool containsPoint(Offset point) {
    // Simple bounding box check (can be improved with polygon intersection)
    return bounds.contains(point);
  }
}

/// Base class for all PDF annotations
abstract class PDFAnnotation {
  final String id;
  final int pageIndex;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final String type; // 'highlight', 'underline', 'pen', 'text'

  PDFAnnotation({
    required this.id,
    required this.pageIndex,
    required this.type,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       modifiedAt = modifiedAt;

  Map<String, dynamic> toJson();
}

/// Text-aware highlight annotation
class HighlightAnnotation extends PDFAnnotation {
  final List<TextQuad> quads;
  final Color color;
  final double opacity;

  HighlightAnnotation({
    required super.id,
    required super.pageIndex,
    required this.quads,
    this.color = Colors.yellow,
    this.opacity = 0.4,
    super.createdAt,
    super.modifiedAt,
  }) : super(type: 'highlight');

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'pageIndex': pageIndex,
      'quads': quads.map((q) => q.toJson()).toList(),
      'color': {
        'r': color.red,
        'g': color.green,
        'b': color.blue,
        'a': color.alpha,
      },
      'opacity': opacity,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt?.toIso8601String(),
    };
  }

  factory HighlightAnnotation.fromJson(Map<String, dynamic> json) {
    return HighlightAnnotation(
      id: json['id'],
      pageIndex: json['pageIndex'],
      quads: (json['quads'] as List).map((q) => TextQuad.fromJson(q)).toList(),
      color: Color.fromARGB(
        json['color']['a'] ?? 255,
        json['color']['r'],
        json['color']['g'],
        json['color']['b'],
      ),
      opacity: json['opacity'] ?? 0.4,
      createdAt: DateTime.parse(json['createdAt']),
      modifiedAt: json['modifiedAt'] != null ? DateTime.parse(json['modifiedAt']) : null,
    );
  }
}

/// Text-aware underline annotation
class UnderlineAnnotation extends PDFAnnotation {
  final List<TextQuad> quads;
  final Color color;
  final double strokeWidth;

  UnderlineAnnotation({
    required super.id,
    required super.pageIndex,
    required this.quads,
    this.color = Colors.blue,
    this.strokeWidth = 2.0,
    super.createdAt,
    super.modifiedAt,
  }) : super(type: 'underline');

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'pageIndex': pageIndex,
      'quads': quads.map((q) => q.toJson()).toList(),
      'color': {
        'r': color.red,
        'g': color.green,
        'b': color.blue,
        'a': color.alpha,
      },
      'strokeWidth': strokeWidth,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt?.toIso8601String(),
    };
  }

  factory UnderlineAnnotation.fromJson(Map<String, dynamic> json) {
    return UnderlineAnnotation(
      id: json['id'],
      pageIndex: json['pageIndex'],
      quads: (json['quads'] as List).map((q) => TextQuad.fromJson(q)).toList(),
      color: Color.fromARGB(
        json['color']['a'] ?? 255,
        json['color']['r'],
        json['color']['g'],
        json['color']['b'],
      ),
      strokeWidth: json['strokeWidth'] ?? 2.0,
      createdAt: DateTime.parse(json['createdAt']),
      modifiedAt: json['modifiedAt'] != null ? DateTime.parse(json['modifiedAt']) : null,
    );
  }
}

/// Freehand pen annotation (page coordinates)
class PenAnnotation extends PDFAnnotation {
  final List<Offset> points; // Page coordinates (PDF space)
  final Color color;
  final double strokeWidth;

  PenAnnotation({
    required super.id,
    required super.pageIndex,
    required this.points,
    this.color = Colors.black,
    this.strokeWidth = 2.0,
    super.createdAt,
    super.modifiedAt,
  }) : super(type: 'pen');

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'pageIndex': pageIndex,
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'color': {
        'r': color.red,
        'g': color.green,
        'b': color.blue,
        'a': color.alpha,
      },
      'strokeWidth': strokeWidth,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt?.toIso8601String(),
    };
  }

  factory PenAnnotation.fromJson(Map<String, dynamic> json) {
    return PenAnnotation(
      id: json['id'],
      pageIndex: json['pageIndex'],
      points: (json['points'] as List).map((p) => Offset(p['x'], p['y'])).toList(),
      color: Color.fromARGB(
        json['color']['a'] ?? 255,
        json['color']['r'],
        json['color']['g'],
        json['color']['b'],
      ),
      strokeWidth: json['strokeWidth'] ?? 2.0,
      createdAt: DateTime.parse(json['createdAt']),
      modifiedAt: json['modifiedAt'] != null ? DateTime.parse(json['modifiedAt']) : null,
    );
  }

  /// Check if point intersects this path (for eraser)
  bool containsPoint(Offset point, {double tolerance = 5.0}) {
    for (var i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final distance = _pointToLineDistance(point, p1, p2);
      if (distance <= tolerance) {
        return true;
      }
    }
    return false;
  }

  double _pointToLineDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final A = point.dx - lineStart.dx;
    final B = point.dy - lineStart.dy;
    final C = lineEnd.dx - lineStart.dx;
    final D = lineEnd.dy - lineStart.dy;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    if (lenSq == 0) {
      return Offset(point.dx - lineStart.dx, point.dy - lineStart.dy).distance;
    }

    final param = dot / lenSq;
    Offset closest;
    if (param < 0) {
      closest = lineStart;
    } else if (param > 1) {
      closest = lineEnd;
    } else {
      closest = Offset(lineStart.dx + param * C, lineStart.dy + param * D);
    }

    return Offset(point.dx - closest.dx, point.dy - closest.dy).distance;
  }
}

/// Factory to create annotations from JSON
extension PDFAnnotationFactory on PDFAnnotation {
  static PDFAnnotation fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'highlight':
        return HighlightAnnotation.fromJson(json);
      case 'underline':
        return UnderlineAnnotation.fromJson(json);
      case 'pen':
        return PenAnnotation.fromJson(json);
      default:
        throw UnimplementedError('Unknown annotation type: $type');
    }
  }
}

