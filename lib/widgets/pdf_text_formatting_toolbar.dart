import 'package:flutter/material.dart';

/// Text formatting toolbar (Sejda-style)
/// Appears when text is selected in PDF
class PDFTextFormattingToolbar extends StatelessWidget {
  final bool isBold;
  final bool isItalic;
  final String? fontFamily;
  final double fontSize;
  final Color textColor;
  final Function(bool)? onBoldChanged;
  final Function(bool)? onItalicChanged;
  final Function(String)? onFontChanged;
  final Function(double)? onFontSizeChanged;
  final Function(Color)? onColorChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onLink;

  const PDFTextFormattingToolbar({
    super.key,
    this.isBold = false,
    this.isItalic = false,
    this.fontFamily,
    this.fontSize = 12.0,
    this.textColor = Colors.black,
    this.onBoldChanged,
    this.onItalicChanged,
    this.onFontChanged,
    this.onFontSizeChanged,
    this.onColorChanged,
    this.onDelete,
    this.onCopy,
    this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bold
          _buildToolbarButton(
            icon: Icons.format_bold,
            isSelected: isBold,
            onTap: () => onBoldChanged?.call(!isBold),
            tooltip: 'Bold',
          ),
          // Italic
          _buildToolbarButton(
            icon: Icons.format_italic,
            isSelected: isItalic,
            onTap: () => onItalicChanged?.call(!isItalic),
            tooltip: 'Italic',
          ),
          // Font size
          PopupMenuButton<double>(
            icon: Text(
              '${fontSize.toInt()}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            itemBuilder: (context) => [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72]
                .map((size) => PopupMenuItem(
                      value: size.toDouble(),
                      child: Text('$size'),
                      onTap: () => onFontSizeChanged?.call(size.toDouble()),
                    ))
                .toList(),
            tooltip: 'Font Size',
          ),
          // Font family
          PopupMenuButton<String>(
            icon: const Icon(Icons.text_fields, size: 18),
            itemBuilder: (context) => [
              'Helvetica',
              'Times-Roman',
              'Courier',
              'Arial',
              'Times New Roman',
            ]
                .map((font) => PopupMenuItem(
                      value: font,
                      child: Text(font),
                      onTap: () => onFontChanged?.call(font),
                    ))
                .toList(),
            tooltip: 'Font',
          ),
          // Text color
          PopupMenuButton<Color>(
            icon: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: textColor,
                border: Border.all(color: Colors.grey),
                shape: BoxShape.circle,
              ),
            ),
            itemBuilder: (context) => [
              Colors.black,
              Colors.red,
              Colors.blue,
              Colors.green,
              Colors.orange,
              Colors.purple,
              Colors.brown,
            ]
                .map((color) => PopupMenuItem(
                      value: color,
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: color,
                              border: Border.all(color: Colors.grey),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_getColorName(color)),
                        ],
                      ),
                      onTap: () => onColorChanged?.call(color),
                    ))
                .toList(),
            tooltip: 'Text Color',
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // Link
          _buildToolbarButton(
            icon: Icons.link,
            onTap: onLink,
            tooltip: 'Add Link',
          ),
          // Copy
          _buildToolbarButton(
            icon: Icons.content_copy,
            onTap: onCopy,
            tooltip: 'Copy',
          ),
          // Delete
          _buildToolbarButton(
            icon: Icons.delete,
            onTap: onDelete,
            tooltip: 'Delete',
            color: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    bool isSelected = false,
    VoidCallback? onTap,
    String? tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: color ?? (isSelected ? Colors.blue : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  String _getColorName(Color color) {
    if (color == Colors.black) return 'Black';
    if (color == Colors.red) return 'Red';
    if (color == Colors.blue) return 'Blue';
    if (color == Colors.green) return 'Green';
    if (color == Colors.orange) return 'Orange';
    if (color == Colors.purple) return 'Purple';
    if (color == Colors.brown) return 'Brown';
    return 'Custom';
  }
}

