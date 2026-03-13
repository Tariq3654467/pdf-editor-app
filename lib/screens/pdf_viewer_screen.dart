import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import '../services/pdf_service.dart';
import '../services/pdf_tools_service.dart';
import '../services/pdf_preferences_service.dart';
import '../services/pdf_text_editor_service.dart';
import '../services/pdf_cache_service.dart';
import '../services/theme_service.dart';
import '../models/pdf_file.dart';
import '../widgets/pdf_annotation_overlay.dart';
import '../widgets/pdf_text_formatting_toolbar.dart';
import '../models/selected_pdf_text.dart';
import '../services/pdf_text_selection_service.dart';
import '../services/mupdf_editor_service.dart';
import '../services/pdf_save_service.dart';
import '../widgets/in_app_file_picker.dart';
import '../widgets/text_aware_annotation_overlay.dart';
import '../models/pdf_annotation.dart';
import '../services/annotation_storage_service.dart';
import 'pdf_word_editor_screen.dart';

/// Active tool for the bottom annotation toolbar
enum PdfTool { none, copy, pen, highlight, underline, eraser }

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
  Timer? _pdfReloadDebounceTimer; // Debounce timer for PDF reloads
  bool _isScrolling = false;
  bool _showPagePreview = true; // Control visibility of page preview bar
  double _pdfScrollOffset = 0.0; // Track PDF vertical scroll offset for annotations
  int _pdfReloadKey = 0; // Key to force PDF viewer reload after modifications
  bool _isSavingAnnotation = false; // Prevent multiple simultaneous saves
  DateTime? _lastReloadTime; // Track last reload time to prevent excessive reloads
  
  // Text-aware annotation system
  Size? _pdfPageSize; // PDF page size in points
  double _zoomLevel = 1.0;
  List<PDFAnnotation> _savedAnnotations = [];
  final AnnotationStorageService _annotationStorage = AnnotationStorageService();
  
  // Error handling
  String? _errorMessage;
  String? _actualFilePath; // May differ from widget.filePath if content URI was copied
  Uint8List? _pdfBytes; // PDF file bytes for memory-based loading (more reliable)
  Timer? _loadingTimeoutTimer;
  static const MethodChannel _fileChannel = MethodChannel('com.example.pdf_editor_app/file_intent');
  
  // Annotation/Editing state
  bool _isEditingMode = false;
  bool _isContentEditMode = false; // True content editing mode (Sejda-style)
  PdfTool _selectedTool = PdfTool.none;
  // Internal string mode used by overlays/text editor: 'pen', 'highlight', 'underline', 'eraser', 'text', 'none'
  String _selectedMode = 'none';
  Color _selectedColor = Colors.red;
  double _strokeWidth = 3.0;
  final GlobalKey<PDFAnnotationOverlayState> _annotationOverlayKey = GlobalKey<PDFAnnotationOverlayState>();
  final GlobalKey<TextAwareAnnotationOverlayState> _textAwareOverlayKey = GlobalKey<TextAwareAnnotationOverlayState>();
  bool _canUndo = false;
  bool _canRedo = false;
  
  // Text editing state (Sejda-style)
  Offset? _textEditPosition;
  String? _editingText;
  bool _isTextEditMode = false;
  List<TextAnnotation> _textAnnotations = []; // Instant text overlays (not saved to PDF yet)
  
  // Text selection state (Sejda-style - select existing text to edit)
  SelectedPDFText? _selectedPDFText;
  String? _selectedPDFTextObjectId; // MuPDF object ID for text replacement
  
  // Cache for text detection to avoid repeated lookups
  final Map<String, dynamic> _textDetectionCache = {};
  static const int _maxCacheSize = 50; // Limit cache size
  Offset? _textSelectionToolbarPosition;
  bool _showTextFormattingToolbar = false;
  bool _isScannedDocument = false; // Track if PDF is scanned (image-based)
  
  
  // View mode and orientation
  String _viewMode = 'vertical'; // 'vertical', 'horizontal', 'page'
  bool _isPortrait = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _pagePreviewScrollController = ScrollController();

  // Helper to determine when a drawing tool is really active
  bool get _isDrawingToolActive =>
      _isEditingMode &&
      (_selectedTool == PdfTool.pen ||
       _selectedTool == PdfTool.highlight ||
       _selectedTool == PdfTool.underline ||
       _selectedTool == PdfTool.eraser);

  /// Map the active [PdfTool] to the overlay's string-based tool id
  String? get _selectedOverlayTool {
    if (!_isEditingMode) return null;
    switch (_selectedTool) {
      case PdfTool.pen:
        return 'pen';
      case PdfTool.eraser:
        return 'eraser';
      case PdfTool.highlight:
      case PdfTool.underline:
      case PdfTool.copy:
      case PdfTool.none:
        // Copy/none should not block PDF viewer gestures
        return null;
    }
  }

  /// Central place to activate a tool and keep state in sync
  void _selectTool(PdfTool tool) {
    setState(() {
      _selectedTool = tool;
      _isEditingMode = tool != PdfTool.none;

      // Map enum to internal string mode for existing overlays/text editor
      switch (tool) {
        case PdfTool.pen:
          _selectedMode = 'pen';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          break;
        case PdfTool.highlight:
          _selectedMode = 'none'; // handled by Syncfusion annotationMode
          _pdfViewerController.annotationMode = PdfAnnotationMode.highlight;
          break;
        case PdfTool.underline:
          _selectedMode = 'none'; // handled by Syncfusion annotationMode
          _pdfViewerController.annotationMode = PdfAnnotationMode.underline;
          break;
        case PdfTool.eraser:
          _selectedMode = 'eraser';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          break;
        case PdfTool.copy:
          _selectedMode = 'none'; // copy should not interfere with overlay gestures
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          break;
        case PdfTool.none:
          _selectedMode = 'none';
          _pdfViewerController.annotationMode = PdfAnnotationMode.none;
          break;
      }

      // Exiting any text-editing mode when switching tools
      _isTextEditMode = false;
      _selectedPDFText = null;
      _showTextFormattingToolbar = false;
    });
  }

  /// Handle tapping the Done button: persist annotations & exit edit mode
  Future<void> _onDoneEditing() async {
    // Cancel any pending debounced reloads
    _pdfReloadDebounceTimer?.cancel();

    // Persist custom overlay annotations snapshot via storage service if possible
    try {
      if (_actualFilePath != null && _savedAnnotations.isNotEmpty) {
        await _annotationStorage.saveAnnotations(_actualFilePath!, _savedAnnotations);
      }
    } catch (e) {
      // Non-fatal; we still exit edit mode but log the error
      print('Error saving annotations on Done: $e');
    }

    if (!mounted) return;

    setState(() {
      _isEditingMode = false;
      _selectedTool = PdfTool.none;
      _selectedMode = 'none';
      _pdfViewerController.annotationMode = PdfAnnotationMode.none;
      // Reload PDF when exiting edit mode to show all saved annotations
      _loadPDFBytes().catchError((e) {
        print('PDFViewer: Error reloading PDF bytes: $e');
      });
      _pdfReloadKey++;
    });

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All changes saved'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

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
    _pdfReloadDebounceTimer?.cancel();
    _textPreviewDebounceTimer?.cancel();
    _formattingDebounceTimer?.cancel();
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
              // Load PDF bytes for memory-based loading (more reliable)
              _loadPDFBytes().catchError((e) {
                print('PDFViewer: Error loading PDF bytes: $e');
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
                      // Load PDF bytes for memory-based loading (more reliable)
                      _loadPDFBytes().catchError((e) {
                        print('PDFViewer: Error loading PDF bytes: $e');
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

  /// Load PDF bytes for memory-based loading (more reliable than file path)
  Future<void> _loadPDFBytes() async {
    if (_actualFilePath == null || !mounted) return;
    
    try {
      final file = File(_actualFilePath!);
      
      // Check existence with timeout
      final exists = await file.exists()
          .timeout(const Duration(seconds: 2))
          .catchError((e) {
            print('PDFViewer: Error checking file for bytes: $e');
            return false;
          });
          
      if (exists) {
        // Read PDF bytes with timeout
        final bytes = await file.readAsBytes()
            .timeout(const Duration(seconds: 10))
            .catchError((e) {
              print('PDFViewer: Error reading PDF bytes: $e');
              return null;
            });
            
        if (bytes != null && mounted) {
          setState(() {
            _pdfBytes = bytes;
          });
          print('PDFViewer: Loaded PDF bytes: ${bytes.length} bytes');
        } else {
          print('PDFViewer: Failed to read PDF bytes');
        }
      }
    } catch (e) {
      print('PDFViewer: Error loading PDF bytes: $e');
      // Don't set error message here - let file-based loading try as fallback
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
        
        // Get page size for annotation coordinate system
        if (details.document.pages.count > 0) {
          final firstPage = details.document.pages[0];
          _pdfPageSize = Size(firstPage.size.width, firstPage.size.height);
        }
      });
      
      // Load saved annotations
      _loadSavedAnnotations();
      
      // Check if document is scanned (image-based, no extractable text)
      _checkIfScannedDocument();
      
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
  
  /// Load saved annotations for current PDF
  Future<void> _loadSavedAnnotations() async {
    try {
      final annotations = await _annotationStorage.loadAnnotations(_actualFilePath ?? widget.filePath);
      if (mounted) {
        setState(() {
          _savedAnnotations = annotations;
        });
      }
    } catch (e) {
      print('Error loading annotations: $e');
    }
  }
  
  /// Check if PDF is a scanned document and disable text editing if so
  Future<void> _checkIfScannedDocument() async {
    try {
      final isScanned = await PDFTextSelectionService.isScannedDocument(
        _actualFilePath ?? widget.filePath,
      );
      
      if (mounted) {
        setState(() {
          _isScannedDocument = isScanned;
        });
        
        if (isScanned) {
          print('PDFViewer: Scanned document detected - text editing disabled');
        }
      }
    } catch (e) {
      print('Error checking if document is scanned: $e');
    }
  }
  
  void _onDocumentLoadFailed(PdfDocumentLoadFailedDetails details) {
    final error = details.error;
    final errorMessage = error?.toString() ?? 'Unknown error';
    print('PDFViewer: Document load failed: $errorMessage');
    print('PDFViewer: Error type: ${error.runtimeType}');
    if (error is Exception) {
      print('PDFViewer: Exception details: ${error.toString()}');
    }
    _loadingTimeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load PDF: $errorMessage\n\nThe file might be corrupted or in an unsupported format.';
      });
    }
  }

  /// Build blue bounding box overlay for selected text (Sejda-style)
  Widget _buildTextSelectionBox() {
    if (_selectedPDFText == null || _pdfPageSize == null) {
      return const SizedBox.shrink();
    }

    // Convert PDF bounds to screen coordinates
    final screenSize = MediaQuery.of(context).size;
    final pageSize = _pdfPageSize!;
    
    // Calculate rendered PDF dimensions
    final pdfAspectRatio = pageSize.height / pageSize.width;
    final renderedPdfWidth = screenSize.width;
    final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;
    
    // Get PDF bounds
    final pdfBounds = _selectedPDFText!.bounds;
    
    // Convert PDF coordinates to screen coordinates
    // PDF uses bottom-left origin, screen uses top-left
    final screenX = (pdfBounds.left / pageSize.width) * renderedPdfWidth;
    // PDF Y is from bottom, screen Y is from top
    final pdfYFromBottom = pdfBounds.top; // Top of bounds in PDF coordinates
    final screenYFromTop = renderedPdfHeight - (pdfYFromBottom / pageSize.height) * renderedPdfHeight;
    
    // Account for page offset in continuous scroll mode
    final pageIndex = _selectedPDFText!.pageIndex;
    final pageStartY = pageIndex * renderedPdfHeight;
    final adjustedScreenY = pageStartY + screenYFromTop - _pdfScrollOffset;
    
    // Calculate width and height in screen coordinates
    final screenWidth = (pdfBounds.width / pageSize.width) * renderedPdfWidth;
    final screenHeight = (pdfBounds.height / pageSize.height) * renderedPdfHeight;
    
    return Positioned(
      left: screenX.clamp(0.0, screenSize.width),
      top: adjustedScreenY.clamp(0.0, screenSize.height),
      child: IgnorePointer(
        child: Container(
          width: screenWidth,
          height: screenHeight,
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFF2196F3), // Blue color like in screenshot
              width: 2.0,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
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
    
    // Wrap PDF viewer in RepaintBoundary to prevent full-screen repaints
    // Use LayoutBuilder so we get the ACTUAL PDF viewer size (not full screen)
    final pdfViewer = RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewerSize = constraints.biggest;
          
          // Use memory-based loading if bytes are available (more reliable)
          // Otherwise fall back to file-based loading
          Widget viewer;
          if (_pdfBytes != null) {
            print('PDFViewer: Using memory-based loading (${_pdfBytes!.length} bytes)');
            viewer = SfPdfViewer.memory(
              _pdfBytes!,
              key: ValueKey('pdf_viewer_memory_${filePath}_$_viewMode$_pdfReloadKey'),
              controller: _pdfViewerController,
              onDocumentLoaded: _onDocumentLoaded,
              onDocumentLoadFailed: _onDocumentLoadFailed,
              onPageChanged: _onPageChanged,
              scrollDirection: _getScrollDirection(),
              pageLayoutMode: _getPageLayoutMode(),
              enableDoubleTapZooming: true,
              enableTextSelection: true,
            );
          } else {
            print('PDFViewer: Using file-based loading (fallback)');
            final file = File(filePath);
            viewer = SfPdfViewer.file(
              file,
              key: ValueKey('pdf_viewer_file_${filePath}_$_viewMode$_pdfReloadKey'),
              controller: _pdfViewerController,
              onDocumentLoaded: _onDocumentLoaded,
              onDocumentLoadFailed: _onDocumentLoadFailed,
              onPageChanged: _onPageChanged,
              scrollDirection: _getScrollDirection(),
              pageLayoutMode: _getPageLayoutMode(),
              enableDoubleTapZooming: true,
              enableTextSelection: true,
            );
          }
          
          // Enable text editing on tap (Sejda-style: tap on text to edit)
          // Only intercept taps when not in drawing mode
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (details) {
              // Only try to detect text if not in drawing mode
              if (!_isEditingMode || _selectedMode == 'none' || _selectedMode == 'text') {
                _handleTextEditTap(details.localPosition);
              }
            },
            child: viewer,
          );
        },
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
          // Edit button - Convert to Word format for editing
          IconButton(
            icon: Icon(
              Icons.edit_document,
              color: iconColor,
              size: 24,
            ),
            onPressed: _showEditOptions,
            tooltip: 'Edit PDF Text',
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
            // PDF Viewer with text-aware annotation overlay
            TextAwareAnnotationOverlay(
            key: _textAwareOverlayKey,
            pdfPath: _actualFilePath ?? widget.filePath,
            currentPage: _currentPage - 1, // Convert to 0-based
            pageSize: _pdfPageSize ?? Size(612, 792), // Default US Letter if not loaded
            zoomLevel: _zoomLevel,
            scrollOffset: Offset(0, _pdfScrollOffset),
            screenSize: MediaQuery.of(context).size,
            selectedTool: _selectedOverlayTool,
            toolColor: _selectedColor,
            strokeWidth: _strokeWidth,
            onAnnotationsChanged: (annotations) {
              setState(() {
                _savedAnnotations = annotations;
              });
            },
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
          // Blue bounding box overlay for selected text (Sejda-style)
          if (_selectedPDFText != null && _selectedPDFText!.pageIndex == _currentPage - 1)
            _buildTextSelectionBox(),
          // Text formatting toolbar (appears when text is selected - Sejda-style)
          // Positioned at bottom to always be visible and accessible
          if (_showTextFormattingToolbar && _selectedPDFText != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).viewInsets.bottom, // Adjust for keyboard
              child: SafeArea(
                top: false,
                child: PDFTextFormattingToolbar(
                  text: _selectedPDFText!.text,
                  isBold: _selectedPDFText!.isBold,
                  isItalic: _selectedPDFText!.isItalic,
                  fontFamily: _selectedPDFText!.fontFamily,
                  fontSize: _selectedPDFText!.fontSize,
                  textColor: _selectedPDFText!.color,
                  onTextChanged: (newText) => _updateTextContentPreview(newText), // Update preview only
                  onBoldChanged: (isBold) => _applyTextFormatting(isBold: isBold),
                  onItalicChanged: (isItalic) => _applyTextFormatting(isItalic: isItalic),
                  onFontChanged: (font) => _applyTextFormatting(fontFamily: font),
                  onFontSizeChanged: (size) => _applyTextFormatting(fontSize: size),
                  onColorChanged: (color) => _applyTextFormatting(color: color),
                  onDelete: _deleteSelectedText,
                  onCopy: _copySelectedText,
                  onLink: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link feature coming soon')),
                    );
                  },
                  onClose: () {
                    _closeTextToolbar();
                  },
                  onDone: () async {
                    // Save text to PDF when user clicks "Done"
                    await _saveTextContent();
                    if (mounted) {
                      _closeTextToolbarAfterSave();
                    }
                  },
                  isLoading: _isSavingText, // Show loading state
                ),
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
      case PdfTool.highlight:
        return Colors.yellow.withOpacity(0.4);
      case PdfTool.underline:
        return Colors.blue;
      case PdfTool.eraser:
        return Colors.white;
      case PdfTool.pen:
      case PdfTool.copy:
      case PdfTool.none:
        return _selectedColor;
    }
  }

  double _getStrokeWidth() {
    switch (_selectedTool) {
      case PdfTool.highlight:
        return 15.0; // Thicker for highlight
      case PdfTool.underline:
        return 2.0; // Thin line for underline
      case PdfTool.eraser:
        return 20.0; // Larger eraser
      case PdfTool.pen:
      case PdfTool.copy:
      case PdfTool.none:
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
                  // Try TextAwareAnnotationOverlay first (new system)
                  _textAwareOverlayKey.currentState?.undo();
                  // Fallback to old overlay if needed
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
                  // Try TextAwareAnnotationOverlay first (new system)
                  _textAwareOverlayKey.currentState?.redo();
                  // Fallback to old overlay if needed
                  _annotationOverlayKey.currentState?.redo();
                }
                : null,
          ),
          // Copy text button
          _buildToolButton(
            icon: Icons.content_copy,
            label: 'Copy',
            isSelected: _selectedTool == PdfTool.copy,
            onTap: () {
              // If Copy is already active and we have text, perform copy immediately
              if (_selectedTool == PdfTool.copy && _selectedPDFText != null) {
                _copySelectedText();
                return;
              }

              // Activate copy tool (does not engage drawing overlay)
              _selectTool(PdfTool.copy);

              if (_selectedPDFText == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Long‑press text in the PDF to select it, then tap Copy again.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          // Pen tool
          _buildToolButton(
            icon: Icons.edit,
            label: 'Pen',
            isSelected: _selectedTool == PdfTool.pen,
            onTap: () {
              _selectTool(PdfTool.pen);
            },
          ),
          // Highlight tool
          _buildToolButton(
            icon: Icons.highlight,
            label: 'Highlight',
            isSelected: _selectedTool == PdfTool.highlight,
            onTap: () {
              _selectTool(PdfTool.highlight);
            },
          ),
          // Underline tool
          _buildToolButton(
            icon: Icons.format_underline,
            label: 'Underline',
            isSelected: _selectedTool == PdfTool.underline,
            onTap: () {
              _selectTool(PdfTool.underline);
            },
          ),
          // Eraser tool
          _buildToolButton(
            icon: Icons.cleaning_services,
            label: 'Eraser',
            isSelected: _selectedTool == PdfTool.eraser,
            onTap: () {
              _selectTool(PdfTool.eraser);
            },
          ),
          // Done button
          _buildToolButton(
            icon: Icons.check,
            label: 'Done',
            isSelected: false,
            onTap: () {
              _onDoneEditing();
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
    // Determine button color based on tool type
    Color buttonColor;
    if (color != null) {
      buttonColor = color;
    } else {
      switch (_selectedTool) {
        case PdfTool.pen:
          buttonColor = Colors.red;
          break;
        case PdfTool.highlight:
          buttonColor = Colors.yellow[700]!;
          break;
        case PdfTool.underline:
          buttonColor = Colors.blue;
          break;
        case PdfTool.eraser:
          buttonColor = Colors.orange;
          break;
        case PdfTool.copy:
        case PdfTool.none:
          buttonColor = Colors.grey[700]!;
      }
    }
    
    final isEnabled = onTap != null;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? buttonColor.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: buttonColor.withOpacity(0.3), width: 1) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? buttonColor : (isEnabled ? Colors.grey[700] : Colors.grey[400]),
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? buttonColor : (isEnabled ? Colors.grey[700] : Colors.grey[400]),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
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
      final file = File(_actualFilePath ?? widget.filePath);
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

      // Get annotations from overlay
      final annotations = _annotationOverlayKey.currentState?.annotations ?? [];
      
      // Save PDF with annotations using MuPDF (true PDF content objects)
      final saveSuccess = await PDFSaveService.savePDFWithProgress(
        context: context,
        filePath: _actualFilePath ?? widget.filePath,
        annotations: annotations,
        successMessage: 'PDF saved with annotations',
      );
      
      if (!saveSuccess) {
        return; // Error already shown in savePDFWithProgress
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not access device storage'),
            ),
          );
        }
        return;
      }

      // Copy file (with annotations already saved) to target directory
      final targetPath = path.join(targetDirectory!.path, fileName);
      final targetFile = File(targetPath);
      await file.copy(targetPath);
      
      // Show success message and offer to share
      if (mounted) {
        final shouldShare = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('PDF Saved'),
            content: Text('PDF with annotations saved to:\n${targetDirectory!.path}\n\nWould you like to share it to save to Downloads?'),
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
              content: Text('PDF with annotations saved to: ${targetDirectory!.path}'),
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

  void _copySelectedText() {
    if (_selectedPDFText == null) return;
    
    Clipboard.setData(ClipboardData(text: _selectedPDFText!.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Text copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showEditOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Edit inside PDF'),
              subtitle: const Text('Tap existing text to edit, or empty space to add text'),
              onTap: () {
                Navigator.pop(context);
                _enableInlineTextEditingMode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Full text editor'),
              subtitle: const Text('Edit all text while keeping the original PDF layout'),
              onTap: () {
                Navigator.pop(context);
                _openWordEditor();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _enableInlineTextEditingMode() {
    setState(() {
      _isEditingMode = true;
      _selectedTool = PdfTool.none;
      _selectedMode = 'text';
      _isTextEditMode = true;
      _selectedPDFText = null;
      _selectedPDFTextObjectId = null;
      _showTextFormattingToolbar = false;
      _pdfViewerController.annotationMode = PdfAnnotationMode.none;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tap text to edit it, or tap an empty spot to add new text.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Open Word editor for full document text editing
  Future<void> _openWordEditor() async {
    try {
      final pdfPath = _actualFilePath ?? widget.filePath;
      
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Navigate to Word editor screen
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => PDFWordEditorScreen(
            pdfPath: pdfPath,
            pdfFileName: widget.fileName,
          ),
        ),
      );
      
      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }
      
      // If a new PDF was created, reload it
      if (result != null && mounted) {
        // Check if the new PDF exists
        final newFile = File(result);
        if (await newFile.exists()) {
          // Reload PDF bytes
          setState(() {
            _actualFilePath = result;
            _pdfReloadKey++;
          });
          await _loadPDFBytes();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF updated successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening editor: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleTextEditTap(Offset position) async {
    // Allow text editing even if text tool wasn't explicitly selected
    // This makes it more intuitive - just tap on text to edit
    if (!_isTextEditMode && _selectedMode != 'text') {
      // Auto-enable text mode when user taps (more intuitive)
      setState(() {
        _selectedMode = 'text';
        _isTextEditMode = true;
      });
    }
    
    // Don't allow text editing on scanned documents
    if (_isScannedDocument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text editing is not available for scanned documents. This PDF contains only images.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Sejda-style: Try to find existing text first
    // If text found → toolbar appears automatically (NO DIALOG)
    // If no text found → just show hint, NO DIALOG
    // Use full screen size here as an approximation of viewer size
    await _handlePDFTextTap(position, MediaQuery.of(context).size);
    
    // Sejda-style: NO DIALOG when clicking on text or empty space
    // The toolbar handles all editing inline
  }
  
  Future<void> _addTextToPDF(String text, Offset screenPosition) async {
    if (text.isEmpty) return;
    
    // Don't allow adding text to scanned documents
    if (_isScannedDocument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text editing is not available for scanned documents. This PDF contains only images.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Get PDF page size and convert screen position to PDF coordinates
      final file = File(_actualFilePath ?? widget.filePath);
      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (_currentPage - 1 >= 0 && _currentPage - 1 < document.pages.count) {
        final page = document.pages[_currentPage - 1];
        final pageSize = page.size;
        final screenSize = MediaQuery.of(context).size;
        
        // Convert screen position to PDF coordinates
        // Syncfusion PDF viewer renders pages scaled to fit screen width
        // We need to account for scroll offset and calculate which page we're on
        
        // Calculate rendered PDF dimensions
        // PDF is scaled to fit screen width, height scales proportionally
        final pdfAspectRatio = pageSize.height / pageSize.width;
        final renderedPdfWidth = screenSize.width;
        final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;
        
        // Account for scroll - screen position is relative to visible viewport
        final absoluteDocumentY = screenPosition.dy + _pdfScrollOffset;
        
        // Calculate which page this position belongs to (for multi-page vertical scroll)
        final pageIndex = (absoluteDocumentY / renderedPdfHeight).floor();
        final pageStartY = pageIndex * renderedPdfHeight;
        final relativeYInPage = absoluteDocumentY - pageStartY;
        
        // Convert to PDF page coordinates (points, not pixels)
        // X: screen X position maps directly to PDF X (both scale with width)
        final pdfX = (screenPosition.dx / renderedPdfWidth) * pageSize.width;
        // Y: relative position in page maps to PDF Y
        final pdfY = (relativeYInPage / renderedPdfHeight) * pageSize.height;
        
        // Clamp to page bounds
        final clampedX = pdfX.clamp(0.0, pageSize.width);
        final clampedY = pdfY.clamp(0.0, pageSize.height);
        
        // Add text to PDF
        final graphics = page.graphics;
        final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12);
        final brush = sf.PdfSolidBrush(sf.PdfColor(
          _selectedColor.red,
          _selectedColor.green,
          _selectedColor.blue,
        ));
        
        final stringFormat = sf.PdfStringFormat();
        stringFormat.alignment = sf.PdfTextAlignment.left;
        stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
        
        graphics.drawString(
          text,
          font,
          brush: brush,
          format: stringFormat,
          bounds: Rect.fromLTWH(
            clampedX,
            clampedY,
            pageSize.width - clampedX,
            100, // Allow multi-line text
          ),
        );
        
        // Save PDF
        final modifiedBytes = await document.save();
        await file.writeAsBytes(modifiedBytes);
        document.dispose();
        
        // Don't reload PDF immediately - it causes hangs
        if (mounted) {
          Navigator.pop(context); // Close loading
          setState(() {
            // Changes will be visible when PDF is reopened or when exiting edit mode
            _isTextEditMode = false;
            _selectedMode = 'none';
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Text added to PDF'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        document.dispose();
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding text: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
  
  /// Save annotation directly to PDF content when drawing completes (non-blocking)
  void _saveAnnotationToPDF(List<AnnotationPoint> path) {
    if (path.isEmpty) return;
    
    // Prevent multiple simultaneous saves
    if (_isSavingAnnotation) {
      print('Annotation save already in progress, skipping...');
      return;
    }
    
    // Run save operation in background without blocking UI
    Future<void>.microtask(() async {
      if (_isSavingAnnotation) return; // Double check
      _isSavingAnnotation = true;
      
      try {
        final firstPoint = path.first;
        final pageIndex = firstPoint.pageNumber - 1; // Convert to 0-based
        final pdfPath = _actualFilePath ?? widget.filePath;
        
        // Get PDF page size for coordinate conversion (non-blocking with timeout)
        Size? pageSize;
        try {
          final file = File(pdfPath);
          if (!await file.exists().timeout(const Duration(seconds: 2))) {
            print('PDF file does not exist');
            return;
          }
          
          final bytes = await file.readAsBytes().timeout(const Duration(seconds: 5));
          final document = sf.PdfDocument(inputBytes: bytes);
          
          if (pageIndex < 0 || pageIndex >= document.pages.count) {
            document.dispose();
            print('Invalid page index: $pageIndex');
            return;
          }
          
          final page = document.pages[pageIndex];
          pageSize = Size(page.size.width, page.size.height);
          document.dispose();
        } catch (e) {
          print('Error getting page size: $e');
          return;
        }
        
        if (pageSize == null) {
          print('Failed to get page size');
          return;
        }
        
        // At this point, pageSize is guaranteed to be non-null
        final nonNullPageSize = pageSize!;
        
        // Convert normalized coordinates (0-1) to PDF coordinates (points)
        bool success = false;
        
        if (firstPoint.toolType == 'pen') {
          // Pen annotation - freehand path
          // Convert normalized coordinates (0-1, top-left origin) to PDF coordinates (points, bottom-left origin)
          final pdfPoints = path.map((p) {
            return Offset(
              p.normalizedPoint.dx * nonNullPageSize.width,
              nonNullPageSize.height - (p.normalizedPoint.dy * nonNullPageSize.height), // Invert Y-axis
            );
          }).toList();
          
          if (pdfPoints.length >= 2) {
            success = await MuPDFEditorService.addPenAnnotation(
              pdfPath,
              pageIndex,
              pdfPoints,
              firstPoint.color,
              firstPoint.strokeWidth,
            );
          }
        } else if (firstPoint.toolType == 'highlight') {
          // Highlight annotation - filled rectangle
          // Convert normalized coordinates (0-1, top-left origin) to PDF coordinates (points, bottom-left origin)
          final pdfPoints = path.map((p) {
            return Offset(
              p.normalizedPoint.dx * nonNullPageSize.width,
              nonNullPageSize.height - (p.normalizedPoint.dy * nonNullPageSize.height), // Invert Y-axis
            );
          }).toList();
          
          if (pdfPoints.length >= 2) {
            final minX = pdfPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
            final maxX = pdfPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
            final minY = pdfPoints.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
            final maxY = pdfPoints.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
            
            // PDF rectangle: (x, y, width, height) where (x,y) is bottom-left corner
            // After Y inversion: minY is the bottom Y, maxY is the top Y
            // So: x = minX, y = minY (bottom), width = maxX - minX, height = maxY - minY
            // The service expects rect.left, rect.top, rect.width, rect.height
            // But PDF needs bottom-left, so we pass: left=minX, top=minY (which is bottom in PDF), width, height
            final rect = Rect.fromLTWH(minX, minY, maxX - minX, maxY - minY);
            success = await MuPDFEditorService.addHighlightAnnotation(
              pdfPath,
              pageIndex,
              rect,
              firstPoint.color,
              0.4, // Default highlight opacity
            );
          }
        } else if (firstPoint.toolType == 'underline') {
          // Underline annotation - line
          // Convert normalized coordinates (0-1, top-left origin) to PDF coordinates (points, bottom-left origin)
          final pdfPoints = path.map((p) {
            return Offset(
              p.normalizedPoint.dx * nonNullPageSize.width,
              nonNullPageSize.height - (p.normalizedPoint.dy * nonNullPageSize.height), // Invert Y-axis
            );
          }).toList();
          
          if (pdfPoints.length >= 2) {
            final minX = pdfPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
            final maxX = pdfPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
            final y = pdfPoints.first.dy; // All points have same Y for underline
            
            success = await MuPDFEditorService.addUnderlineAnnotation(
              pdfPath,
              pageIndex,
              Offset(minX, y),
              Offset(maxX, y),
              firstPoint.color,
              firstPoint.strokeWidth,
            );
          }
        }
        
        // Skip saving if eraser tool (eraser doesn't add content, it removes overlay)
        if (firstPoint.isEraser) {
          // Eraser just removes from overlay, doesn't modify PDF
          if (mounted) {
            _annotationOverlayKey.currentState?.removeLastPath();
          }
          return;
        }
        
        // Save PDF and update UI only if successful
        if (success) {
          // Save PDF (with timeout to prevent hanging)
          try {
            await MuPDFEditorService.savePdf(pdfPath).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                print('PDF save timed out');
                return false;
              },
            );
          } catch (e) {
            print('Error saving PDF: $e');
            return;
          }
          
          // Update UI on main thread after save completes
          if (mounted) {
            // Remove the path from overlay immediately (annotation is saved)
            _annotationOverlayKey.currentState?.removeLastPath();
            
            // Reload PDF after a short delay to show changes (debounced to prevent hangs)
            _pdfReloadDebounceTimer?.cancel();
            _pdfReloadDebounceTimer = Timer(const Duration(milliseconds: 800), () {
              if (mounted) {
                // Reload PDF bytes after modification
                _loadPDFBytes().catchError((e) {
                  print('PDFViewer: Error reloading PDF bytes: $e');
                });
                setState(() {
                  _pdfReloadKey++; // Force PDF viewer to reload
                });
                print('PDF reloaded to show annotation changes');
              }
            });
          }
        } else {
          // Save failed - show error message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to save annotation. Please try again.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        print('Error saving annotation to PDF: $e');
      } finally {
        _isSavingAnnotation = false;
      }
    });
  }
  
  /// Handle tap on PDF to detect and select text (Sejda-style) using MuPDF
  ///
  /// IMPORTANT:
  /// - [screenPosition] is in the same coordinate space as the PDF viewer /
  ///   text-aware overlay (top-left origin, already includes zoom).
  /// - Coordinate conversion MUST match `_screenToPdf` in
  ///   `text_aware_annotation_overlay.dart` so taps, highlights, and
  ///   editing all hit the same text.
  Future<void> _handlePDFTextTap(Offset screenPosition, Size viewerSize) async {
    // Don't allow text editing on scanned documents
    if (_isScannedDocument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text editing is not available for scanned documents. This PDF contains only images.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      final file = File(_actualFilePath ?? widget.filePath);
      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (document.pages.count == 0) {
        document.dispose();
        return;
      }
      
      // Convert screen position to PDF coordinates
      // This logic is intentionally kept IDENTICAL to _screenToPdf() in
      // text_aware_annotation_overlay.dart so all tools agree.

      // Use PDF page size (all pages assumed same size for scaling)
      final firstPage = document.pages[0];
      final pageSize = firstPage.size;

      // Use viewerSize (actual PDF viewer widget size) for scaling
      // This matches the coordinate system of details.localPosition
      final screenSize = viewerSize;

      // Rendered PDF dimensions (scaled to fit viewer width)
      final pdfAspectRatio = pageSize.height / pageSize.width;
      final renderedPdfWidth = screenSize.width;
      final renderedPdfHeight = renderedPdfWidth * pdfAspectRatio;

      // 1) Absolute Y in document space (includes scroll)
      final absoluteDocumentY = screenPosition.dy + _pdfScrollOffset;

      // 2) Page index from absolute Y (continuous vertical layout)
      int tappedPageIndex = (absoluteDocumentY / renderedPdfHeight).floor();
      tappedPageIndex = tappedPageIndex.clamp(0, document.pages.count - 1);

      // 3) Y relative to that page
      final pageStartY = tappedPageIndex * renderedPdfHeight;
      final relativeYInPage = absoluteDocumentY - pageStartY;

      // 4) Convert to PDF page coordinates (points)
      // PDF uses bottom-left origin where Y=0 is at bottom, Y increases upward
      // MuPDF text coordinates are in this native system
      final pdfX = (screenPosition.dx / renderedPdfWidth) * pageSize.width;
      
      // Convert screen Y to PDF Y (both measured from bottom)
      // Screen: Y=0 at top, Y=renderedHeight at bottom
      // PDF: Y=0 at bottom, Y=pageHeight at top
      // Screen Y from top = relativeYInPage
      // Screen Y from bottom = renderedPdfHeight - relativeYInPage
      // PDF Y from bottom = (screen Y from bottom / renderedPdfHeight) * pageSize.height
      final screenYFromBottom = renderedPdfHeight - relativeYInPage;
      final pdfY = (screenYFromBottom / renderedPdfHeight) * pageSize.height;
      
      final pdfTapPoint = Offset(pdfX, pdfY);
      
      // DEBUG: Log coordinate conversion values
      print('PDFTextTap DEBUG: screenPosition=(${screenPosition.dx}, ${screenPosition.dy}), '
          'scrollOffset=$_pdfScrollOffset, '
          'absoluteDocumentY=$absoluteDocumentY, '
          'renderedPdfHeight=$renderedPdfHeight, '
          'tappedPageIndex=$tappedPageIndex, '
          'pageStartY=$pageStartY, '
          'relativeYInPage=$relativeYInPage, '
          'screenYFromBottom=$screenYFromBottom, '
          'pdfY=$pdfY, '
          'pageSize.height=${pageSize.height}, '
          'pdfTapPoint=($pdfX, $pdfY)');

      // Keep document alive while we use pageSize for tolerance calculations

      // Use MuPDF to get word quads at this position (same pipeline as highlight)
      final pdfPath = _actualFilePath ?? widget.filePath;
      final wordQuad = await _hitTestWordQuadAt(
        pdfPath: pdfPath,
        pageIndex: tappedPageIndex,
        pdfTapPoint: pdfTapPoint,
        pageSize: Size(pageSize.width, pageSize.height),
        renderedPdfWidth: renderedPdfWidth,
        renderedPdfHeight: renderedPdfHeight,
      );

      document.dispose();

      if (wordQuad == null || wordQuad.text == null || wordQuad.text!.isEmpty) {
        // No word found at this position
        print('PDFTextTap: No word found at position ($screenPosition)');
        
        // In explicit text-edit mode, tapping empty space adds new text.
        if (_selectedMode == 'text' || _isTextEditMode) {
          setState(() {
            _selectedPDFText = null;
            _selectedPDFTextObjectId = null;
            _showTextFormattingToolbar = false;
          });

          _showTextEditDialog(
            initialText: '',
            position: screenPosition,
            isEditing: false,
          );
          return;
        }
        return;
      }
      
      // Validate that we have an objectId (required for text replacement)
      if (wordQuad.objectId == null || wordQuad.objectId!.isEmpty) {
        print('PDFTextTap: Warning - Text found but no objectId available. Text editing may not work correctly.');
        // Still show toolbar but warn user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Text found but editing may be limited. Try using full document editing instead.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }

      print('PDFTextTap: Found word "${wordQuad.text}" at page ${wordQuad.pageIndex}');

      // If highlight or underline tool is selected, we rely on the overlay-based
      // drag selection to create annotations. Tapping on text is reserved for
      // inline text editing only.

      // Text and objectId come directly from the MuPDF quad extraction.
      // This is the SINGLE source of truth for selection; no second lookup.
      final bounds = wordQuad.bounds;

      setState(() {
        // Automatically enable text mode when text is found (even if text tool wasn't selected)
        _selectedMode = 'text';
        _isTextEditMode = true;
        _isEditingMode = true;
        
        _selectedPDFText = SelectedPDFText(
          text: wordQuad.text!,
          bounds: bounds,
          pageIndex: wordQuad.pageIndex,
          position: bounds.topLeft,
          // Use sensible defaults for formatting; actual formatting updates
          // come from the toolbar and are applied via replaceText.
          fontSize: 12.0,
          color: Colors.black,
          fontFamily: null,
          isBold: false,
          isItalic: false,
        );
        // Store MuPDF objectId for later replacement
        _selectedPDFTextObjectId = wordQuad.objectId;
        // Position toolbar above the selected text (Sejda-style: near but not blocking)
        final screenSize = MediaQuery.of(context).size;
        _textSelectionToolbarPosition = Offset(
          (screenPosition.dx - 150).clamp(16.0, screenSize.width - 320), // Keep toolbar on screen
          (screenPosition.dy - 100).clamp(16.0, screenSize.height - 200), // Above tap, but visible
        );
        _showTextFormattingToolbar = true;
        // Show visual feedback (Sejda-style: brief highlight)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.edit, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Text selected - Edit inline in toolbar'),
              ],
            ),
            backgroundColor: const Color(0xFF2196F3),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
          ),
        );
      });
    } catch (e) {
      print('Error handling PDF text tap: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error detecting text: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Shared word hit-test using MuPDF text quads (same pipeline as highlight)
  ///
  /// - [pdfTapPoint] is in PDF coordinates (page space, bottom-left origin).
  /// - Returns the TextQuad whose bounds contain the tap, with a small
  ///   tolerance equivalent to ~4 screen pixels.
  Future<TextQuad?> _hitTestWordQuadAt({
    required String pdfPath,
    required int pageIndex,
    required Offset pdfTapPoint,
    required Size pageSize,
    required double renderedPdfWidth,
    required double renderedPdfHeight,
  }) async {
    try {
      // Convert screen pixels into PDF units so we can build a selection
      // rectangle around the tap point. MuPDF's quad extractor returns quads
      // that intersect the selection rect, so a zero-area rect (start == end)
      // often produces 0 quads.
      // Use a more generous tolerance (15 screen pixels) to improve text selection
      // accuracy, especially for small text or when coordinates are slightly off.
      final pdfPixelsPerScreenX = pageSize.width / renderedPdfWidth;
      final pdfPixelsPerScreenY = pageSize.height / renderedPdfHeight;
      final tolerancePdfX = 15.0 * pdfPixelsPerScreenX;
      final tolerancePdfY = 15.0 * pdfPixelsPerScreenY;
      // Use the larger tolerance to ensure we catch nearby words
      final tolerance = math.max(tolerancePdfX, tolerancePdfY);
      // Ensure minimum tolerance of at least 10 PDF units for very small text
      final minTolerance = 10.0;
      final finalTolerance = math.max(tolerance, minTolerance);

      final start = Offset(
        pdfTapPoint.dx - finalTolerance,
        pdfTapPoint.dy - finalTolerance,
      );
      final end = Offset(
        pdfTapPoint.dx + finalTolerance,
        pdfTapPoint.dy + finalTolerance,
      );

      final jsonString = await MuPDFEditorService.getTextQuadsForSelection(
        pdfPath,
        pageIndex,
        start,
        end,
      );

      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }

      final quadsJson = jsonDecode(jsonString) as List;
      if (quadsJson.isEmpty) {
        return null;
      }

      final quads = quadsJson
          .map((q) => TextQuad.fromJson(q as Map<String, dynamic>))
          .toList();

      print('_hitTestWordQuadAt: Found ${quads.length} quads for tap at PDF ($pdfTapPoint)');
      
      if (quads.isEmpty) {
        print('_hitTestWordQuadAt: No quads found, returning null');
        return null;
      }

      // Find the best quad: prefer quads that contain the tap point,
      // and among those, pick the closest one
      TextQuad? bestContaining;
      double minContainingDistance = double.infinity;
      
      // Use a more generous expansion for checking containment
      // This helps when coordinates are slightly off due to rounding or scaling
      final expandedTolerance = finalTolerance * 1.5;

      for (final quad in quads) {
        final expanded = quad.bounds.inflate(expandedTolerance);
        if (expanded.contains(pdfTapPoint)) {
          final distance = (quad.bounds.center - pdfTapPoint).distance;
          if (bestContaining == null || distance < minContainingDistance) {
            bestContaining = quad;
            minContainingDistance = distance;
          }
        }
      }

      // If we found a quad containing the point, use it
      if (bestContaining != null) {
        print('_hitTestWordQuadAt: Selected containing quad "${bestContaining.text}"');
        return bestContaining;
      }

      // Fallback: use nearest quad by center distance, but only if within reasonable range
      // This prevents selecting text that's too far from the tap point
      // Use a more adaptive distance: max of 10% page width or 3x tolerance
      final maxDistance = math.max(pageSize.width * 0.1, finalTolerance * 3.0);
      TextQuad? nearest;
      double minDistance = double.infinity;
      
      for (final quad in quads) {
        final distance = (quad.bounds.center - pdfTapPoint).distance;
        if (distance < maxDistance && distance < minDistance) {
          nearest = quad;
          minDistance = distance;
        }
      }
      
      if (nearest != null) {
        print('_hitTestWordQuadAt: Selected nearest quad "${nearest.text}" (distance: ${minDistance.toStringAsFixed(2)})');
        return nearest;
      }
      
      // Last resort: if no quad is within reasonable distance, return the absolute nearest
      if (quads.isNotEmpty) {
        final absoluteNearest = quads.reduce((a, b) {
          final da = (a.bounds.center - pdfTapPoint).distance;
          final db = (b.bounds.center - pdfTapPoint).distance;
          return da <= db ? a : b;
        });
        print('_hitTestWordQuadAt: Selected absolute nearest quad "${absoluteNearest.text}" (last resort)');
        return absoluteNearest;
      }
      
      return null;
    } catch (e) {
      print('Error in _hitTestWordQuadAt: $e');
      return null;
    }
  }
  
  // Debounce timer for text preview updates
  Timer? _textPreviewDebounceTimer;
  
  /// Update text content preview (UI only - doesn't save to PDF)
  /// Text is only saved when user clicks "Done"
  /// Optimized with debouncing to reduce setState calls
  void _updateTextContentPreview(String newText) {
    if (_selectedPDFText == null) return;
    
    // Cancel previous debounce timer
    _textPreviewDebounceTimer?.cancel();
    
    // Debounce UI updates to reduce setState calls (improves performance)
    _textPreviewDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted && _selectedPDFText != null) {
        setState(() {
          _selectedPDFText = _selectedPDFText!.copyWith(text: newText);
        });
      }
    });
  }
  
  // Loading state for text save operation
  bool _isSavingText = false;
  
  /// Save text content to PDF (called when user clicks "Done")
  /// Optimized with immediate UI feedback and async save
  Future<void> _saveTextContent() async {
    if (_selectedPDFText == null) return;
    if (_isSavingText) return; // Prevent multiple simultaneous saves
    
    // Cancel any pending preview updates
    _textPreviewDebounceTimer?.cancel();
    
    // Show loading indicator immediately
    setState(() {
      _isSavingText = true;
    });
    
    try {
      // Save the current text to PDF (non-blocking)
      await _saveTextChangeToPDF(_selectedPDFText!.text);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingText = false;
        });
      }
    }
  }

  Future<bool> _tryReplaceTextWithMuPdf(String newText) async {
    if (_selectedPDFText == null ||
        _selectedPDFTextObjectId == null ||
        _selectedPDFTextObjectId!.isEmpty) {
      return false;
    }

    try {
      final pdfPath = _actualFilePath ?? widget.filePath;
      final file = File(pdfPath);
      if (!await file.exists()) {
        return false;
      }

      final beforeBytes = await file.readAsBytes();
      final replaceSuccess = await MuPDFEditorService.replaceText(
        pdfPath,
        _selectedPDFText!.pageIndex,
        _selectedPDFTextObjectId!,
        newText,
      );

      if (!replaceSuccess) {
        return false;
      }

      await MuPDFEditorService.savePdf(pdfPath);
      final afterBytes = await file.readAsBytes();
      final fileChanged = !listEquals(beforeBytes, afterBytes);

      if (!fileChanged) {
        print('_tryReplaceTextWithMuPdf: Native edit reported success but file did not change');
      }

      return fileChanged;
    } catch (e) {
      print('_tryReplaceTextWithMuPdf: $e');
      return false;
    }
  }
  
  /// Save text content change to PDF (background operation)
  /// Optimized with faster reload and better error handling
  Future<void> _saveTextChangeToPDF(String newText) async {
    if (_selectedPDFText == null) {
      print('_saveTextChangeToPDF: No text selected');
      return;
    }
    
    if (_selectedPDFTextObjectId == null || _selectedPDFTextObjectId!.isEmpty) {
      print('_saveTextChangeToPDF: No objectId available, using Syncfusion fallback');
      // Try Syncfusion fallback if no objectId
      final success = await _replaceTextWithSyncfusion(newText);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Text editing failed here. Try the full text editor to update the document while keeping its layout.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
      return;
    }
    
    try {
      final pageIndex = _selectedPDFText!.pageIndex;
      
      print('_saveTextChangeToPDF: Attempting to replace text with objectId: ${_selectedPDFTextObjectId}');

      bool success = false;
      if (_selectedPDFTextObjectId != null && _selectedPDFTextObjectId!.isNotEmpty) {
        success = await _tryReplaceTextWithMuPdf(newText);
      }

      if (!success) {
        print('_saveTextChangeToPDF: Using Syncfusion fallback for visible PDF text update');
        success = await _replaceTextWithSyncfusion(newText);
      }
      
      if (success) {
        // Optimized: Reload faster (reduced from 800ms to 200ms)
        // Also navigate to the edited page to show changes immediately
        if (mounted) {
          _pdfReloadDebounceTimer?.cancel();
          
          // Navigate to the edited page first (faster visual feedback)
          if (_pdfViewerController.pageNumber != pageIndex + 1) {
            _pdfViewerController.jumpToPage(pageIndex + 1);
          }
          
          // Reload PDF after minimal delay
          _pdfReloadDebounceTimer = Timer(const Duration(milliseconds: 200), () {
            if (mounted) {
              // Reload PDF bytes after modification
              _loadPDFBytes().catchError((e) {
                print('PDFViewer: Error reloading PDF bytes: $e');
              });
              setState(() {
                _pdfReloadKey++; // Force PDF viewer to reload
              });
              
              // Show success message (non-blocking)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Text updated'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update text. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('Error saving text change: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  /// Fallback: Replace text using Syncfusion (works but less precise)
  Future<bool> _replaceTextWithSyncfusion(String newText) async {
    try {
      if (_selectedPDFText == null) return false;

      final file = File(_actualFilePath ?? widget.filePath);
      final bytes = await file.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      if (_selectedPDFText!.pageIndex >= 0 && _selectedPDFText!.pageIndex < document.pages.count) {
        final page = document.pages[_selectedPDFText!.pageIndex];
        final graphics = page.graphics;
        final pageSize = page.size;
        
        // Draw white rectangle to "erase" old text before redrawing.
        final bounds = _selectedPDFText!.bounds;
        final lineCount = '\n'.allMatches(newText).length + 1;
        final fontSize = _selectedPDFText!.fontSize.clamp(8.0, 72.0);
        final redrawWidth = (pageSize.width - bounds.left - 16).clamp(
          bounds.width + 12,
          pageSize.width,
        );
        final redrawHeight = math.max(
          bounds.height + 12,
          (fontSize * 1.4 * lineCount) + 12,
        );
        final redrawBounds = Rect.fromLTWH(
          bounds.left,
          bounds.top,
          redrawWidth,
          redrawHeight,
        );

        graphics.drawRectangle(
          brush: sf.PdfSolidBrush(sf.PdfColor(255, 255, 255)),
          bounds: redrawBounds,
        );

        if (newText.trim().isEmpty) {
          final modifiedBytes = await document.save();
          await file.writeAsBytes(modifiedBytes);
          document.dispose();
          return true;
        }

        // Draw replacement text at the same position using current toolbar styling.
        sf.PdfFontFamily fontFamily = sf.PdfFontFamily.helvetica;
        final selectedFont = _selectedPDFText!.fontFamily?.toLowerCase();
        if (selectedFont != null) {
          if (selectedFont.contains('times')) {
            fontFamily = sf.PdfFontFamily.timesRoman;
          } else if (selectedFont.contains('courier')) {
            fontFamily = sf.PdfFontFamily.courier;
          }
        }

        final font = sf.PdfStandardFont(
          fontFamily,
          fontSize,
          style: _selectedPDFText!.isBold
              ? sf.PdfFontStyle.bold
              : (_selectedPDFText!.isItalic
                  ? sf.PdfFontStyle.italic
                  : sf.PdfFontStyle.regular),
        );
        final brush = sf.PdfSolidBrush(sf.PdfColor(
          _selectedPDFText!.color.red,
          _selectedPDFText!.color.green,
          _selectedPDFText!.color.blue,
        ));
        
        final stringFormat = sf.PdfStringFormat();
        stringFormat.alignment = sf.PdfTextAlignment.left;
        stringFormat.lineAlignment = sf.PdfVerticalAlignment.top;
        stringFormat.wordWrap = sf.PdfWordWrapType.word;
        
        graphics.drawString(
          newText,
          font,
          brush: brush,
          format: stringFormat,
          bounds: redrawBounds,
        );
        
        // Save PDF
        final modifiedBytes = await document.save();
        await file.writeAsBytes(modifiedBytes);
        document.dispose();
        
        return true;
      }
      document.dispose();
      return false;
    } catch (e) {
      print('Error in Syncfusion text replacement: $e');
      return false;
    }
  }
  
  /// Close text toolbar (without saving - used when user clicks Close)
  void _closeTextToolbar() {
    // Cancel any pending debounced reloads
    _pdfReloadDebounceTimer?.cancel();
    
    // Close toolbar immediately (don't reload PDF since no changes were saved)
    setState(() {
      _showTextFormattingToolbar = false;
      _selectedPDFText = null;
      _selectedPDFTextObjectId = null;
    });
  }
  
  /// Close text toolbar and reload PDF to show saved changes
  /// Optimized: Reload is already handled in _saveTextChangeToPDF
  void _closeTextToolbarAfterSave() {
    // Cancel any pending debounced reloads
    _pdfReloadDebounceTimer?.cancel();
    _textPreviewDebounceTimer?.cancel();
    
    // Close toolbar immediately (reload is handled by save operation)
    setState(() {
      _showTextFormattingToolbar = false;
      _selectedPDFText = null;
      _selectedPDFTextObjectId = null;
    });
    
    // Note: PDF reload is already scheduled in _saveTextChangeToPDF
    // No need to reload again here
  }
  
  // Debounce timer for formatting updates
  Timer? _formattingDebounceTimer;
  
  /// Apply text formatting to selected text using MuPDF (Sejda-style: immediate feedback)
  /// Optimized with debouncing to batch formatting changes
  Future<void> _applyTextFormatting({
    bool? isBold,
    bool? isItalic,
    String? fontFamily,
    double? fontSize,
    Color? color,
  }) async {
    if (_selectedPDFText == null || _selectedPDFTextObjectId == null) return;
    
    // Update UI immediately (Sejda-style immediate feedback)
    final updatedText = _selectedPDFText!.copyWith(
      isBold: isBold ?? _selectedPDFText!.isBold,
      isItalic: isItalic ?? _selectedPDFText!.isItalic,
      fontFamily: fontFamily ?? _selectedPDFText!.fontFamily,
      fontSize: fontSize ?? _selectedPDFText!.fontSize,
      color: color ?? _selectedPDFText!.color,
    );
    
    setState(() {
      _selectedPDFText = updatedText;
    });
    
    // Debounce formatting saves to batch multiple changes
    _formattingDebounceTimer?.cancel();
    _formattingDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      // Save to PDF in background (non-blocking, no loading dialog)
      _saveTextFormattingToPDF(updatedText);
    });
  }
  
  /// Save text formatting to PDF (background operation)
  Future<void> _saveTextFormattingToPDF(SelectedPDFText updatedText) async {
    if (_selectedPDFTextObjectId == null) return;
    
    try {
      final pdfPath = _actualFilePath ?? widget.filePath;
      // Note: Formatting changes require content stream editing which is complex
      // For now, we update the text with formatting applied
      // Full implementation would require parsing and modifying PDF content streams
      final success = await MuPDFEditorService.replaceText(
        pdfPath,
        updatedText.pageIndex,
        _selectedPDFTextObjectId!,
        updatedText.text,
      );
      
      if (success) {
        await MuPDFEditorService.savePdf(pdfPath);
        
        // Reload PDF after a short delay to show changes (debounced to prevent hangs)
        if (mounted) {
          _pdfReloadDebounceTimer?.cancel();
          _pdfReloadDebounceTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted) {
              // Reload PDF bytes after modification
              _loadPDFBytes().catchError((e) {
                print('PDFViewer: Error reloading PDF bytes: $e');
              });
              setState(() {
                _pdfReloadKey++; // Force PDF viewer to reload
              });
              print('PDF reloaded to show formatting changes');
            }
          });
        }
      }
    } catch (e) {
      print('Error saving text formatting: $e');
    }
  }
  
  /// Delete selected text using MuPDF
  Future<void> _deleteSelectedText() async {
    if (_selectedPDFText == null) return;
    
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      bool success = false;

      if (_selectedPDFTextObjectId != null && _selectedPDFTextObjectId!.isNotEmpty) {
        success = await _tryReplaceTextWithMuPdf('');
      }

      if (!success) {
        success = await _replaceTextWithSyncfusion('');
      }
      
      if (mounted) {
        Navigator.pop(context);
        
        if (success) {
          _pdfReloadDebounceTimer?.cancel();
          _pdfReloadDebounceTimer = Timer(const Duration(milliseconds: 200), () {
            if (mounted) {
              _loadPDFBytes().catchError((e) {
                print('PDFViewer: Error reloading PDF bytes: $e');
              });
              setState(() {
                _pdfReloadKey++;
              });
            }
          });

          setState(() {
            _selectedPDFText = null;
            _selectedPDFTextObjectId = null;
            _showTextFormattingToolbar = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Text deleted'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error deleting text. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting text: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                _selectedMode = 'none';
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
                // Add new text directly to PDF (true content editing)
                _addTextToPDF(newText, position);
              }
              
              // Reset text edit mode
              setState(() {
                _isTextEditMode = false;
                _selectedMode = 'none';
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

