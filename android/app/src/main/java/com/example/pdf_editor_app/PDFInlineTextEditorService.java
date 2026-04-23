package com.example.pdf_editor_app;

import android.util.Log;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Flutter Method Channel service wrapper for PDFInlineTextEditor
 * 
 * This service bridges Flutter and the native Java PDF text editor
 */
public class PDFInlineTextEditorService {
    private static final String TAG = "PDFInlineTextEditorService";
    
    /**
     * Handle method calls from Flutter
     */
    public void handleMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "getTextAt": {
                    String pdfPath = call.argument("path");
                    Integer pageIndex = call.argument("pageIndex");
                    Double x = call.argument("x");
                    Double y = call.argument("y");
                    
                    if (pdfPath == null || pageIndex == null || x == null || y == null) {
                        result.error("INVALID_ARGUMENT", "Missing required arguments", null);
                        return;
                    }
                    
                    try {
                        PDFInlineTextEditor.TextObject textObject = PDFInlineTextEditor.getTextAt(
                            pdfPath, pageIndex, x.floatValue(), y.floatValue()
                        );
                        
                        if (textObject != null) {
                            result.success(textObject.toMap());
                        } else {
                            result.success(null);
                        }
                    } catch (NoClassDefFoundError e) {
                        Log.e(TAG, "AWT class not found - PDFBox initialization failed", e);
                        result.error("AWT_CLASS_NOT_FOUND", "PDFBox requires AWT classes: " + e.getMessage(), null);
                    } catch (Exception e) {
                        Log.e(TAG, "Error getting text at position", e);
                        result.error("ERROR", "Failed to get text: " + e.getMessage(), null);
                    }
                    break;
                }
                
                case "replaceText": {
                    String pdfPath = call.argument("path");
                    Integer pageIndex = call.argument("pageIndex");
                    String objectId = call.argument("objectId");
                    String newText = call.argument("newText");
                    Double x = call.argument("x"); // Optional: coordinates for fallback
                    Double y = call.argument("y"); // Optional: coordinates for fallback
                    
                    if (pdfPath == null || pageIndex == null || objectId == null || newText == null) {
                        result.error("INVALID_ARGUMENT", "Missing required arguments", null);
                        return;
                    }
                    
                    Log.d(TAG, String.format("replaceText called: objectId=%s, page=%d, newText='%s', x=%s, y=%s", 
                        objectId, pageIndex, newText, x != null ? String.valueOf(x) : "null", y != null ? String.valueOf(y) : "null"));
                    
                    // Try objectId-based replacement first
                    boolean success = PDFInlineTextEditor.replaceText(pdfPath, pageIndex, objectId, newText);
                    
                    // If that fails and coordinates are provided, try coordinate-based fallback
                    if (!success && x != null && y != null) {
                        Log.d(TAG, "ObjectId-based replacement failed, trying coordinate-based fallback");
                        success = PDFInlineTextEditor.replaceTextByCoordinates(
                            pdfPath, pageIndex, x.floatValue(), y.floatValue(), newText
                        );
                    }
                    
                    if (success) {
                        Log.d(TAG, "✓ Text replacement successful! Returning true to Flutter");
                    } else {
                        Log.w(TAG, "✗ Text replacement failed for objectId: " + objectId);
                    }
                    
                    result.success(success);
                    break;
                }
                
                case "addText": {
                    String pdfPath = call.argument("path");
                    Integer pageIndex = call.argument("pageIndex");
                    String text = call.argument("text");
                    Double x = call.argument("x");
                    Double y = call.argument("y");
                    Double fontSize = call.argument("fontSize");
                    String fontName = call.argument("fontName");
                    Integer colorR = call.argument("colorR");
                    Integer colorG = call.argument("colorG");
                    Integer colorB = call.argument("colorB");
                    
                    if (pdfPath == null || pageIndex == null || text == null || 
                        x == null || y == null) {
                        result.error("INVALID_ARGUMENT", "Missing required arguments", null);
                        return;
                    }
                    
                    float fontSizeValue = fontSize != null ? fontSize.floatValue() : 12.0f;
                    String fontNameValue = fontName != null ? fontName : "Helvetica";
                    int colorRValue = colorR != null ? colorR : 0;
                    int colorGValue = colorG != null ? colorG : 0;
                    int colorBValue = colorB != null ? colorB : 0;
                    
                    boolean success = PDFInlineTextEditor.addText(
                        pdfPath, pageIndex, text,
                        x.floatValue(), y.floatValue(),
                        fontSizeValue, fontNameValue,
                        colorRValue, colorGValue, colorBValue
                    );
                    result.success(success);
                    break;
                }
                
                case "getAllTextObjects": {
                    String pdfPath = call.argument("path");
                    Integer pageIndex = call.argument("pageIndex");
                    
                    if (pdfPath == null || pageIndex == null) {
                        result.error("INVALID_ARGUMENT", "Missing required arguments", null);
                        return;
                    }
                    
                    List<PDFInlineTextEditor.TextObject> textObjects = 
                        PDFInlineTextEditor.getAllTextObjects(pdfPath, pageIndex);
                    
                    List<Map<String, Object>> resultList = new ArrayList<>();
                    for (PDFInlineTextEditor.TextObject obj : textObjects) {
                        resultList.add(obj.toMap());
                    }
                    
                    result.success(resultList);
                    break;
                }
                
                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception e) {
            Log.e(TAG, "Error handling method call: " + call.method, e);
            result.error("ERROR", e.getMessage(), null);
        }
    }
}

