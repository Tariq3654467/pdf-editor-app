package com.example.pdf_editor_app

import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Service for PDF editing using MuPDF native engine
 * 
 * This service bridges Flutter and native MuPDF implementation
 * All PDF editing operations are performed in native layer
 */
class PDFEditorService(private val methodChannel: MethodChannel) {
    
    private val pdfEditor = PDFEditorNative()
    private val TAG = "PDFEditorService"
    
    /**
     * Handle method calls from Flutter
     */
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadPdf" -> {
                val pdfPath = call.argument<String>("path")
                if (pdfPath != null) {
                    val success = pdfEditor.loadPdf(pdfPath)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "PDF path is null", null)
                }
            }
            
            "getTextAt" -> {
                val pdfPath = call.argument<String>("path")
                val pageIndex = call.argument<Int>("pageIndex") ?: 0
                val x = call.argument<Double>("x")?.toFloat() ?: 0f
                val y = call.argument<Double>("y")?.toFloat() ?: 0f
                
                if (pdfPath != null) {
                    try {
                        val textObject = pdfEditor.getTextAt(pdfPath, pageIndex, x, y)
                        if (textObject != null) {
                            result.success(mapOf(
                                "text" to textObject.text,
                                "fontName" to textObject.fontName,
                                "fontSize" to textObject.fontSize,
                                "x" to textObject.x,
                                "y" to textObject.y,
                                "width" to textObject.width,
                                "height" to textObject.height,
                                "objectId" to textObject.objectId,
                                "pageIndex" to textObject.pageIndex
                            ))
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting text at position: ${e.message}", e)
                        // Return null instead of crashing
                        result.success(null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "PDF path is null", null)
                }
            }
            
            "replaceText" -> {
                val pdfPath = call.argument<String>("path")
                val pageIndex = call.argument<Int>("pageIndex") ?: 0
                val objectId = call.argument<String>("objectId")
                val newText = call.argument<String>("newText")
                
                if (pdfPath != null && objectId != null && newText != null) {
                    val success = pdfEditor.replaceText(pdfPath, pageIndex, objectId, newText)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "Missing required arguments", null)
                }
            }
            
            "savePdf" -> {
                val pdfPath = call.argument<String>("path")
                if (pdfPath != null) {
                    val success = pdfEditor.savePdf(pdfPath)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "PDF path is null", null)
                }
            }
            
            "addPenAnnotation" -> {
                val pdfPath = call.argument<String>("path")
                val pageIndex = call.argument<Int>("pageIndex") ?: 0
                val pointsX = call.argument<List<Double>>("pointsX")?.map { it.toFloat() }?.toFloatArray()
                val pointsY = call.argument<List<Double>>("pointsY")?.map { it.toFloat() }?.toFloatArray()
                val colorR = call.argument<Int>("colorR") ?: 0
                val colorG = call.argument<Int>("colorG") ?: 0
                val colorB = call.argument<Int>("colorB") ?: 0
                val strokeWidth = call.argument<Double>("strokeWidth")?.toFloat() ?: 1.0f
                
                if (pdfPath != null && pointsX != null && pointsY != null && pointsX.size == pointsY.size) {
                    val success = pdfEditor.addPenAnnotation(
                        pdfPath, pageIndex, pointsX, pointsY,
                        colorR, colorG, colorB, strokeWidth
                    )
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "Missing or invalid arguments", null)
                }
            }
            
            "addHighlightAnnotation" -> {
                val pdfPath = call.argument<String>("path")
                val pageIndex = call.argument<Int>("pageIndex") ?: 0
                val x = call.argument<Double>("x")?.toFloat() ?: 0f
                val y = call.argument<Double>("y")?.toFloat() ?: 0f
                val width = call.argument<Double>("width")?.toFloat() ?: 0f
                val height = call.argument<Double>("height")?.toFloat() ?: 0f
                val colorR = call.argument<Int>("colorR") ?: 255
                val colorG = call.argument<Int>("colorG") ?: 255
                val colorB = call.argument<Int>("colorB") ?: 0
                val opacity = call.argument<Double>("opacity")?.toFloat() ?: 0.4f
                
                if (pdfPath != null) {
                    val success = pdfEditor.addHighlightAnnotation(
                        pdfPath, pageIndex, x, y, width, height,
                        colorR, colorG, colorB, opacity
                    )
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "PDF path is null", null)
                }
            }
            
            "addUnderlineAnnotation" -> {
                val pdfPath = call.argument<String>("path")
                val pageIndex = call.argument<Int>("pageIndex") ?: 0
                val x1 = call.argument<Double>("x1")?.toFloat() ?: 0f
                val y1 = call.argument<Double>("y1")?.toFloat() ?: 0f
                val x2 = call.argument<Double>("x2")?.toFloat() ?: 0f
                val y2 = call.argument<Double>("y2")?.toFloat() ?: 0f
                val colorR = call.argument<Int>("colorR") ?: 0
                val colorG = call.argument<Int>("colorG") ?: 0
                val colorB = call.argument<Int>("colorB") ?: 0
                val strokeWidth = call.argument<Double>("strokeWidth")?.toFloat() ?: 1.0f
                
                if (pdfPath != null) {
                    val success = pdfEditor.addUnderlineAnnotation(
                        pdfPath, pageIndex, x1, y1, x2, y2,
                        colorR, colorG, colorB, strokeWidth
                    )
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "PDF path is null", null)
                }
            }
            
            else -> {
                result.notImplemented()
            }
        }
    }
}

