import 'package:flutter/material.dart';

/// Text formatting toolbar (Sejda-style)
/// Appears when text is selected in PDF
class PDFTextFormattingToolbar extends StatefulWidget {
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final String? fontFamily;
  final double fontSize;
  final Color textColor;
  final Function(bool)? onBoldChanged;
  final Function(bool)? onItalicChanged;
  final Function(bool)? onUnderlineChanged;
  final Function(String)? onFontChanged;
  final Function(double)? onFontSizeChanged;
  final Function(Color)? onColorChanged;
  final Function(String)? onTextChanged; // New: For inline text editing
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onLink;
  final VoidCallback? onClose; // Close toolbar
  final VoidCallback? onDone; // Done button - save and close
  final bool isLoading; // Loading state for save operation

  final String? text; // Current text content for editing
  
  const PDFTextFormattingToolbar({
    super.key,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.fontFamily,
    this.fontSize = 12.0,
    this.textColor = Colors.black,
    this.text,
    this.isLoading = false,
    this.onBoldChanged,
    this.onItalicChanged,
    this.onUnderlineChanged,
    this.onFontChanged,
    this.onFontSizeChanged,
    this.onColorChanged,
    this.onTextChanged,
    this.onDelete,
    this.onCopy,
    this.onLink,
    this.onClose,
    this.onDone,
  });

  @override
  State<PDFTextFormattingToolbar> createState() => _PDFTextFormattingToolbarState();
}

class _PDFTextFormattingToolbarState extends State<PDFTextFormattingToolbar> {
  late TextEditingController _textController;
  String? _lastText;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.text ?? '');
    _lastText = widget.text;
  }

  @override
  void didUpdateWidget(PDFTextFormattingToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller if text changed externally
    if (widget.text != _lastText && widget.text != _textController.text) {
      _textController.text = widget.text ?? '';
      _lastText = widget.text;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: const Color(0xFF2196F3),
            width: 2,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Close button at top
          if (widget.onClose != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                  tooltip: 'Close',
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          // Inline text editor (Sejda-style) - Full width, prominent
          if (widget.text != null && widget.onTextChanged != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2196F3), width: 2),
              ),
              child: TextField(
                controller: _textController,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: widget.isItalic ? FontStyle.italic : FontStyle.normal,
                  color: widget.textColor,
                  fontFamily: widget.fontFamily,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  hintText: 'Type to edit text...',
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: widget.fontSize,
                  ),
                ),
                onChanged: (newText) {
                  _lastText = newText;
                  widget.onTextChanged?.call(newText);
                },
                onSubmitted: (newText) {
                  // When user presses "Done" on keyboard, save and close
                  widget.onDone?.call();
                },
                autofocus: keyboardHeight == 0, // Auto-focus only if keyboard not visible
                maxLines: null,
                textInputAction: TextInputAction.done,
              ),
            ),
          // Formatting toolbar - Modern horizontal design (Sejda-style)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              // Bold
          _buildToolbarButton(
            icon: Icons.format_bold,
            isSelected: widget.isBold,
            onTap: () => widget.onBoldChanged?.call(!widget.isBold),
            tooltip: 'Bold',
          ),
          // Italic
          _buildToolbarButton(
            icon: Icons.format_italic,
            isSelected: widget.isItalic,
            onTap: () => widget.onItalicChanged?.call(!widget.isItalic),
            tooltip: 'Italic',
          ),
          // Underline
          _buildToolbarButton(
            icon: Icons.format_underline,
            isSelected: widget.isUnderline,
            onTap: () => widget.onUnderlineChanged?.call(!widget.isUnderline),
            tooltip: 'Underline',
          ),
          // Font size - Modern design
          PopupMenuButton<double>(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.fontSize.toInt()}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
                ],
              ),
            ),
            itemBuilder: (context) => [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72]
                .map((size) => PopupMenuItem(
                      value: size.toDouble(),
                      child: Text(
                        '$size',
                        style: TextStyle(
                          fontWeight: widget.fontSize.toInt() == size ? FontWeight.bold : FontWeight.normal,
                          color: widget.fontSize.toInt() == size ? const Color(0xFF2196F3) : Colors.black87,
                        ),
                      ),
                      onTap: () => widget.onFontSizeChanged?.call(size.toDouble()),
                    ))
                .toList(),
            tooltip: 'Font Size',
          ),
          // Font family - Modern design
          PopupMenuButton<String>(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.text_fields, size: 18, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    widget.fontFamily ?? 'Font',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
                ],
              ),
            ),
            itemBuilder: (context) => [
              'Helvetica',
              'Times-Roman',
              'Courier',
              'Arial',
              'Times New Roman',
              'Roboto',
              'Open Sans',
            ]
                .map((font) => PopupMenuItem(
                      value: font,
                      child: Text(
                        font,
                        style: TextStyle(
                          fontWeight: widget.fontFamily == font ? FontWeight.bold : FontWeight.normal,
                          color: widget.fontFamily == font ? const Color(0xFF2196F3) : Colors.black87,
                        ),
                      ),
                      onTap: () => widget.onFontChanged?.call(font),
                    ))
                .toList(),
            tooltip: 'Font Family',
          ),
          // Text color - Modern design
          PopupMenuButton<Color>(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.textColor,
                  border: Border.all(color: Colors.grey[400]!, width: 2),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
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
              Colors.pink,
              Colors.teal,
              Colors.indigo,
            ]
                .map((color) => PopupMenuItem(
                      value: color,
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              border: Border.all(
                                color: widget.textColor == color ? const Color(0xFF2196F3) : Colors.grey[300]!,
                                width: widget.textColor == color ? 3 : 1,
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _getColorName(color),
                            style: TextStyle(
                              fontWeight: widget.textColor == color ? FontWeight.bold : FontWeight.normal,
                              color: widget.textColor == color ? const Color(0xFF2196F3) : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => widget.onColorChanged?.call(color),
                    ))
                .toList(),
            tooltip: 'Text Color',
          ),
                const VerticalDivider(width: 1, thickness: 1, indent: 4, endIndent: 4),
                // Link
                _buildToolbarButton(
                  icon: Icons.link,
                  onTap: widget.onLink,
                  tooltip: 'Add Link',
                ),
                // Copy
                _buildToolbarButton(
                  icon: Icons.content_copy,
                  onTap: widget.onCopy,
                  tooltip: 'Copy',
                ),
                // Delete
                _buildToolbarButton(
                  icon: Icons.delete_outline,
                  onTap: widget.onDelete,
                  tooltip: 'Delete',
                  color: Colors.red,
                ),
                const VerticalDivider(width: 1, thickness: 1, indent: 4, endIndent: 4),
                // Done button - Save and close
                if (widget.onDone != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: widget.isLoading 
                          ? Colors.grey 
                          : const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.isLoading ? null : widget.onDone,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.isLoading)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              else
                                const Icon(Icons.check, color: Colors.white, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                widget.isLoading ? 'Saving...' : 'Done',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: isSelected ? const Color(0xFF2196F3).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 22,
              color: color ?? (isSelected ? const Color(0xFF2196F3) : Colors.grey[800]),
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


