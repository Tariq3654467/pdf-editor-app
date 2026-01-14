import 'package:flutter/material.dart';

class PDFIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Draw white document/page shape
    final documentPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final documentRect = Rect.fromLTWH(20, 15, 60, 75);
    canvas.drawRRect(
      RRect.fromRectAndRadius(documentRect, const Radius.circular(4)),
      documentPaint,
    );

    // Draw fold corner (upper right) - white triangle
    final foldPath = Path()
      ..moveTo(80, 15)
      ..lineTo(80, 30)
      ..lineTo(95, 15)
      ..close();
    canvas.drawPath(foldPath, documentPaint);

    // Draw three grey horizontal lines representing text
    final linePaint = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      const Offset(28, 40),
      const Offset(68, 40),
      linePaint,
    );
    canvas.drawLine(
      const Offset(28, 50),
      const Offset(68, 50),
      linePaint,
    );
    canvas.drawLine(
      const Offset(28, 60),
      const Offset(65, 60),
      linePaint,
    );

    // Draw green pencil icon in top-left of document
    final pencilPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.fill;

    // Pencil body (small rectangle)
    final pencilRect = Rect.fromLTWH(25, 20, 8, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pencilRect, const Radius.circular(2)),
      pencilPaint,
    );

    // Pencil tip (triangle)
    final pencilTipPath = Path()
      ..moveTo(25, 32)
      ..lineTo(33, 32)
      ..lineTo(29, 36)
      ..close();
    canvas.drawPath(pencilTipPath, pencilPaint);

    // Draw red "PDF" banner at the bottom of document
    final bannerPaint = Paint()
      ..color = const Color(0xFFE53935)
      ..style = PaintingStyle.fill;

    final bannerRect = Rect.fromLTWH(20, 80, 60, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bannerRect, const Radius.circular(2)),
      bannerPaint,
    );

    // Draw "PDF" text on banner
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'PDF',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        82,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
