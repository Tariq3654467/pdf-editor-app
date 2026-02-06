import 'package:flutter/material.dart';

// Scan to PDF Icon - Scanner over document
class ScanToPDFPainter extends CustomPainter {
  final Color color;

  ScanToPDFPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw document background
    final docRect = Rect.fromLTWH(10, 20, 50, 60);
    canvas.drawRRect(
      RRect.fromRectAndRadius(docRect, const Radius.circular(4)),
      paint..color = Colors.white,
    );

    // Draw scanner (square with lines)
    final scannerRect = Rect.fromLTWH(25, 15, 30, 30);
    canvas.drawRRect(
      RRect.fromRectAndRadius(scannerRect, const Radius.circular(4)),
      paint..color = color,
    );

    // Draw scanner lines
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(30, 25),
      Offset(50, 25),
      linePaint,
    );
    canvas.drawLine(
      Offset(30, 30),
      Offset(50, 30),
      linePaint,
    );
    canvas.drawLine(
      Offset(30, 35),
      Offset(50, 35),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Image to PDF Icon - Image and document with arrows
class ImageToPDFPainter extends CustomPainter {
  final Color color;

  ImageToPDFPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw image (square with mountain icon)
    final imageRect = Rect.fromLTWH(5, 20, 30, 30);
    canvas.drawRRect(
      RRect.fromRectAndRadius(imageRect, const Radius.circular(4)),
      paint..color = color,
    );

    // Draw document
    final docRect = Rect.fromLTWH(45, 20, 30, 40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(docRect, const Radius.circular(4)),
      paint..color = Colors.white,
    );

    // Draw arrows between them
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(35, 35), Offset(45, 35), arrowPaint);
    // Arrow head
    canvas.drawLine(Offset(40, 30), Offset(45, 35), arrowPaint);
    canvas.drawLine(Offset(40, 40), Offset(45, 35), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Split PDF Icon - Two documents splitting
class SplitPDFPainter extends CustomPainter {
  final Color color;

  SplitPDFPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw two overlapping documents
    final doc1Rect = Rect.fromLTWH(10, 20, 35, 50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(doc1Rect, const Radius.circular(4)),
      paint..color = color,
    );

    final doc2Rect = Rect.fromLTWH(35, 20, 35, 50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(doc2Rect, const Radius.circular(4)),
      paint..color = color.withOpacity(0.6),
    );

    // Draw outward arrows
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    // Left arrow
    canvas.drawLine(Offset(5, 45), Offset(10, 45), arrowPaint);
    canvas.drawLine(Offset(8, 40), Offset(10, 45), arrowPaint);
    canvas.drawLine(Offset(8, 50), Offset(10, 45), arrowPaint);
    // Right arrow
    canvas.drawLine(Offset(70, 45), Offset(75, 45), arrowPaint);
    canvas.drawLine(Offset(72, 40), Offset(70, 45), arrowPaint);
    canvas.drawLine(Offset(72, 50), Offset(70, 45), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Merge PDF Icon - Two documents merging
class MergePDFPainter extends CustomPainter {
  final Color color;

  MergePDFPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw two documents
    final doc1Rect = Rect.fromLTWH(5, 20, 35, 50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(doc1Rect, const Radius.circular(4)),
      paint..color = color.withOpacity(0.6),
    );

    final doc2Rect = Rect.fromLTWH(40, 20, 35, 50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(doc2Rect, const Radius.circular(4)),
      paint..color = color,
    );

    // Draw inward arrows
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    // Left arrow
    canvas.drawLine(Offset(5, 45), Offset(25, 45), arrowPaint);
    canvas.drawLine(Offset(10, 40), Offset(25, 45), arrowPaint);
    canvas.drawLine(Offset(10, 50), Offset(25, 45), arrowPaint);
    // Right arrow
    canvas.drawLine(Offset(75, 45), Offset(55, 45), arrowPaint);
    canvas.drawLine(Offset(70, 40), Offset(55, 45), arrowPaint);
    canvas.drawLine(Offset(70, 50), Offset(55, 45), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Annotate Icon - Pencil drawing on document
class AnnotatePainter extends CustomPainter {
  final Color color;

  AnnotatePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw document
    final docRect = Rect.fromLTWH(15, 20, 50, 60);
    canvas.drawRRect(
      RRect.fromRectAndRadius(docRect, const Radius.circular(4)),
      paint..color = Colors.white,
    );

    // Draw curved line (annotation)
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    path.moveTo(25, 40);
    path.quadraticBezierTo(35, 30, 50, 35);
    path.quadraticBezierTo(60, 40, 55, 50);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Compress PDF Icon - Document with compression arrows
class CompressPDFPainter extends CustomPainter {
  final Color color;

  CompressPDFPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw document
    final docRect = Rect.fromLTWH(20, 25, 40, 50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(docRect, const Radius.circular(4)),
      paint..color = Colors.white,
    );

    // Draw compression arrows (vertical arrows pointing inward)
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    // Top arrow
    canvas.drawLine(Offset(40, 15), Offset(40, 25), arrowPaint);
    canvas.drawLine(Offset(35, 20), Offset(40, 25), arrowPaint);
    canvas.drawLine(Offset(45, 20), Offset(40, 25), arrowPaint);
    // Bottom arrow
    canvas.drawLine(Offset(40, 75), Offset(40, 65), arrowPaint);
    canvas.drawLine(Offset(35, 70), Offset(40, 65), arrowPaint);
    canvas.drawLine(Offset(45, 70), Offset(40, 65), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Create ZIP Icon - Folder with zipper
class CreateZIPPainter extends CustomPainter {
  final Color color;

  CreateZIPPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw folder
    final folderPath = Path()
      ..moveTo(15, 30)
      ..lineTo(15, 65)
      ..lineTo(65, 65)
      ..lineTo(65, 40)
      ..lineTo(50, 30)
      ..lineTo(15, 30);
    canvas.drawPath(folderPath, paint..color = color);

    // Draw folder tab
    final tabRect = Rect.fromLTWH(15, 30, 20, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tabRect, const Radius.circular(2)),
      paint..color = color.withOpacity(0.8),
    );

    // Draw zipper (vertical line with small rectangles)
    final zipperPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(Offset(40, 35), Offset(40, 60), zipperPaint);
    // Zipper pull tab
    final tabPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(37, 45, 6, 8),
        const Radius.circular(1),
      ),
      tabPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Print Icon - Printer
class PrintPainter extends CustomPainter {
  final Color color;

  PrintPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw printer body
    final printerRect = Rect.fromLTWH(15, 25, 50, 40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(printerRect, const Radius.circular(4)),
      paint..color = color,
    );

    // Draw paper coming out
    final paperRect = Rect.fromLTWH(25, 15, 30, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(paperRect, const Radius.circular(2)),
      paint..color = Colors.white,
    );

    // Draw control panel (small rectangle on top)
    final panelRect = Rect.fromLTWH(30, 30, 20, 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(2)),
      paint..color = Colors.white.withOpacity(0.3),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Edit PDF Text Icon - Document with text lines and edit cursor
class EditPDFTextPainter extends CustomPainter {
  final Color color;

  EditPDFTextPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw document
    final docRect = Rect.fromLTWH(15, 20, 50, 60);
    canvas.drawRRect(
      RRect.fromRectAndRadius(docRect, const Radius.circular(4)),
      paint..color = Colors.white,
    );

    // Draw text lines
    final textPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // Three horizontal lines representing text
    canvas.drawLine(Offset(20, 35), Offset(55, 35), textPaint);
    canvas.drawLine(Offset(20, 45), Offset(55, 45), textPaint);
    canvas.drawLine(Offset(20, 55), Offset(50, 55), textPaint);

    // Draw edit cursor (vertical line with caret)
    final cursorPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(50, 50), Offset(50, 60), cursorPaint);
    // Draw caret (small triangle)
    final caretPath = Path()
      ..moveTo(50, 50)
      ..lineTo(47, 53)
      ..lineTo(53, 53)
      ..close();
    canvas.drawPath(caretPath, paint..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

