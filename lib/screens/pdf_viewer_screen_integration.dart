// INTEGRATION GUIDE: How to integrate TextAwareAnnotationOverlay into PDFViewerScreen
//
// This file shows the key changes needed to integrate the new text-aware annotation system.
// Copy these changes into your pdf_viewer_screen.dart file.

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../widgets/text_aware_annotation_overlay.dart';
import '../models/pdf_annotation.dart';

// ============================================================================
// STEP 1: Add these imports to pdf_viewer_screen.dart
// ============================================================================
// import '../widgets/text_aware_annotation_overlay.dart';
// import '../models/pdf_annotation.dart';

// ============================================================================
// STEP 2: Add these state variables to _PDFViewerScreenState
// ============================================================================
/*
  // Text-aware annotation system
  Size? _pdfPageSize; // PDF page size in points
  double _zoomLevel = 1.0;
  List<PDFAnnotation> _savedAnnotations = [];
*/

// ============================================================================
// STEP 3: Update _onDocumentLoaded to capture page size
// ============================================================================
/*
  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    if (mounted) {
      setState(() {
        _totalPages = details.document.pages.count;
        _isLoading = false;
        
        // Get page size for annotation coordinate system
        if (details.document.pages.count > 0) {
          final firstPage = details.document.pages[0];
          _pdfPageSize = Size(firstPage.size.width, firstPage.size.height);
        }
      });
      
      // Load saved annotations
      _loadSavedAnnotations();
    }
  }
*/

// ============================================================================
// STEP 4: Add method to load saved annotations
// ============================================================================
/*
  Future<void> _loadSavedAnnotations() async {
    try {
      final storage = AnnotationStorageService();
      final annotations = await storage.loadAnnotations(_actualFilePath ?? widget.filePath);
      if (mounted) {
        setState(() {
          _savedAnnotations = annotations;
        });
      }
    } catch (e) {
      print('Error loading annotations: $e');
    }
  }
*/

// ============================================================================
// STEP 5: Replace PDFAnnotationOverlay with TextAwareAnnotationOverlay
// ============================================================================
/*
  // OLD CODE (around line 999):
  PDFAnnotationOverlay(
    key: _annotationOverlayKey,
    drawingColor: _getToolColor(),
    strokeWidth: _getStrokeWidth(),
    isDrawing: _isDrawingToolActive,
    isEraser: _selectedTool == 'eraser',
    toolType: _selectedTool,
    currentPage: _currentPage,
    scrollOffset: _pdfScrollOffset,
    pdfPath: _actualFilePath ?? widget.filePath,
    onAnnotationComplete: _saveAnnotationToPDF,
    child: NotificationListener<ScrollNotification>(
      // ... existing code
    ),
  ),

  // NEW CODE:
  TextAwareAnnotationOverlay(
    pdfPath: _actualFilePath ?? widget.filePath,
    currentPage: _currentPage - 1, // Convert to 0-based
    pageSize: _pdfPageSize ?? Size(612, 792), // Default US Letter if not loaded
    zoomLevel: _zoomLevel,
    scrollOffset: Offset(0, _pdfScrollOffset),
    selectedTool: _isEditingMode ? _selectedTool : null,
    toolColor: _selectedColor,
    strokeWidth: _strokeWidth,
    onAnnotationsChanged: (annotations) {
      setState(() {
        _savedAnnotations = annotations;
      });
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Track scroll for annotations
        if (notification is ScrollUpdateNotification) {
          setState(() {
            _pdfScrollOffset = notification.metrics.pixels;
          });
        }
        // ... rest of existing scroll handling
        return false;
      },
      child: _buildPDFViewer(),
    ),
  ),
*/

// ============================================================================
// STEP 6: Update zoom tracking (if you have zoom functionality)
// ============================================================================
/*
  // In your zoom handler:
  void _onZoomChanged(double zoom) {
    setState(() {
      _zoomLevel = zoom;
    });
  }
*/

// ============================================================================
// STEP 7: Remove old _saveAnnotationToPDF method (no longer needed)
// ============================================================================
/*
  // The new TextAwareAnnotationOverlay handles saving automatically
  // You can remove the old _saveAnnotationToPDF method
*/

