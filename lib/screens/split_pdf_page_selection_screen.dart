import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import '../services/pdf_isolate_service.dart';
import '../services/pdf_tools_service.dart';
import '../services/pdf_service.dart';
import '../services/pdf_cache_service.dart';
import '../services/pdf_preferences_service.dart';
import '../services/pdf_page_cache.dart';

class SplitPDFPageSelectionScreen extends StatefulWidget {
  final String pdfPath;
  final String fileName;

  const SplitPDFPageSelectionScreen({
    super.key,
    required this.pdfPath,
    required this.fileName,
  });

  @override
  State<SplitPDFPageSelectionScreen> createState() => _SplitPDFPageSelectionScreenState();
}

class _SplitPDFPageSelectionScreenState extends State<SplitPDFPageSelectionScreen> {
  Set<int> _selectedPages = {};
  int _totalPages = 0;
  bool _isLoading = true;
  bool _isProcessing = false;
  final ScrollController _scrollController = ScrollController();
  final Map<int, Uint8List?> _thumbnailCache = {};
  final Set<int> _loadingPages = {};

  @override
  void initState() {
    super.initState();
    _loadPDFInfo();
    // Initialize page cache
    PDFPageCache().initialize();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPDFInfo() async {
    try {
      final info = await PDFIsolateService.loadPDFInfo(widget.pdfPath);
      if (mounted) {
        setState(() {
          _totalPages = info.pageCount;
          _isLoading = false;
        });
        // Pre-load first few thumbnails
        _preloadThumbnails(0, 9);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  void _togglePageSelection(int pageIndex) {
    setState(() {
      if (_selectedPages.contains(pageIndex)) {
        _selectedPages.remove(pageIndex);
      } else {
        _selectedPages.add(pageIndex);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPages.length == _totalPages) {
        _selectedPages.clear();
      } else {
        _selectedPages = List.generate(_totalPages, (index) => index).toSet();
      }
    });
  }

  Future<void> _preloadThumbnails(int startIndex, int count) async {
    for (int i = startIndex; i < startIndex + count && i < _totalPages; i++) {
      if (!_thumbnailCache.containsKey(i) && !_loadingPages.contains(i)) {
        _loadThumbnail(i);
      }
    }
  }

  Future<void> _loadThumbnail(int pageIndex) async {
    if (_loadingPages.contains(pageIndex) || _thumbnailCache.containsKey(pageIndex)) {
      return;
    }

    setState(() {
      _loadingPages.add(pageIndex);
    });

    try {
      // Check cache first
      final cached = await PDFPageCache().getCachedPage(widget.pdfPath, pageIndex);
      if (cached != null) {
        if (mounted) {
          setState(() {
            _thumbnailCache[pageIndex] = cached;
            _loadingPages.remove(pageIndex);
          });
        }
        return;
      }

      // Render thumbnail in isolate
      final imageBytes = await PDFIsolateService.renderPageToImage(
        PDFPageRenderRequest(
          filePath: widget.pdfPath,
          pageIndex: pageIndex,
          scale: 0.5, // Smaller scale for thumbnails
        ),
      );

      if (imageBytes != null) {
        // Cache the thumbnail
        await PDFPageCache().cachePage(widget.pdfPath, pageIndex, imageBytes);
        
        if (mounted) {
          setState(() {
            _thumbnailCache[pageIndex] = imageBytes;
            _loadingPages.remove(pageIndex);
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loadingPages.remove(pageIndex);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPages.remove(pageIndex);
        });
      }
    }
  }

  Future<void> _splitSelectedPages() async {
    if (_selectedPages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one page to split'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
        ),
      ),
    );

    try {
      // Convert page indices (0-based) to page numbers (1-based) and sort
      final selectedPageNumbers = _selectedPages.toList()..sort();
      
      // Split only selected pages
      final splitFiles = await PDFToolsService.splitPDFPages(
        widget.pdfPath,
        selectedPageNumbers,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      if (splitFiles.isNotEmpty) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'split',
          widget.pdfPath,
          resultPath: splitFiles.first,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF split into ${splitFiles.length} file(s). Files saved in app storage.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );

          // Pop back to tools screen
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to split PDF. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF263238)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Selected ${_selectedPages.length}',
          style: const TextStyle(
            color: Color(0xFF263238),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Row(
            children: [
              const Text(
                'All',
                style: TextStyle(
                  color: Color(0xFF263238),
                  fontSize: 14,
                ),
              ),
              Checkbox(
                value: _totalPages > 0 && _selectedPages.length == _totalPages,
                onChanged: _isLoading ? null : (value) => _toggleSelectAll(),
                activeColor: const Color(0xFFE53935),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification) {
                        // Load thumbnails for visible items
                        final renderObject = _scrollController.position;
                        if (renderObject.hasContentDimensions) {
                          final firstVisible = (renderObject.pixels / 200).floor();
                          final lastVisible = ((renderObject.pixels + renderObject.viewportDimension) / 200).ceil();
                          _preloadThumbnails(
                            (firstVisible * 3).clamp(0, _totalPages),
                            ((lastVisible - firstVisible + 1) * 3).clamp(0, _totalPages),
                          );
                        }
                      }
                      return false;
                    },
                    child: GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: _totalPages,
                      cacheExtent: 300, // Cache items for smoother scrolling
                      addAutomaticKeepAlives: true, // Keep items alive when scrolled out
                      addRepaintBoundaries: true, // Optimize repaints
                      itemBuilder: (context, index) {
                        final pageNumber = index + 1;
                        final isSelected = _selectedPages.contains(index);
                        // Load thumbnail if not cached
                        if (!_thumbnailCache.containsKey(index) && !_loadingPages.contains(index)) {
                          _loadThumbnail(index);
                        }
                        return _PageThumbnailWidget(
                          pageNumber: pageNumber,
                          pageIndex: index,
                          isSelected: isSelected,
                          onTap: () => _togglePageSelection(index),
                          imageBytes: _thumbnailCache[index],
                          isLoading: _loadingPages.contains(index),
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isProcessing || _selectedPages.isEmpty
                        ? null
                        : _splitSelectedPages,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: Text(
                      'Continue (${_selectedPages.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// Optimized thumbnail widget with AutomaticKeepAliveClientMixin
class _PageThumbnailWidget extends StatefulWidget {
  final int pageNumber;
  final int pageIndex;
  final bool isSelected;
  final VoidCallback onTap;
  final Uint8List? imageBytes;
  final bool isLoading;

  const _PageThumbnailWidget({
    required this.pageNumber,
    required this.pageIndex,
    required this.isSelected,
    required this.onTap,
    this.imageBytes,
    this.isLoading = false,
  });

  @override
  State<_PageThumbnailWidget> createState() => _PageThumbnailWidgetState();
}

class _PageThumbnailWidgetState extends State<_PageThumbnailWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep widget alive when scrolled out

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: widget.isSelected ? const Color(0xFFE53935) : Colors.grey[300]!,
                width: widget.isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(7),
                      topRight: Radius.circular(7),
                    ),
                    child: widget.imageBytes != null
                        ? _buildThumbnailImage(widget.imageBytes!)
                        : widget.isLoading
                            ? Container(
                                color: Colors.grey[100],
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                color: Colors.grey[100],
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: widget.isSelected 
                                          ? const Color(0xFFE53935).withOpacity(0.1)
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.picture_as_pdf,
                                      color: widget.isSelected 
                                          ? const Color(0xFFE53935)
                                          : Colors.grey[600],
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${widget.pageNumber}',
                    style: TextStyle(
                      color: widget.isSelected ? const Color(0xFFE53935) : Colors.grey[600],
                      fontSize: 14,
                      fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Checkbox in top-right corner
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: widget.isSelected
                  ? const Icon(
                      Icons.check,
                      color: Color(0xFFE53935),
                      size: 18,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailImage(Uint8List imageBytes) {
    return FutureBuilder<ui.Image>(
      future: _decodeImage(imageBytes),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return CustomPaint(
            painter: _ImagePainter(snapshot.data!),
            child: Container(),
          );
        }
        return Container(
          color: Colors.grey[100],
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;

  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) => oldDelegate.image != image;
}
