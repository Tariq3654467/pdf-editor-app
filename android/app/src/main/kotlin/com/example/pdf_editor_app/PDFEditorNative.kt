package com.example.pdf_editor_app

import android.util.Log

/**
 * Native PDF editing interface using MuPDF
 * 
 * This class provides JNI methods for:
 * - Loading PDF documents
 * - Detecting text objects at positions
 * - Replacing text in PDF content streams
 * - Saving edited PDFs
 */
class PDFEditorNative {
    
    companion object {
        private const val TAG = "PDFEditorNative"
        
        init {
            try {
                System.loadLibrary("pdf_editor_native")
                Log.d(TAG, "Native library loaded successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load native library", e)
            }
        }
    }
    
    /**
     * Data class representing a text object in PDF
     */
    data class PDFTextObject(
        val text: String,
        val fontName: String,
        val fontSize: Float,
        val x: Float,
        val y: Float,
        val width: Float,
        val height: Float,
        val objectId: String,
        val pageIndex: Int
    )
    
    /**
     * Load PDF document
     * @param pdfPath Path to PDF file
     * @return true if loaded successfully
     */
    external fun loadPdf(pdfPath: String): Boolean
    
    /**
     * Get text object at specific position
     * @param pdfPath Path to PDF file
     * @param pageIndex Page number (0-based)
     * @param x X coordinate in PDF space
     * @param y Y coordinate in PDF space
     * @return PDFTextObject or null if not found
     */
    external fun getTextAt(pdfPath: String, pageIndex: Int, x: Float, y: Float): PDFTextObject?
    
    /**
     * Replace text in PDF content stream
     * @param pdfPath Path to PDF file
     * @param pageIndex Page number (0-based)
     * @param objectId PDF object identifier
     * @param newText New text content
     * @return true if successful
     */
    external fun replaceText(pdfPath: String, pageIndex: Int, objectId: String, newText: String): Boolean
    
    /**
     * Save PDF after editing
     * @param pdfPath Path to PDF file
     * @return true if successful
     */
    external fun savePdf(pdfPath: String): Boolean
    
    /**
     * Add pen annotation (freehand path) to PDF
     * @param pdfPath Path to PDF file
     * @param pageIndex Page number (0-based)
     * @param pointsX Array of X coordinates in PDF space
     * @param pointsY Array of Y coordinates in PDF space
     * @param colorR Red component (0-255)
     * @param colorG Green component (0-255)
     * @param colorB Blue component (0-255)
     * @param strokeWidth Stroke width in points
     * @return true if successful
     */
    external fun addPenAnnotation(
        pdfPath: String,
        pageIndex: Int,
        pointsX: FloatArray,
        pointsY: FloatArray,
        colorR: Int,
        colorG: Int,
        colorB: Int,
        strokeWidth: Float
    ): Boolean
    
    /**
     * Add highlight annotation (filled rectangle) to PDF
     * @param pdfPath Path to PDF file
     * @param pageIndex Page number (0-based)
     * @param x X coordinate of rectangle start
     * @param y Y coordinate of rectangle start
     * @param width Width of rectangle
     * @param height Height of rectangle
     * @param colorR Red component (0-255)
     * @param colorG Green component (0-255)
     * @param colorB Blue component (0-255)
     * @param opacity Opacity (0.0-1.0)
     * @return true if successful
     */
    external fun addHighlightAnnotation(
        pdfPath: String,
        pageIndex: Int,
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        colorR: Int,
        colorG: Int,
        colorB: Int,
        opacity: Float
    ): Boolean
    
    /**
     * Add underline annotation (line) to PDF
     * @param pdfPath Path to PDF file
     * @param pageIndex Page number (0-based)
     * @param x1 X coordinate of line start
     * @param y1 Y coordinate of line start
     * @param x2 X coordinate of line end
     * @param y2 Y coordinate of line end
     * @param colorR Red component (0-255)
     * @param colorG Green component (0-255)
     * @param colorB Blue component (0-255)
     * @param strokeWidth Stroke width in points
     * @return true if successful
     */
    external fun addUnderlineAnnotation(
        pdfPath: String,
        pageIndex: Int,
        x1: Float,
        y1: Float,
        x2: Float,
        y2: Float,
        colorR: Int,
        colorG: Int,
        colorB: Int,
        strokeWidth: Float
    ): Boolean
    
    /**
     * Get text quads (bounding boxes) for text selection range
     * @param pdfPath Path to PDF file
     * @param pageIndex Page number (0-based)
     * @param startX Start X coordinate in PDF space
     * @param startY Start Y coordinate in PDF space
     * @param endX End X coordinate in PDF space
     * @param endY End Y coordinate in PDF space
     * @return JSON string containing array of quads
     */
    external fun getTextQuadsForSelection(
        pdfPath: String,
        pageIndex: Int,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float
    ): String
}

