import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:async';
import '../services/pdf_service.dart';
import '../services/pdf_tools_service.dart';
import '../services/pdf_preferences_service.dart';
import '../services/pdf_text_editor_service.dart';
import '../services/pdf_content_editor_service.dart';
import '../services/pdf_cache_service.dart';
import '../services/theme_service.dart';
import '../models/pdf_file.dart';
import '../widgets/pdf_annotation_overlay.dart';
import '../widgets/pdf_content_editor.dart';
import '../widgets/in_app_file_picker.dart';

class PDFViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const PDFViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  late PdfViewerController _pdfViewerController;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = true;
  bool _isFavorite = false;
  PDFFile? _pdfFileInfo;
  bool _showPageIndicator = false;
  Timer? _hidePageIndicatorTimer;
  Timer? _scrollCheckTimer;
  bool _isScrolling = false;
  bool _showPagePreview = true; // Control visibility of page preview bar
  double _pdfScrollOffset = 0.0; // Track PDF vertical scroll offset for annotations
  int _pdfReloadKey = 0; // Key to force PDF viewer reload after modifications
  
  // Error handling
  String? _errorMessage;
  String? _actualFilePath; // May differ from widget.filePath if content URI was copied
  Timer? _loadingTimeoutTimer;
  static const MethodChannel _fileChannel = MethodChannel('com.example.pdf_editor_app/file_intent');
  
  // Annotation/Editing state
  bool _isEditingMode = false;
  bool _isContentEditMode = false; // True content editing mode (Sejda-style)
  String _selectedTool = 'pen'; // 'pen', 'highlight', 'underline', 'eraser', 'text', 'none'
  Color _selectedColor = Colors.red;
  double _strokeWidth = 3.0;
  final GlobalKey<PDFAnnotationOverlayState> _annotationOverlayKey = GlobalKey<PDFAnnotationOverlayState>();
  bool _canUndo = false;
  bool _canRedo = false;
  
  // Text editing state (Sejda-style)
  Offset? _textEditPosition;
  String? _editingText;
  bool _isTextEditMode = false;
  List<TextAnnotation> _textAnnotations = []; // Instant text overlays (not saved to PDF yet)
  
  // Content editing state (true PDF content editing)
  String? _editableCopyPath; // Path to editable copy of PDF
  
  // View mode and orientation
  String _viewMode = 'vertical'; // 'vertical', 'horizontal', 'page'
  bool _isPortrait = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _pagePreviewScrollController = ScrollController();

  // Helper to determine when a drawing tool is really active
  bool get _isDrawingToolActive =>
      _isEditingMode &&
      (_selectedTool == 'pen' ||
       _selectedTool == 'highlight' ||
       _selectedTool == 'underline' ||
       _selectedTool == 'eraser');

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    
    // Add listener to scroll controller
    _pagePreviewScrollController.addListener(() {
      // This helps ensure the controller is working
    });
    
    // CRITICAL FIX: Delay initialization to prevent crashes on Samsung devices
    // Widget must be fully built before starting heavy file operations
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      try {
        _initializePDF();
        // Auto-bookmark in background (non-blocking)
        _autoBookmarkPDF().catchError((e) {
          print('Error auto-bookmarking: $e');
        });
      } catch (e, stackTrace) {
        print('Error in delayed init: $e');
        print('Stack trace: $stackTrace');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Error initializing PDF viewer. Please try again.';
          });
        }
      }
    });
    
    // Set loading timeout (30 seconds for large PDFs - reduced for Samsung)
    _loadingTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _isLoading && _actualFilePath != null) {
        print('PDFViewer: Loading timeout after 30 seconds');
        setState(() {
          _isLoading = false;
          _errorMessage = 'PDF took too long to load. The file might be very large. Please try again.';
        });
      }
    });
  }
  
  @override
  void dispose() {
    // Cancel all timers
    _loadingTimeoutTimer?.cancel();
    _hidePageIndicatorTimer?.cancel();
    _scrollCheckTimer?.cancel();
    _stopScrollCheckTimer();
    
    // Reset orientation to allow all orientations when leaving the screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // Dispose controllers
    _pdfViewerController.dispose();
    _searchController.dispose();
    _pagePreviewScrollController.dispose();
    
    super.dispose();
  }
  
  Future<void> _initializePDF() async {
    if (!mounted) return;
    
    try {
      print('PDFViewer: Initializing PDF with path: ${widget.filePath}');
      
      // Check if filePath is a content URI
      if (widget.filePath.startsWith('content://')) {
        print('PDFViewer: Detected content URI, copying to cache...');
        // Copy content URI to cache with timeout
        final tempPath = await _copyContentUriToCache(widget.filePath)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                print('PDFViewer: Content URI copy timeout');
                return null;
              },
            )
            .catchError((e) {
              print('PDFViewer: Error copying content URI: $e');
              return null;
            });
            
        if (tempPath != null && mounted) {
          print('PDFViewer: Content URI copied to: $tempPath');
          final tempFile = File(tempPath);
          final exists = await tempFile.exists()
              .timeout(const Duration(seconds: 2))
              .catchError((e) {
                print('PDFViewer: Error checking file existence: $e');
                return false;
              });
              
          if (exists) {
            print('PDFViewer: Setting _actualFilePath to cached path: $tempPath');
            if (mounted) {
              setState(() {
                _actualFilePath = tempPath;
              });
              // Load PDF info in background (non-blocking)
              _loadPDFInfo().catchError((e) {
                print('PDFViewer: Error loading PDF info: $e');
              });
            }
          } else {
            print('PDFViewer: Copied file does not exist at: $tempPath');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Failed to access PDF file. The file may have been moved or deleted.';
              });
            }
          }
        } else {
          print('PDFViewer: Failed to copy content URI to cache');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Failed to access PDF file. Please try selecting the file again.';
            });
          }
        }
      } else {
        // Regular file path - verify it exists (non-blocking)
        print('PDFViewer: Regular file path detected');
        final file = File(widget.filePath);
        
        // Check file existence with timeout
        final exists = await file.exists()
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
              print('PDFViewer: Error checking file existence: $e');
              return false;
            });
            
        if (exists) {
          // CRITICAL FIX: Don't read entire file with readAsBytes() - causes ANR!
          // Only read first 4 bytes to check header
          try {
            final randomAccessFile = await file.open()
                .timeout(const Duration(seconds: 2))
                .catchError((e) {
                  print('PDFViewer: Error opening file: $e');
                  return null;
                });
                
            if (randomAccessFile != null) {
              try {
                final bytes = await randomAccessFile.read(4)
                    .timeout(const Duration(seconds: 2))
                    .catchError((e) {
                      print('PDFViewer: Error reading header: $e');
                      return <int>[];
                    });
                await randomAccessFile.close();
                
                if (bytes.length >= 4) {
                  final header = String.fromCharCodes(bytes);
                  print('PDFViewer: File header: $header');
                  if (header == '%PDF') {
                    print('PDFViewer: Valid PDF file detected');
                    if (mounted) {
                      setState(() {
                        _actualFilePath = widget.filePath;
                      });
                      // Load PDF info in background (non-blocking)
                      _loadPDFInfo().catchError((e) {
                        print('PDFViewer: Error loading PDF info: $e');
                      });
                    }
                  } else {
                    print('PDFViewer: File is not a valid PDF (header: $header)');
                    if (mounted) {
                      setState(() {
                        _isLoading = false;
                        _errorMessage = 'The selected file is not a valid PDF file.';
                      });
                    }
                  }
                } else {
                  print('PDFViewer: File is too small or empty');
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _errorMessage = 'The PDF file appears to be empty or corrupted.';
                    });
                  }
                }
              } catch (readError) {
                await randomAccessFile.close().catchError((_) {});
                // If we can't read header, still try to load it (might be a permission issue)
                print('PDFViewer: Error reading header, proceeding anyway: $readError');
                if (mounted) {
                  setState(() {
                    _actualFilePath = widget.filePath;
                  });
                  _loadPDFInfo().catchError((e) {
                    print('PDFViewer: Error loading PDF info: $e');
                  });
                }
              }
            } else {
              // Can't open file, but try to load anyway
              print('PDFViewer: Could not open file, proceeding anyway');
              if (mounted) {
                setState(() {
                  _actualFilePath = widget.filePath;
                });
                _loadPDFInfo().catchError((e) {
                  print('PDFViewer: Error loading PDF info: $e');
                });
              }
            }
          } catch (e) {
            print('PDFViewer: Error reading file: $e');
            // Still try to load - might work even if header check fails
            if (mounted) {
              setState(() {
                _actualFilePath = widget.filePath;
              });
              _loadPDFInfo().catchError((e) {
                print('PDFViewer: Error loading PDF info: $e');
              });
            }
          }
        } else {
          print('PDFViewer: File does not exist at: ${widget.filePath}');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'PDF file not found. It may have been moved or deleted.';
            });
          }
        }
      }
    } catch (e, stackTrace) {
      print('PDFViewer: Error initializing PDF: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading PDF: ${e.toString()}';
        });
      }
    }
  }
  
  Future<String?> _copyContentUriToCache(String contentUri) async {
    try {
      print('PDFViewer: Copying content URI: $contentUri');
      // Add timeout to prevent hanging
      final String? result = await _fileChannel.invokeMethod('copyContentUriToCache', contentUri)
          .timeout(
            const Duration(seconds: 15), // Max 15 seconds for file copy
            onTimeout: () {
              print('PDFViewer: Content URI copy timeout');
              return null;
            },
          )
          .catchError((e) {
            print('PDFViewer: Error copying content URI: $e');
            return null;
          });
          
      if (result != null) {
        print('PDFViewer: Content URI copied successfully to: $result');
        final file = File(result);
        
        // Check existence with timeout
        final exists = await file.exists()
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
              print('PDFViewer: Error checking copied file: $e');
              return false;
            });
            
        if (exists) {
          // Get file size with timeout
          final size = await file.length()
              .timeout(const Duration(seconds: 2))
              .catchError((e) {
                print('PDFViewer: Error getting file size: $e');
                return 0;
              });
          print('PDFViewer: Copied file exists, size: $size bytes');
          return result;
        } else {
          print('PDFViewer: Copied file does not exist');
          return null;
        }
      } else {
        print('PDFViewer: Content URI copy returned null');
        return null;
      }
    } catch (e, stackTrace) {
      print('PDFViewer: Error copying content URI: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  Future<void> _autoBookmarkPDF() async {
    // Automatically add PDF to bookmarks when opened
    try {
      final isBookmarked = await PDFPreferencesService.isBookmarked(widget.filePath);
      if (!isBookmarked) {
        // Auto-bookmark when PDF is opened for the first time
        await PDFPreferencesService.setBookmark(widget.filePath, true);
      }
      // Update last accessed time
      await PDFPreferencesService.setLastAccessed(widget.filePath);
    } catch (e) {
      print('Error auto-bookmarking PDF: $e');
    }
  }

  Future<void> _loadPDFInfo() async {
    if (_actualFilePath == null || !mounted) return;
    
    try {
      final file = File(_actualFilePath!);
      
      // Check existence with timeout
      final exists = await file.exists()
          .timeout(const Duration(seconds: 2))
          .catchError((e) {
            print('PDFViewer: Error checking file in _loadPDFInfo: $e');
            return false;
          });
          
      if (exists) {
        // Get file stat with timeout
        final stat = await file.stat()
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
              print('PDFViewer: Error getting file stat: $e');
              return null;
            });
            
        if (stat != null && mounted) {
          final fileName = widget.fileName;
          final fileSize = PDFService.formatFileSize(stat.size);
          final modifiedDate = stat.modified;
          final date = PDFService.formatDate(modifiedDate);

          // Load bookmark status (use original filePath for bookmarking) - non-blocking
          final isBookmarked = await PDFPreferencesService.isBookmarked(widget.filePath)
              .timeout(const Duration(seconds: 1))
              .catchError((e) {
                print('PDFViewer: Error checking bookmark: $e');
                return false;
              });
        
          setState(() {
            _isFavorite = isBookmarked;
            _pdfFileInfo = PDFFile(
              name: fileName,
              date: date,
              size: fileSize,
              isFavorite: isBookmarked,
              filePath: widget.filePath,
            );
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'PDF file not found. It may have been moved or deleted.';
        });
      }
    } catch (e) {
      print('Error loading PDF info: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error accessing PDF file: ${e.toString()}';
      });
    }
  }


  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    print('PDFViewer: Document loaded successfully, pages: ${details.document.pages.count}');
    _loadingTimeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _totalPages = details.document.pages.count;
        _isLoading = false;
        _errorMessage = null; // Clear any previous errors
      });
      // Scroll to current page after document loads - use multiple callbacks to ensure it works
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToCurrentPage();
        }
      });
      // Also try after a longer delay to ensure the preview bar is fully built
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _scrollToCurrentPage();
        }
      });
    }
  }
  
  void _onDocumentLoadFailed(PdfDocumentLoadFailedDetails details) {
    print('PDFViewer: Document load failed: ${details.error}');
    _loadingTimeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load PDF: ${details.error}\n\nThe file might be corrupted or in an unsupported format.';
      });
    }
  }

  Widget _buildPDFViewer() {
    // Show error if loading failed
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Color(0xFFE53935),
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to Load PDF',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF757575),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _isLoading = true;
                    _actualFilePath = null;
                  });
                  _initializePDF();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show loading indicator only if we don't have a file path yet
    // Once we have _actualFilePath, build the PDF viewer (it will show its own loading)
    if (_actualFilePath == null) {
      print('PDFViewer: Waiting for file path...');
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
        ),
      );
    }
    
    // Build PDF viewer with actual file path
    // Ensure we're using the cached file path, not the content URI
    final filePath = _actualFilePath!;
    print('PDFViewer: Building PDF viewer with file path: $filePath');
    
    // Double-check it's not a content URI
    if (filePath.startsWith('content://')) {
      print('PDFViewer: ERROR - Still using content URI! This should not happen.');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Color(0xFFE53935),
              ),
              const SizedBox(height: 16),
              const Text(
                'Configuration Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unable to process content URI. Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF757575),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // CRITICAL FIX: Don't check file.existsSync() or await file.exists() in build()!
    // Build method cannot be async and file checks block UI thread causing ANR
    // File existence was already verified in _initializePDF() - trust that result
    // Let the PDF viewer handle file errors itself if file doesn't exist
    
    print('PDFViewer: Building PDF viewer...');
    
    // Create File object - don't check existence here (already checked in _initializePDF)
    final file = File(filePath);
    
    // Wrap PDF viewer in RepaintBoundary to prevent full-screen repaints
    final pdfViewer = RepaintBoundary(
      child: _isTextEditMode && _selectedTool == 'text'
          ? GestureDetector(
              onTapDown: (details) => _handleTextEditTap(details.localPosition),
              behavior: HitTestBehavior.translucent,
              child: SfPdfViewer.file(
                file,
                key: ValueKey('pdf_viewer_${filePath}_$_viewMode$_pdfReloadKey'),
                controller: _pdfViewerController,
                onDocumentLoaded: _onDocumentLoaded,
                onDocumentLoadFailed: _onDocumentLoadFailed,
                onPageChanged: _onPageChanged,
                scrollDirection: _getScrollDirection(),
                pageLayoutMode: _getPageLayoutMode(),
                enableDoubleTapZooming: true,
                enableTextSelection: false,
              ),
            )
          : SfPdfViewer.file(
              file,
              key: ValueKey('pdf_viewer_${filePath}_$_viewMode$_pdfReloadKey'),
              controller: _pdfViewerController,
              onDocumentLoaded: _onDocumentLoaded,
              onDocumentLoadFailed: _onDocumentLoadFailed,
              onPageChanged: _onPageChanged,
              scrollDirection: _getScrollDirection(),
              pageLayoutMode: _getPageLayoutMode(),
              enableDoubleTapZooming: true,
              enableTextSelection: true,
            ),
    );
    
    return pdfViewer;
  }

  void _onPageChanged(PdfPageChangedDetails details) {
    final newPage = details.newPageNumber;
    if (newPage != _currentPage && mounted) {
      // CRITICAL FIX: Batch setState calls to prevent excessive updates
      // Use SchedulerBinding to batch updates and prevent ANR
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentPage = newPage;
            _showPageIndicator = true;
          });
          
          // Hide page indicator after delay
          _hidePageIndicatorTimer?.cancel();
          _hidePageIndicatorTimer = Timer(const Duration(seconds: 1), () {
            if (mounted) {
              setState(() {
                _showPageIndicator = false;
              });
            }
          });
          
          // Scroll to current page in preview bar (only if visible) - non-blocking
          if (_showPagePreview) {
            Future.microtask(() {
              if (mounted) {
                _scrollToCurrentPage();
              }
            });
          }
        }
      });
    }
  }

  void _scrollToCurrentPage() {
    // Try immediate scroll first, then with delay as fallback
    _performScroll();
    
    // Also try after a delay to ensure controller is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _performScroll();
      }
    });
    
    // One more attempt after longer delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _performScroll();
      }
    });
  }

  void _performScroll() {
    if (!mounted || _totalPages == 0) {
      return;
    }
    
    // Wait for scroll controller to be attached - retry if not ready
    if (!_pagePreviewScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _performScroll();
        }
      });
      return;
    }
    
    try {
      final thumbnailWidth = 60.0;
      final thumbnailMargin = 8.0;
      final totalThumbnailWidth = thumbnailWidth + thumbnailMargin;
      final screenWidth = MediaQuery.of(context).size.width;
      
      // Calculate the position of the current page thumbnail
      final pagePosition = (_currentPage - 1) * totalThumbnailWidth;
      
      // Calculate offset to center the current page
      final targetOffset = pagePosition - (screenWidth / 2) + (thumbnailWidth / 2);
      
      final maxScrollExtent = _pagePreviewScrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxScrollExtent > 0 ? maxScrollExtent : 0.0);
      
      // Only scroll if the target is different from current position
      final currentOffset = _pagePreviewScrollController.offset;
      if ((clampedOffset - currentOffset).abs() > 5) {
        _pagePreviewScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } catch (e) {
      print('Error in _performScroll: $e');
    }
  }

  void _goToPage(int pageNumber) {
    if (pageNumber >= 1 && pageNumber <= _totalPages) {
      setState(() {
        _currentPage = pageNumber;
        _showPagePreview = false; // Hide preview bar when page is clicked
      });
      _pdfViewerController.jumpToPage(pageNumber);
    }
  }

  void _startScrollCheckTimer() {
    _stopScrollCheckTimer(); // Stop any existing timer
    _scrollCheckTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isScrolling || !mounted) {
        _stopScrollCheckTimer();
        return;
      }
      _updateCurrentPageFromScroll();
    });
  }

  void _stopScrollCheckTimer() {
    _scrollCheckTimer?.cancel();
    _scrollCheckTimer = null;
  }

  void _updateCurrentPageFromScroll() {
    // Try to get the current page from the controller
    // The onPageChanged callback should be the primary source, but we check here as backup
    if (mounted) {
      try {
        // Try to access pageNumber property (may not exist in all versions)
        int? currentPageFromController;
        try {
          // Use reflection or direct access - if this fails, we'll catch it
          currentPageFromController = _pdfViewerController.pageNumber;
        } catch (_) {
          // pageNumber property might not be available, that's okay
          // We'll rely on onPageChanged callback instead
        }
        
        if (currentPageFromController != null && 
            currentPageFromController != _currentPage &&
            currentPageFromController >= 1 && 
            currentPageFromController <= _totalPages) {
          setState(() {
            _currentPage = currentPageFromController!;
          });
          // Show page indicator briefly
          _hidePageIndicatorTimer?.cancel();
          setState(() {
            _showPageIndicator = true;
          });
          _hidePageIndicatorTimer = Timer(const Duration(seconds: 1), () {
            if (mounted) {
              setState(() {
                _showPageIndicator = false;
              });
            }
          });
          // Scroll preview bar to show current page (only if visible)
          if (_showPagePreview) {
            _scrollToCurrentPage();
          }
        } else {
          // Even if page hasn't changed, ensure preview bar is in sync (only if visible)
          if (_showPagePreview) {
            _scrollToCurrentPage();
          }
        }
      } catch (e) {
        print('Error in _updateCurrentPageFromScroll: $e');
        // Fallback: just scroll the preview bar to keep it in sync
        _scrollToCurrentPage();
      }
    }
  }

  PdfScrollDirection _getScrollDirection() {
    switch (_viewMode) {
      case 'horizontal':
        return PdfScrollDirection.horizontal;
      case 'page':
        // For page-by-page interaction prefer horizontal swiping
        return PdfScrollDirection.horizontal;
      case 'vertical':
      default:
        return PdfScrollDirection.vertical;
    }
  }

  PdfPageLayoutMode _getPageLayoutMode() {
    switch (_viewMode) {
      case 'page':
        return PdfPageLayoutMode.single;
      case 'vertical':
      case 'horizontal':
      default:
        return PdfPageLayoutMode.continuous;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use system theme instead of local state
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF424242);
    final iconColor = isDarkMode ? Colors.white : const Color(0xFF424242);
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: iconColor,
            size: 24,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Page $_currentPage',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(
              Icons.search_outlined,
              color: iconColor,
              size: 24,
            ),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: Icon(
              _isPortrait ? Icons.screen_rotation_outlined : Icons.screen_lock_portrait_outlined,
              color: iconColor,
              size: 24,
            ),
            onPressed: _toggleOrientation,
          ),
          IconButton(
            icon: Icon(
              Icons.description_outlined,
              color: iconColor,
              size: 24,
            ),
            onPressed: _showViewModeBottomSheet,
          ),
          IconButton(
            icon: Icon(
              Icons.more_vert,
              color: iconColor,
              size: 24,
            ),
            onPressed: _showOptionsBottomSheet,
          ),
        ],
        iconTheme: IconThemeData(
          color: iconColor,
          size: 24,
        ),
      ),
      // CRITICAL FIX: Wrap body in SafeArea to handle system insets (status bar, navigation bar)
      // This prevents content from being cut off by ~23px on gesture navigation devices (Android 13-14)
      body: SafeArea(
        // Only apply top safe area (status bar), bottom is handled by bottomNavigationBar
        top: true,
        bottom: false,
        child: Stack(
          children: [
            // Show content editor if in content edit mode
            if (_isContentEditMode && _editableCopyPath != null)
              PDFContentEditor(
                filePath: _editableCopyPath!,
                currentPage: _currentPage,
                onSave: (savedPath) async {
                  // Replace original with edited copy
                  try {
                    final originalFile = File(_actualFilePath ?? widget.filePath);
                    final editedFile = File(savedPath);
                    if (await editedFile.exists()) {
                      await originalFile.writeAsBytes(await editedFile.readAsBytes());
                      // Update cache
                      await PDFCacheService.clearCache();
                      // Reload PDF
                      setState(() {
                        _pdfReloadKey++;
                        _isContentEditMode = false;
                        _editableCopyPath = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('PDF saved successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving PDF: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                onCancel: () {
                  setState(() {
                    _isContentEditMode = false;
                    // Optionally delete editable copy
                    if (_editableCopyPath != null) {
                      File(_editableCopyPath!).delete();
                      _editableCopyPath = null;
                    }
                  });
                },
              )
            else
            // PDF Viewer with annotation overlay
            PDFAnnotationOverlay(
            key: _annotationOverlayKey,
            drawingColor: _getToolColor(),
            strokeWidth: _getStrokeWidth(),
            isDrawing: _isDrawingToolActive,
            isEraser: _selectedTool == 'eraser',
            toolType: _selectedTool,
            currentPage: _currentPage,
            scrollOffset: _pdfScrollOffset,
            textAnnotations: _textAnnotations,
            onTextTap: (textAnnotation) {
              // Allow editing text by tapping on it
              if (_isTextEditMode && _selectedTool == 'text') {
                _editTextAnnotation(textAnnotation);
              }
            },
            onClear: () {},
            onUndoStateChanged: (canUndo) {
              setState(() {
                _canUndo = canUndo;
              });
            },
            onRedoStateChanged: (canRedo) {
              setState(() {
                _canRedo = canRedo;
              });
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Detect when user scrolls manually and update preview bar
                if (notification is ScrollStartNotification) {
                  // Start periodic checks during scrolling
                  _isScrolling = true;
                  _startScrollCheckTimer();
                } else if (notification is ScrollUpdateNotification) {
                  // Update during scroll for real-time feedback
                  _isScrolling = true;
                  // Track scroll offset for annotation positioning
                  if (mounted) {
                    setState(() {
                      _pdfScrollOffset = notification.metrics.pixels;
                    });
                  }
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (mounted) {
                      _updateCurrentPageFromScroll();
                    }
                  });
                } else if (notification is ScrollEndNotification) {
                  // Stop periodic checks and do final update
                  _isScrolling = false;
                  _stopScrollCheckTimer();
                  // Update final scroll offset
                  if (mounted) {
                    setState(() {
                      _pdfScrollOffset = notification.metrics.pixels;
                    });
                  }
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (mounted) {
                      _updateCurrentPageFromScroll();
                    }
                  });
                }
                return false;
              },
            child: _buildPDFViewer(),
            ),
          ),
          // Page count indicator (briefly shown on page change)
          // Use IgnorePointer to ensure it doesn't block PDF scrolling
          Positioned(
            top: 16,
            left: 16,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showPageIndicator ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.2) 
                        : Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_currentPage/$_totalPages',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Loading indicator
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      ),
      floatingActionButton: _isEditingMode
          ? null
          : FloatingActionButton(
              onPressed: () {
                setState(() {
                  _isEditingMode = true;
                });
              },
              backgroundColor: const Color(0xFF1976D2),
              child: const Icon(Icons.edit, color: Colors.white),
            ),
      bottomNavigationBar: _isEditingMode
          ? _buildEditingToolbar()
          : (_totalPages > 0 && _showPagePreview
              ? _buildPagePreviewBar()
              : null),
    );
  }

  Color _getToolColor() {
    switch (_selectedTool) {
      case 'highlight':
        return Colors.yellow.withOpacity(0.4);
      case 'underline':
        return Colors.blue;
      case 'eraser':
        return Colors.white;
      default:
        return _selectedColor;
    }
  }

  double _getStrokeWidth() {
    switch (_selectedTool) {
      case 'highlight':
        return 15.0; // Thicker for highlight
      case 'underline':
        return 2.0; // Thin line for underline
      case 'eraser':
        return 20.0; // Larger eraser
      default:
        return _strokeWidth;
    }
  }

  Widget _buildEditingToolbar() {
    // CRITICAL FIX: Get system insets to account for navigation bar height
    // On gesture navigation devices (Android 13-14), this is typically ~23px
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom; // System navigation bar height
    final bottomViewInsets = mediaQuery.viewInsets.bottom; // Keyboard height (if visible)
    
    // Total bottom inset = system padding + view insets (keyboard)
    final totalBottomInset = bottomPadding + bottomViewInsets;
    
    return Container(
      // Dynamic height: base height (70) + system navigation bar padding
      // This ensures toolbar is never cut off on any Android version
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        // Base toolbar height (70) - padding is already applied to parent Container
        height: 70,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
          // Undo button
          _buildToolButton(
            icon: Icons.undo,
            label: 'Undo',
            isSelected: false,
            onTap: _canUndo
                ? () {
                  _annotationOverlayKey.currentState?.undo();
                }
                : null,
          ),
          // Redo button
          _buildToolButton(
            icon: Icons.redo,
            label: 'Redo',
            isSelected: false,
            onTap: _canRedo
                ? () {
                  _annotationOverlayKey.currentState?.redo();
                }
                : null,
          ),
          // Copy text button
          _buildToolButton(
            icon: Icons.content_copy,
            label: 'Copy',
            isSelected: false,
            onTap: () {
              _copySelectedText();
            },
          ),
          // Pen tool
          _buildToolButton(
            icon: Icons.edit,
            label: 'Pen',
            isSelected: _selectedTool == 'pen',
            onTap: () => setState(() => _selectedTool = 'pen'),
          ),
          // Highlight tool
          _buildToolButton(
            icon: Icons.highlight,
            label: 'Highlight',
            isSelected: _selectedTool == 'highlight',
            onTap: () => setState(() => _selectedTool = 'highlight'),
          ),
          // Underline tool
          _buildToolButton(
            icon: Icons.format_underline,
            label: 'Underline',
            isSelected: _selectedTool == 'underline',
            onTap: () => setState(() => _selectedTool = 'underline'),
          ),
          // Eraser tool
          _buildToolButton(
            icon: Icons.cleaning_services,
            label: 'Eraser',
            isSelected: _selectedTool == 'eraser',
            onTap: () => setState(() => _selectedTool = 'eraser'),
          ),
          // Text tool (Sejda-style: click to edit existing text or add new)
          _buildToolButton(
            icon: Icons.text_fields,
            label: 'Text',
            isSelected: _selectedTool == 'text',
            onTap: () {
              setState(() {
                _selectedTool = 'text';
                _isTextEditMode = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tap on text to edit it, or tap on empty space to add new text'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          // Content Edit mode (True PDF content editing - Sejda-style)
          _buildToolButton(
            icon: Icons.edit_document,
            label: 'Content Edit',
            isSelected: _isContentEditMode,
            onTap: () async {
              // Create editable copy if not exists
              if (_editableCopyPath == null) {
                final copyPath = await PDFContentEditorService.createEditableCopy(_actualFilePath ?? widget.filePath);
                if (copyPath != null) {
                  setState(() {
                    _editableCopyPath = copyPath;
                    _isContentEditMode = true;
                    _isEditingMode = false; // Exit annotation mode
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error creating editable copy'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } else {
                setState(() {
                  _isContentEditMode = true;
                  _isEditingMode = false; // Exit annotation mode
                });
              }
            },
            color: Colors.orange,
          ),
          // Done button
          _buildToolButton(
            icon: Icons.check,
            label: 'Done',
            isSelected: false,
            onTap: () {
              setState(() {
                _isEditingMode = false;
                _selectedTool = 'none';
              });
            },
            color: Colors.green,
          ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final buttonColor = color ?? (_selectedTool == 'pen' ? Colors.red : Colors.grey[700]!);
    final isEnabled = onTap != null;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? buttonColor.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? buttonColor : (isEnabled ? Colors.grey[600] : Colors.grey[400]),
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? buttonColor : (isEnabled ? Colors.grey[600] : Colors.grey[400]),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ]),
        ),
      ),
    );
  }

  void _showOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildOptionsBottomSheet(),
    );
  }

  Widget _buildOptionsBottomSheet() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : const Color(0xFF9E9E9E);
    
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // PDF File Information
          if (_pdfFileInfo != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pdfFileInfo!.name,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_pdfFileInfo!.date} • ${_pdfFileInfo!.size}',
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.star : Icons.star_outline,
                      color: _isFavorite
                          ? const Color(0xFFE53935)
                          : secondaryTextColor,
                    ),
                    onPressed: () async {
                      final newBookmarkStatus = !_isFavorite;
                      await PDFPreferencesService.setBookmark(
                        widget.filePath,
                        newBookmarkStatus,
                      );
                      setState(() {
                        _isFavorite = newBookmarkStatus;
                        if (_pdfFileInfo != null) {
                          _pdfFileInfo = PDFFile(
                            name: _pdfFileInfo!.name,
                            date: _pdfFileInfo!.date,
                            size: _pdfFileInfo!.size,
                            isFavorite: newBookmarkStatus,
                            filePath: _pdfFileInfo!.filePath,
                          );
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // Options List
          _buildOptionTile(
            icon: Icons.dark_mode,
            title: 'Dark mode',
            onTap: _toggleDarkMode,
          ),
          _buildOptionTile(
            icon: Icons.merge,
            title: 'Merge PDF',
            onTap: _mergePDF,
          ),
          _buildOptionTile(
            icon: Icons.content_cut,
            title: 'Split PDF',
            onTap: _splitPDF,
          ),
          _buildOptionTile(
            icon: Icons.arrow_forward,
            title: 'Go to page',
            onTap: _goToPageDialog,
          ),
          _buildOptionTile(
            icon: Icons.print,
            title: 'Print',
            onTap: _printPDF,
          ),
          _buildOptionTile(
            icon: Icons.save_alt,
            title: 'Save to device',
            onTap: _saveToDevice,
          ),
          _buildOptionTile(
            icon: Icons.share,
            title: 'Share',
            onTap: _sharePDF,
          ),
          _buildOptionTile(
            icon: Icons.delete,
            title: 'Delete',
            onTap: _deletePDF,
            isDestructive: true,
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final iconColor = isDestructive ? Colors.red : textColor;
    
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : textColor,
          fontSize: 16,
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  void _toggleDarkMode() async {
    final currentTheme = Theme.of(context).brightness;
    final newThemeMode = currentTheme == Brightness.dark 
        ? ThemeMode.light 
        : ThemeMode.dark;
    
    await ThemeService.setThemeMode(newThemeMode);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newThemeMode == ThemeMode.dark 
              ? 'Dark mode enabled' 
              : 'Light mode enabled'),
          duration: const Duration(seconds: 1),
        ),
      );
      // Navigate back and forward to trigger theme rebuild
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PDFViewerScreen(
            filePath: widget.filePath,
            fileName: widget.fileName,
          ),
        ),
      );
    }
  }

  Future<void> _mergePDF() async {
    try {
      // Show in-app file picker with multi-select
      final selectedFiles = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (context) => const InAppFilePicker(
            allowMultiSelect: true,
            title: 'Select PDFs to Merge',
          ),
        ),
      );

      if (selectedFiles == null || selectedFiles.isEmpty) return;
      
      // Include current PDF in merge
      final pdfPaths = [widget.filePath, ...selectedFiles];

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Merge PDFs
      final mergedPath = await PDFToolsService.mergePDFs(pdfPaths);

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      if (mergedPath != null) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'merge',
          widget.filePath,
          resultPath: mergedPath,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDFs merged successfully! File saved in app storage. Returning to file list...'),
              duration: Duration(seconds: 2),
            ),
          );
          
          // Pop back to home screen so file list refreshes and shows the merged file
          // The merged file is already in cache, so it will appear in the list
          Navigator.of(context).pop(true); // Return true to indicate refresh needed
        }
      } else {
        // PHASE 5: User-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to merge PDFs. One or more PDFs may be corrupted or too large.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // PHASE 5: Close loading dialog on error and show user-friendly message
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        final errorMessage = e.toString().contains('timeout')
            ? 'Merge operation timed out. The PDFs may be too large. Please try with smaller PDFs.'
            : e.toString().contains('permission')
                ? 'Permission denied. Please grant storage access in settings.'
                : 'An error occurred while merging PDFs. Please try again.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _splitPDF() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    
    showDialog(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: backgroundColor,
        ),
        child: AlertDialog(
          title: Text('Split PDF', style: TextStyle(color: textColor)),
          content: Text(
            'This will split "${widget.fileName}" into $_totalPages separate page files. Continue?',
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: textColor)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _performSplitPDF();
              },
              child: const Text('Split', style: TextStyle(color: Color(0xFFE53935))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performSplitPDF() async {
    BuildContext? dialogContext;
    
    try {
      // Show loading indicator with progress message
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogContext = context;
          return PopScope(
            canPop: false, // Prevent dismissing during operation
            child: Dialog(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Splitting PDF into $_totalPages pages...',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This may take a moment for large PDFs',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : Colors.black54,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      // Run split operation with timeout to prevent indefinite hanging
      final splitFiles = await PDFToolsService.splitPDF(widget.filePath)
          .timeout(
            const Duration(minutes: 5), // Max 5 minutes for very large PDFs
            onTimeout: () {
              print('Split PDF operation timed out');
              return <String>[];
            },
          )
          .catchError((e) {
            print('Error in split PDF: $e');
            return <String>[];
          });

      // Close loading dialog
      if (mounted && dialogContext != null) {
        Navigator.of(dialogContext!).pop();
      }

      if (splitFiles.isNotEmpty) {
        // Save to history
        await PDFPreferencesService.addToolsHistory(
          'split',
          widget.filePath,
          resultPath: splitFiles.first,
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF split successfully! Created ${splitFiles.length} page file(s). Files are saved in app storage.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
          
          // Pop back to home screen - it will reload files automatically
          Navigator.of(context).pop(true); // Return true to indicate refresh needed
        }
      } else {
        // PHASE 5: User-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to split PDF. The PDF may be too large or corrupted. Please try with a smaller PDF.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // PHASE 5: Close loading dialog on error and show user-friendly message
      if (mounted && dialogContext != null) {
        Navigator.of(dialogContext!).pop();
      }
      if (mounted) {
        final errorMessage = e.toString().contains('timeout')
            ? 'Split operation timed out. The PDF may be too large. Please try with a smaller PDF.'
            : e.toString().contains('permission')
                ? 'Permission denied. Please grant storage access in settings.'
                : 'An error occurred while splitting the PDF. Please try again.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _goToPageDialog() {
    final pageController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to Page'),
        content: TextField(
          controller: pageController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter page number (1-$_totalPages)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final pageNumber = int.tryParse(pageController.text);
              if (pageNumber != null &&
                  pageNumber >= 1 &&
                  pageNumber <= _totalPages) {
                Navigator.pop(context);
                _goToPage(pageNumber);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a valid page number (1-$_totalPages)'),
                  ),
                );
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  Future<void> _printPDF() async {
    try {
      if (_actualFilePath == null) {
        throw Exception('PDF file not available');
      }
      final file = File(_actualFilePath!);
      final bytes = await file.readAsBytes();
      
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error printing PDF: $e'),
        ),
      );
    }
  }

  Future<void> _saveToDevice() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF file not found'),
            ),
          );
        }
        return;
      }

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Try to save to app's external storage directory first (no permissions needed)
      // Then offer to share so user can save to Downloads if they want
      final fileName = path.basename(widget.filePath);
      Directory? targetDirectory;
      
      if (Platform.isAndroid) {
        // Use external storage directory (app-specific, no permissions needed)
        try {
          targetDirectory = await getExternalStorageDirectory();
          if (targetDirectory != null) {
            // Create a "Saved PDFs" subdirectory
            final savedPdfsDir = Directory('${targetDirectory.path}/Saved PDFs');
            if (!await savedPdfsDir.exists()) {
              await savedPdfsDir.create(recursive: true);
            }
            targetDirectory = savedPdfsDir;
          }
        } catch (e) {
          print('Error getting external storage: $e');
        }
      }
      
      // Fallback to app documents directory
      if (targetDirectory == null) {
        final appDocDir = await getApplicationDocumentsDirectory();
        final savedPdfsDir = Directory('${appDocDir.path}/Saved PDFs');
        if (!await savedPdfsDir.exists()) {
          await savedPdfsDir.create(recursive: true);
        }
        targetDirectory = savedPdfsDir;
      }

      // Ensure we have a valid directory
      if (targetDirectory == null) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not access device storage'),
            ),
          );
        }
        return;
      }

      // Copy file to target directory
      final targetPath = path.join(targetDirectory!.path, fileName);
      final targetFile = File(targetPath);
      await file.copy(targetPath);
      
      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }
      
      // Show success message and offer to share
      if (mounted) {
        final shouldShare = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('PDF Saved'),
            content: Text('PDF saved to:\n${targetDirectory!.path}\n\nWould you like to share it to save to Downloads?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No, thanks'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Share'),
              ),
            ],
          ),
        );
        
        if (shouldShare == true) {
          // Share the file so user can save to Downloads
          await Share.shareXFiles(
            [XFile(targetPath, name: fileName)],
            text: 'Save PDF: $fileName',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF saved to: ${targetDirectory!.path}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving PDF: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _sharePDF() async {
    try {
      if (_actualFilePath == null) {
        throw Exception('PDF file not available');
      }
      final file = File(_actualFilePath!);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(_actualFilePath!)],
          text: 'Check out this PDF: ${widget.fileName}',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF file not found'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing PDF: $e'),
        ),
      );
    }
  }

  void _deletePDF() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete PDF'),
        content: Text('Are you sure you want to delete "${widget.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final file = File(widget.filePath);
                if (await file.exists()) {
                  await file.delete();
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to home screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('PDF deleted successfully'),
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error deleting PDF: $e'),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _copySelectedText() async {
    try {
      // Syncfusion PDF viewer handles text selection natively
      // Users can select text by long-pressing and dragging
      // Once text is selected, they can copy it using the system's copy option
      // This button provides instructions on how to copy text
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Copy Text'),
            content: const Text(
              'To copy text from the PDF:\n\n'
              '1. Long press on the text you want to copy\n'
              '2. Drag to select the desired text\n'
              '3. Use the system copy option from the context menu that appears\n\n'
              'Text selection is enabled in the PDF viewer. The selected text will be automatically available for copying through the system menu.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleTextEditTap(Offset position) async {
    if (!_isTextEditMode || _selectedTool != 'text') return;
    
    // First check if user tapped on an existing text overlay
    final screenSize = MediaQuery.of(context).size;
    final tappedText = _textAnnotations.firstWhere(
      (textAnnotation) {
        if (textAnnotation.pageNumber != _currentPage) return false;
        final screenX = textAnnotation.position.dx * screenSize.width;
        final screenY = textAnnotation.documentY != null
            ? textAnnotation.documentY! - _pdfScrollOffset
            : textAnnotation.position.dy * screenSize.height;
        
        // Check if tap is within text bounds (approximate - text width based on length)
        final textWidth = textAnnotation.text.length * textAnnotation.fontSize * 0.6;
        final textHeight = textAnnotation.fontSize;
        final textRect = Rect.fromLTWH(
          screenX - 5,
          screenY - 5,
          textWidth + 10,
          textHeight + 10,
        );
        return textRect.contains(position);
      },
      orElse: () => TextAnnotation(
        text: '',
        position: Offset.zero,
        color: Colors.black,
        pageNumber: -1,
      ),
    );
    
    if (tappedText.pageNumber == _currentPage && tappedText.text.isNotEmpty) {
      // Edit existing text overlay
      _editTextAnnotation(tappedText);
      return;
    }
    
    // No existing text found - add new text at tap position
    _showTextEditDialog(
      initialText: '',
      position: position,
      isEditing: false,
    );
  }
  
  void _editTextAnnotation(TextAnnotation textAnnotation) {
    _showTextEditDialog(
      initialText: textAnnotation.id, // Use ID to identify which annotation to edit
      position: Offset(
        textAnnotation.position.dx * MediaQuery.of(context).size.width,
        textAnnotation.documentY != null
            ? textAnnotation.documentY! - _pdfScrollOffset
            : textAnnotation.position.dy * MediaQuery.of(context).size.height,
      ),
      isEditing: true,
      existingAnnotation: textAnnotation,
    );
  }

  void _showTextEditDialog({
    required String initialText,
    required Offset position,
    required bool isEditing,
    TextAnnotation? existingAnnotation,
  }) {
    final textController = TextEditingController(
      text: existingAnnotation?.text ?? initialText,
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Text' : 'Add Text'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Enter text',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isTextEditMode = false;
                _selectedTool = 'none';
              });
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newText = textController.text.trim();
              
              // Validate: don't allow empty text when adding new
              if (!isEditing && newText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter some text'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              
              Navigator.pop(context);
              
              if (isEditing && existingAnnotation != null) {
                // Update existing text annotation
                final index = _textAnnotations.indexWhere((t) => t.id == existingAnnotation.id);
                if (index != -1) {
                  setState(() {
                    if (newText.isEmpty) {
                      // Remove if text is empty
                      _textAnnotations.removeAt(index);
                    } else {
                      // Update text
                      _textAnnotations[index] = TextAnnotation(
                        text: newText,
                        position: existingAnnotation.position,
                        color: existingAnnotation.color,
                        fontSize: existingAnnotation.fontSize,
                        pageNumber: existingAnnotation.pageNumber,
                        documentY: existingAnnotation.documentY,
                        id: existingAnnotation.id,
                      );
                    }
                  });
                }
              } else {
                // Add new text annotation instantly (Sejda-style - no PDF save)
                final normalizedPosition = Offset(
                  position.dx / MediaQuery.of(context).size.width,
                  position.dy / MediaQuery.of(context).size.height,
                );
                
                setState(() {
                  _textAnnotations.add(TextAnnotation(
                    text: newText,
                    position: normalizedPosition,
                    color: _selectedColor,
                    fontSize: 12.0,
                    pageNumber: _currentPage,
                    documentY: position.dy + _pdfScrollOffset,
                  ));
                });
              }
              
              // Reset text edit mode
              setState(() {
                _isTextEditMode = false;
                _selectedTool = 'none';
              });
            },
            child: Text(isEditing ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _showTextInputDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Text Annotation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter text to add as annotation. The text will be added to the current page.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter text to add',
                border: OutlineInputBorder(),
                labelText: 'Text',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                Navigator.pop(context);
                // For now, show a message. In future, this could add text annotation
                // to the PDF at the current page position
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Text annotation "${textController.text}" will be added. Use Pen tool to draw text annotations.'),
                    duration: const Duration(seconds: 3),
                  ),
                );
                // Note: True text editing (like Sejda) requires PDF text extraction
                // and manipulation which is complex. For now, users can use the Pen tool
                // to write text manually or use text selection to copy existing text.
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search in PDF'),
        content: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Enter text to search',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              _pdfViewerController.searchText(value);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              _searchController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_searchController.text.isNotEmpty) {
                _pdfViewerController.searchText(_searchController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  void _toggleOrientation() async {
    setState(() {
      _isPortrait = !_isPortrait;
    });
    
    // Actually change the device orientation
    if (_isPortrait) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }


  void _showViewModeBottomSheet() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'View mode',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            _buildViewModeOption(
              icon: Icons.view_column,
              title: 'Vertical scroll',
              value: 'vertical',
            ),
            _buildViewModeOption(
              icon: Icons.view_agenda,
              title: 'Horizontal scroll',
              value: 'horizontal',
            ),
            _buildViewModeOption(
              icon: Icons.view_module,
              title: 'Page by page',
              value: 'page',
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeOption({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final isSelected = _viewMode == value;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final unselectedColor = isDarkMode ? Colors.grey[400] : const Color(0xFF9E9E9E);
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFFE53935) : unselectedColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? textColor : unselectedColor,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Radio<String>(
        value: value,
        groupValue: _viewMode,
        onChanged: (newValue) {
          final currentPage = _currentPage;
          setState(() {
            _viewMode = newValue!;
          });
          Navigator.pop(context);
          // Restore current page after view mode change
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && currentPage >= 1 && currentPage <= _totalPages) {
              _pdfViewerController.jumpToPage(currentPage);
            }
          });
        },
        activeColor: const Color(0xFFE53935),
      ),
      onTap: () {
        final currentPage = _currentPage;
        setState(() {
          _viewMode = value;
        });
        Navigator.pop(context);
        // Restore current page after view mode change
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && currentPage >= 1 && currentPage <= _totalPages) {
            _pdfViewerController.jumpToPage(currentPage);
          }
        });
      },
    );
  }

  Widget _buildPagePreviewBar() {
    // CRITICAL FIX: Get system insets to account for navigation bar height
    // On gesture navigation devices (Android 13-14), this is typically ~23px
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom; // System navigation bar height
    
    // Show all pages that can fit in the screen width
    final thumbnailWidth = 60.0; // Width of each thumbnail
    
    // Show all pages in a scrollable list
    return Container(
      // Dynamic height: base height (100) + system navigation bar padding
      // This ensures preview bar is never cut off on any Android version
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        // Base preview bar height (100) - padding is already applied to parent Container
        height: 100,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _totalPages,
          controller: _pagePreviewScrollController,
          physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final pageNumber = index + 1;
          final isActive = _currentPage == pageNumber;
          return GestureDetector(
            onTap: () => _goToPage(pageNumber),
            child: Container(
              width: thumbnailWidth,
              height: 80,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.grey[200],
                border: Border.all(
                  color: isActive
                      ? const Color(0xFFE53935)
                      : Colors.grey[300]!,
                  width: isActive ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Page thumbnail
                  SizedBox(
                    width: 40,
                    height: 50,
                    child: _buildPageThumbnail(pageNumber, isActive),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$pageNumber',
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFFE53935)
                          : Colors.grey[600],
                      fontSize: 10,
                      fontWeight: isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _buildPageThumbnail(int pageNumber, bool isActive) {
    return Container(
      width: 40,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? const Color(0xFFE53935) : Colors.grey[300]!,
          width: isActive ? 1.5 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Actual PDF page thumbnail using small viewer
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _PDFThumbnailViewer(
                filePath: _actualFilePath ?? widget.filePath,
                pageNumber: pageNumber,
              ),
            ),
          ),
          // Page number at top
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '$pageNumber',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
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

// Widget to display a single PDF page as thumbnail
class _PDFThumbnailViewer extends StatefulWidget {
  final String filePath;
  final int pageNumber;

  const _PDFThumbnailViewer({
    required this.filePath,
    required this.pageNumber,
  });

  @override
  State<_PDFThumbnailViewer> createState() => _PDFThumbnailViewerState();
}

class _PDFThumbnailViewerState extends State<_PDFThumbnailViewer> {
  late PdfViewerController _controller;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    // Jump to the specific page after a short delay
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _controller.jumpToPage(widget.pageNumber);
        setState(() {
          _isLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: _isLoaded
          ? SfPdfViewer.file(
              File(widget.filePath),
              controller: _controller,
              enableDoubleTapZooming: false,
              enableTextSelection: false,
              canShowScrollHead: false,
              canShowScrollStatus: false,
              canShowPaginationDialog: false,
              canShowPasswordDialog: false,
              pageLayoutMode: PdfPageLayoutMode.single,
              scrollDirection: PdfScrollDirection.horizontal,
              onDocumentLoaded: (details) {
                if (mounted) {
                  _controller.jumpToPage(widget.pageNumber);
                }
              },
            )
          : Container(
              color: Colors.grey[200],
              child: const Center(
                child: SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1,
                  ),
                ),
              ),
            ),
    );
  }
}

