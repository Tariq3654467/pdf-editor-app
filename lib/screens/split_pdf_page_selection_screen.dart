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
import '../services/pdf_storage_service.dart';
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
  final Set<int> _failedPages = {}; // Track pages that failed to load to prevent infinite retries
  String? _actualFilePath; // Store actual file path (converted from content URI if needed)

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
      // Handle content URIs - convert to actual file path first
      String actualFilePath = widget.pdfPath;
      if (widget.pdfPath.startsWith('content://')) {
        try {
          print('Split: Detected content URI in _loadPDFInfo, converting: ${widget.pdfPath}');
          actualFilePath = await PDFStorageService.ensureInAppStorage(widget.pdfPath);
          print('Split: Content URI converted to: $actualFilePath');
          // Store actual file path in state for use throughout the screen
          if (mounted) {
            setState(() {
              _actualFilePath = actualFilePath;
            });
          }
        } catch (e) {
          print('Split: Failed to convert content URI: ${widget.pdfPath}, error: $e');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _totalPages = 0;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to access PDF file: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else {
        // Store regular file path in state
        if (mounted) {
          setState(() {
            _actualFilePath = actualFilePath;
          });
        }
      }
      
      // Validate file exists first
      final file = File(actualFilePath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _totalPages = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF file does not exist: $actualFilePath'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final info = await PDFIsolateService.loadPDFInfo(actualFilePath)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('Timeout loading PDF info');
              return PDFDocumentInfo(
                pageCount: 0,
                fileSize: 0,
                isValid: false,
                error: 'Timeout loading PDF',
              );
            },
          );
      
      if (mounted) {
        if (info.isValid && info.pageCount > 0) {
          setState(() {
            _totalPages = info.pageCount;
            _isLoading = false;
          });
          // Pre-load first batch of thumbnails immediately
          Future.microtask(() {
            if (mounted) {
              _preloadThumbnails(0, _totalPages.clamp(0, 20)); // Load first 20 pages
            }
          });
        } else {
          setState(() {
            _totalPages = 0;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading PDF: ${info.error ?? "Invalid PDF file"}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('Error in _loadPDFInfo: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _totalPages = 0;
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
    // Load thumbnails in parallel batches for faster loading
    final List<Future<void>> loadFutures = [];
    for (int i = startIndex; i < startIndex + count && i < _totalPages; i++) {
      if (!_thumbnailCache.containsKey(i) && !_loadingPages.contains(i)) {
        loadFutures.add(_loadThumbnail(i));
      }
    }
    // Wait for all thumbnails in this batch to start loading (don't wait for completion)
    await Future.wait(loadFutures, eagerError: false);
  }

  Future<void> _loadThumbnail(int pageIndex) async {
    // Don't retry if already loading, cached, or previously failed
    if (_loadingPages.contains(pageIndex) || 
        _thumbnailCache.containsKey(pageIndex) ||
        _failedPages.contains(pageIndex)) {
      return;
    }

    if (mounted) {
      setState(() {
        _loadingPages.add(pageIndex);
      });
    }

    try {
      // Use actual file path (converted from content URI if needed)
      final filePath = _actualFilePath ?? widget.pdfPath;
      
      // Check cache first
      final cached = await PDFPageCache().getCachedPage(filePath, pageIndex);
      if (cached != null && cached.isNotEmpty) {
        if (mounted) {
          setState(() {
            _thumbnailCache[pageIndex] = cached;
            _loadingPages.remove(pageIndex);
            _failedPages.remove(pageIndex); // Clear failed status if cache found
          });
        }
        return;
      }

      // Render thumbnail in isolate
      final imageBytes = await PDFIsolateService.renderPageToImage(
        PDFPageRenderRequest(
          filePath: filePath,
          pageIndex: pageIndex,
          scale: 0.3, // Smaller scale for faster loading and smaller memory footprint
        ),
      );

      if (imageBytes != null && imageBytes.isNotEmpty) {
        // Cache the thumbnail
        await PDFPageCache().cachePage(filePath, pageIndex, imageBytes);
        
        if (mounted) {
          setState(() {
            _thumbnailCache[pageIndex] = imageBytes;
            _loadingPages.remove(pageIndex);
            _failedPages.remove(pageIndex); // Clear failed status on success
          });
        }
      } else {
        // Mark as failed to prevent infinite retries
        if (mounted) {
          setState(() {
            _loadingPages.remove(pageIndex);
            _failedPages.add(pageIndex);
          });
        }
        print('Failed to render thumbnail for page $pageIndex: imageBytes is null or empty');
      }
    } catch (e, stackTrace) {
      print('Error loading thumbnail for page $pageIndex: $e');
      print('Stack trace: $stackTrace');
      // Mark as failed to prevent infinite retries
      if (mounted) {
        setState(() {
          _loadingPages.remove(pageIndex);
          _failedPages.add(pageIndex);
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

    BuildContext? dialogContext;
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        dialogContext = context;
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
          ),
        );
      },
    );

    try {
      // Use actual file path (converted from content URI if needed)
      final filePath = _actualFilePath ?? widget.pdfPath;
      
      // Convert page indices (0-based) to page numbers (1-based) and sort
      final selectedPageNumbers = _selectedPages.toList()..sort();
      
      // Split only selected pages with timeout protection
      final splitFiles = await PDFToolsService.splitPDFPages(
        filePath,
        selectedPageNumbers,
      ).timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          print('Split PDF operation timed out');
          return <String>[];
        },
      ).catchError((e) {
        print('Error in split PDF: $e');
        return <String>[];
      });

      // Close loading dialog - ensure it's always closed
      if (mounted) {
        if (dialogContext != null) {
          try {
            Navigator.of(dialogContext!).pop();
          } catch (e) {
            print('Error closing dialog: $e');
            // Try alternative method
            Navigator.of(context).pop();
          }
          dialogContext = null;
        } else {
          // Fallback: try to close any open dialog
          try {
            Navigator.of(context).pop();
          } catch (e) {
            // Dialog might already be closed
          }
        }
      }

      if (splitFiles.isNotEmpty) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'split',
          widget.pdfPath,
          resultPath: splitFiles.first,
        );

        if (mounted) {
          // Small delay to ensure cache is fully updated before showing message
          await Future.delayed(const Duration(milliseconds: 100));
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF split successfully! ${splitFiles.length} file(s) saved automatically. Files are available in Recent and App Files.',
              ),
              duration: const Duration(seconds: 4),
            ),
          );

          // Pop back to tools screen - this will trigger refresh via onOperationComplete
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
      // Close loading dialog if still open - ensure it's always closed
      if (mounted) {
        if (dialogContext != null) {
          try {
            Navigator.of(dialogContext!).pop();
          } catch (e2) {
            print('Error closing dialog in catch: $e2');
            // Try alternative method
            try {
              Navigator.of(context).pop();
            } catch (e3) {
              // Dialog might already be closed
            }
          }
          dialogContext = null;
        } else {
          // Fallback: try to close any open dialog
          try {
            Navigator.of(context).pop();
          } catch (e2) {
            // Dialog might already be closed
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Ensure dialog is closed and processing state is reset
      if (mounted) {
        if (dialogContext != null) {
          try {
            Navigator.of(dialogContext!).pop();
          } catch (e) {
            // Dialog might already be closed, try alternative
            try {
              Navigator.of(context).pop();
            } catch (e2) {
              // Ignore - dialog already closed
            }
          }
          dialogContext = null;
        }
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
                        // Load thumbnail if not cached, not loading, and not failed
                        if (!_thumbnailCache.containsKey(index) && 
                            !_loadingPages.contains(index) &&
                            !_failedPages.contains(index)) {
                          // Use microtask to load after current frame but don't wait for postFrameCallback
                          Future.microtask(() {
                            if (mounted && 
                                !_thumbnailCache.containsKey(index) && 
                                !_loadingPages.contains(index) &&
                                !_failedPages.contains(index)) {
                              _loadThumbnail(index);
                            }
                          });
                        }
                        return _PageThumbnailWidget(
                          pageNumber: pageNumber,
                          pageIndex: index,
                          isSelected: isSelected,
                          onTap: () => _togglePageSelection(index),
                          imageBytes: _thumbnailCache[index],
                          isLoading: _loadingPages.contains(index),
                          hasFailed: _failedPages.contains(index),
                        );
                      },
                    ),
                  ),
                ),
                SafeArea(
                  child: Container(
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
  final bool hasFailed;

  const _PageThumbnailWidget({
    required this.pageNumber,
    required this.pageIndex,
    required this.isSelected,
    required this.onTap,
    this.imageBytes,
    this.isLoading = false,
    this.hasFailed = false,
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
                            : widget.hasFailed
                                ? Container(
                                    color: Colors.grey[100],
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.error_outline,
                                            color: Colors.grey[400],
                                            size: 24,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Page ${widget.pageNumber}',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
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
    // Use Image.memory for simpler and faster rendering
    // Note: Image.memory loads synchronously, so no loadingBuilder needed
    return Image.memory(
      imageBytes,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        print('Error loading thumbnail image: $error');
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(
              Icons.broken_image,
              color: Colors.grey,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}
