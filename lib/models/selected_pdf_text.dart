import 'package:flutter/material.dart';

/// Represents selected text in PDF (for editing)
class SelectedPDFText {
  final String text;
  final Rect bounds;
  final int pageIndex;
  final Offset position; // Position in PDF coordinates
  final double fontSize;
  final Color color;
  final String? fontFamily;
  final bool isBold;
  final bool isItalic;

  SelectedPDFText({
    required this.text,
    required this.bounds,
    required this.pageIndex,
    required this.position,
    this.fontSize = 12.0,
    this.color = Colors.black,
    this.fontFamily,
    this.isBold = false,
    this.isItalic = false,
  });

  SelectedPDFText copyWith({
    String? text,
    Rect? bounds,
    int? pageIndex,
    Offset? position,
    double? fontSize,
    Color? color,
    String? fontFamily,
    bool? isBold,
    bool? isItalic,
  }) {
    return SelectedPDFText(
      text: text ?? this.text,
      bounds: bounds ?? this.bounds,
      pageIndex: pageIndex ?? this.pageIndex,
      position: position ?? this.position,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
    );
  }
}

