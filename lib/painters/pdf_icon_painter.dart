import 'package:flutter/material.dart';

class PDFIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw document/page shape
    final rect = Rect.fromLTWH(15, 10, 50, 70);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      fillPaint,
    );

    // Draw fold corner (upper right)
    final path = Path()
      ..moveTo(15 + 50, 10)
      ..lineTo(15 + 50, 25)
      ..lineTo(15 + 50 + 12, 10)
      ..close();
    canvas.drawPath(path, fillPaint);

    // Draw lines on document (red lines)
    final linePaint = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Three horizontal lines representing text
    canvas.drawLine(
      const Offset(20, 35),
      const Offset(55, 35),
      linePaint,
    );
    canvas.drawLine(
      const Offset(20, 45),
      const Offset(55, 45),
      linePaint,
    );
    canvas.drawLine(
      const Offset(20, 55),
      const Offset(45, 55),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
