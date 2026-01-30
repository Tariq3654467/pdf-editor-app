import 'package:flutter/material.dart';
import '../models/pdf_file.dart';
import '../services/pdf_cache_service.dart';
import '../services/pdf_preferences_service.dart';
import '../services/theme_service.dart';

/// In-app file picker that shows PDFs managed by the app
class InAppFilePicker extends StatefulWidget {
  final bool allowMultiSelect;
  final Function(List<String>)? onFilesSelected;
  final String? title;

  const InAppFilePicker({
    super.key,
    this.allowMultiSelect = false,
    this.onFilesSelected,
    this.title,
  });

  @override
  State<InAppFilePicker> createState() => _InAppFilePickerState();
}

class _InAppFilePickerState extends State<InAppFilePicker> {
  List<PDFFile> _pdfFiles = [];
  Set<String> _selectedFiles = {};
  bool _isLoading = true;
  int _selectedTabIndex = 0; // 0: All, 1: Recent

  @override
  void initState() {
    super.initState();
    _loadPDFs();
  }

  Future<void> _loadPDFs() async {
    setState(() => _isLoading = true);
    try {
      final pdfs = await PDFCacheService.loadPDFList();
      if (mounted) {
        setState(() {
          _pdfFiles = pdfs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<PDFFile> _getFilteredPDFs() {
    if (_selectedTabIndex == 0) {
      return _pdfFiles;
    } else {
      // Recent files
      final recentFiles = _pdfFiles.where((pdf) => pdf.lastAccessed != null).toList();
      recentFiles.sort((a, b) {
        if (a.lastAccessed == null) return 1;
        if (b.lastAccessed == null) return -1;
        return b.lastAccessed!.compareTo(a.lastAccessed!);
      });
      return recentFiles;
    }
  }

  void _toggleSelection(String filePath) {
    setState(() {
      if (_selectedFiles.contains(filePath)) {
        _selectedFiles.remove(filePath);
      } else {
        if (widget.allowMultiSelect) {
          _selectedFiles.add(filePath);
        } else {
          _selectedFiles.clear();
          _selectedFiles.add(filePath);
        }
      }
    });
  }

  void _confirmSelection() {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one file'),
        ),
      );
      return;
    }
    
    // Call callback if provided
    widget.onFilesSelected?.call(_selectedFiles.toList());
    
    // Return selected files via Navigator.pop() for use with Navigator.push
    Navigator.of(context).pop(_selectedFiles.toList());
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ThemeService.isDarkMode(context);
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : const Color(0xFF9E9E9E);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title ?? (widget.allowMultiSelect ? 'Select PDFs' : 'Select PDF'),
          style: TextStyle(color: textColor),
        ),
        actions: [
          if (widget.allowMultiSelect)
            TextButton(
              onPressed: _confirmSelection,
              child: Text(
                'Select (${_selectedFiles.length})',
                style: TextStyle(
                  color: _selectedFiles.isEmpty
                      ? secondaryTextColor
                      : const Color(0xFFE53935),
                ),
              ),
            )
          else if (_selectedFiles.isNotEmpty)
            TextButton(
              onPressed: _confirmSelection,
              child: Text(
                'Select',
                style: const TextStyle(
                  color: Color(0xFFE53935),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Tabs
          Container(
            color: backgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: _buildTab('All PDFs', 0, isDarkMode),
                ),
                Expanded(
                  child: _buildTab('Recent', 1, isDarkMode),
                ),
              ],
            ),
          ),
          // File list
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFFE53935),
                      ),
                    ),
                  )
                : _buildFileList(isDarkMode, textColor, secondaryTextColor ?? Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, bool isDarkMode) {
    final isActive = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFFE53935) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive
                ? const Color(0xFFE53935)
                : (isDarkMode ? Colors.grey[400] : const Color(0xFF9E9E9E)),
            fontSize: 16,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFileList(bool isDarkMode, Color textColor, Color secondaryTextColor) {
    final filteredPDFs = _getFilteredPDFs();

    if (filteredPDFs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: secondaryTextColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No PDFs found',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredPDFs.length,
      itemBuilder: (context, index) {
        final pdf = filteredPDFs[index];
        final isSelected = pdf.filePath != null && _selectedFiles.contains(pdf.filePath);
        
        return ListTile(
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          title: Text(
            pdf.name,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${pdf.date} • ${pdf.size}',
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 12,
            ),
          ),
          trailing: widget.allowMultiSelect
              ? Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    if (pdf.filePath != null) {
                      _toggleSelection(pdf.filePath!);
                    }
                  },
                  activeColor: const Color(0xFFE53935),
                )
              : Radio<String>(
                  value: pdf.filePath ?? '',
                  groupValue: _selectedFiles.isEmpty ? null : _selectedFiles.first,
                  onChanged: (value) {
                    if (pdf.filePath != null) {
                      _toggleSelection(pdf.filePath!);
                    }
                  },
                  activeColor: const Color(0xFFE53935),
                ),
          onTap: () {
            if (pdf.filePath != null) {
              if (widget.allowMultiSelect) {
                _toggleSelection(pdf.filePath!);
              } else {
                _selectedFiles.clear();
                _selectedFiles.add(pdf.filePath!);
                _confirmSelection();
              }
            }
          },
        );
      },
    );
  }
}

