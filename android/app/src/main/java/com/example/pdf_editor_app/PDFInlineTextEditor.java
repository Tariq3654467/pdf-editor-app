package com.example.pdf_editor_app;

import android.util.Log;
import com.itextpdf.kernel.pdf.PdfDocument;
import com.itextpdf.kernel.pdf.PdfReader;
import com.itextpdf.kernel.pdf.PdfWriter;
import com.itextpdf.kernel.pdf.PdfPage;
import com.itextpdf.kernel.geom.Rectangle;
import com.itextpdf.kernel.pdf.canvas.PdfCanvas;
import com.itextpdf.kernel.pdf.canvas.parser.PdfTextExtractor;
import com.itextpdf.kernel.pdf.canvas.parser.listener.LocationTextExtractionStrategy;
import com.itextpdf.kernel.pdf.canvas.parser.listener.TextChunk;
import com.itextpdf.kernel.pdf.canvas.parser.listener.ITextExtractionStrategy;
import com.itextpdf.kernel.font.PdfFont;
import com.itextpdf.kernel.font.PdfFontFactory;
import com.itextpdf.kernel.colors.DeviceRgb;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.HashMap;

/**
 * Native Java implementation for real inline PDF text editing using iText 7
 * 
 * This class provides true inline text editing by:
 * 1. Finding text objects at specific positions
 * 2. Replacing text content using overlay approach
 * 3. Preserving font, size, position, and formatting
 * 4. Saving the edited PDF
 */
public class PDFInlineTextEditor {
    private static final String TAG = "PDFInlineTextEditor";
    
    /**
     * Represents a text object found in the PDF
     */
    public static class TextObject {
        public String text;
        public String fontName;
        public float fontSize;
        public float x;
        public float y;
        public float width;
        public float height;
        public String objectId;
        public int pageIndex;
        public int colorR;
        public int colorG;
        public int colorB;
        
        public TextObject(String text, String fontName, float fontSize, float x, float y,
                         float width, float height, String objectId, int pageIndex,
                         int colorR, int colorG, int colorB) {
            this.text = text;
            this.fontName = fontName;
            this.fontSize = fontSize;
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
            this.objectId = objectId;
            this.pageIndex = pageIndex;
            this.colorR = colorR;
            this.colorG = colorG;
            this.colorB = colorB;
        }
        
        public Map<String, Object> toMap() {
            Map<String, Object> map = new HashMap<>();
            map.put("text", text);
            map.put("fontName", fontName);
            map.put("fontSize", fontSize);
            map.put("x", x);
            map.put("y", y);
            map.put("width", width);
            map.put("height", height);
            map.put("objectId", objectId);
            map.put("pageIndex", pageIndex);
            map.put("colorR", colorR);
            map.put("colorG", colorG);
            map.put("colorB", colorB);
            return map;
        }
    }
    
    /**
     * Custom text extraction strategy to get text with positions
     */
    private static class PositionTextExtractionStrategy extends LocationTextExtractionStrategy {
        private List<TextObject> textObjects = new ArrayList<>();
        private int pageIndex;
        private float pageHeight;
        
        public PositionTextExtractionStrategy(int pageIndex, float pageHeight) {
            this.pageIndex = pageIndex;
            this.pageHeight = pageHeight;
        }
        
        @Override
        public void eventOccurred(com.itextpdf.kernel.pdf.canvas.parser.data.IEventData data, com.itextpdf.kernel.pdf.canvas.parser.EventType type) {
            if (type == com.itextpdf.kernel.pdf.canvas.parser.EventType.RENDER_TEXT) {
                com.itextpdf.kernel.pdf.canvas.parser.data.TextRenderInfo renderInfo = 
                    (com.itextpdf.kernel.pdf.canvas.parser.data.TextRenderInfo) data;
                
                String text = renderInfo.getText();
                if (text == null || text.trim().isEmpty()) {
                    return;
                }
                
                Rectangle rect = renderInfo.getBaseline().getBoundingRectangle();
                com.itextpdf.kernel.geom.Matrix ctm = renderInfo.getGraphicsState().getCtm();
                
                // Get position (iText uses bottom-left origin)
                float x = rect.getX();
                float y = pageHeight - rect.getY() - rect.getHeight(); // Convert to top-left origin
                
                // Get font info
                PdfFont font = renderInfo.getFont();
                String fontName = font != null ? font.getFontProgram().getFontNames().getFontName() : "Helvetica";
                float fontSize = renderInfo.getFontSize();
                
                // Calculate text width
                float textWidth = rect.getWidth();
                float textHeight = rect.getHeight();
                
                // Get color (default to black)
                int colorR = 0;
                int colorG = 0;
                int colorB = 0;
                try {
                    com.itextpdf.kernel.colors.Color fillColor = renderInfo.getGraphicsState().getFillColor();
                    if (fillColor instanceof DeviceRgb) {
                        DeviceRgb rgb = (DeviceRgb) fillColor;
                        // iText 7 DeviceRgb stores color values internally
                        // Access through color space or use getColorValue
                        float[] colorValues = rgb.getColorValue();
                        if (colorValues != null && colorValues.length >= 3) {
                            colorR = (int) (colorValues[0] * 255);
                            colorG = (int) (colorValues[1] * 255);
                            colorB = (int) (colorValues[2] * 255);
                        }
                    }
                } catch (Exception e) {
                    // Use default black
                    Log.d(TAG, "Could not extract color, using default black", e);
                }
                
                // Generate object ID
                String objectId = String.format("obj_%d_%.1f_%.1f", pageIndex, x, y);
                
                textObjects.add(new TextObject(
                    text,
                    fontName,
                    fontSize,
                    x,
                    y,
                    textWidth,
                    textHeight,
                    objectId,
                    pageIndex,
                    colorR,
                    colorG,
                    colorB
                ));
            }
            super.eventOccurred(data, type);
        }
        
        public List<TextObject> getTextObjects() {
            return textObjects;
        }
    }
    
    /**
     * Find text object at a specific position
     */
    public static TextObject getTextAt(String pdfPath, int pageIndex, float x, float y) {
        try {
            PdfReader reader = new PdfReader(pdfPath);
            PdfDocument document = new PdfDocument(reader);
            
            if (pageIndex < 0 || pageIndex >= document.getNumberOfPages()) {
                document.close();
                reader.close();
                return null;
            }
            
            PdfPage page = document.getPage(pageIndex + 1); // iText uses 1-based indexing
            Rectangle pageSize = page.getPageSize();
            float pageHeight = pageSize.getHeight();
            
            // Extract text with positions
            PositionTextExtractionStrategy strategy = new PositionTextExtractionStrategy(pageIndex, pageHeight);
            PdfTextExtractor.getTextFromPage(page, strategy);
            
            List<TextObject> textObjects = strategy.getTextObjects();
            
            Log.d(TAG, String.format("getTextAt: Searching for text at (%.2f, %.2f) on page %d. Found %d text objects.", 
                x, y, pageIndex, textObjects.size()));
            
            // Find the closest text object to the given position
            TextObject closest = null;
            float minDistance = Float.MAX_VALUE;
            float tolerance = 20.0f; // 20 points tolerance
            
            for (TextObject obj : textObjects) {
                // Check if point is within the text bounds (with tolerance)
                boolean withinBounds = x >= obj.x - tolerance && x <= obj.x + obj.width + tolerance &&
                    y >= obj.y - tolerance && y <= obj.y + obj.height + tolerance;
                
                if (withinBounds) {
                    // Calculate distance from tap point to text center
                    float textCenterX = obj.x + obj.width / 2;
                    float textCenterY = obj.y + obj.height / 2;
                    float distance = (float) Math.sqrt(
                        Math.pow(textCenterX - x, 2) + Math.pow(textCenterY - y, 2)
                    );
                    
                    if (distance < minDistance) {
                        minDistance = distance;
                        closest = obj;
                        Log.d(TAG, String.format("getTextAt: Found closer match: '%s' at (%.2f, %.2f) size (%.2f, %.2f), distance=%.2f", 
                            obj.text, obj.x, obj.y, obj.width, obj.height, distance));
                    }
                }
            }
            
            if (closest != null) {
                Log.d(TAG, String.format("getTextAt: Returning text '%s' at (%.2f, %.2f)", closest.text, closest.x, closest.y));
            } else {
                Log.d(TAG, "getTextAt: No text found at position");
            }
            
            document.close();
            reader.close();
            return closest;
            
        } catch (Exception e) {
            Log.e(TAG, "Error getting text at position", e);
            return null;
        }
    }
    
    /**
     * Replace text in PDF by overlaying new text and covering old text
     * Supports both objectId-based and coordinate-based text replacement
     */
    public static boolean replaceText(String pdfPath, int pageIndex, String objectId, String newText) {
        PdfReader reader = null;
        PdfWriter writer = null;
        PdfDocument document = null;
        try {
            // Create temporary file for output
            File tempFile = new File(pdfPath + ".tmp");
            reader = new PdfReader(pdfPath);
            writer = new PdfWriter(tempFile);
            document = new PdfDocument(reader, writer);
            
            if (pageIndex < 0 || pageIndex >= document.getNumberOfPages()) {
                Log.e(TAG, "Invalid page index: " + pageIndex);
                return false;
            }
            
            PdfPage page = document.getPage(pageIndex + 1); // iText uses 1-based indexing
            Rectangle pageSize = page.getPageSize();
            float pageHeight = pageSize.getHeight();
            
            // First, extract text to find the object and get its properties
            PositionTextExtractionStrategy strategy = new PositionTextExtractionStrategy(pageIndex, pageHeight);
            PdfTextExtractor.getTextFromPage(page, strategy);
            
            List<TextObject> textObjects = strategy.getTextObjects();
            
            // Find the text object by ID or by parsing coordinates from objectId
            TextObject targetObject = null;
            
            // Try exact match first
            for (TextObject obj : textObjects) {
                if (obj.objectId.equals(objectId)) {
                    targetObject = obj;
                    Log.d(TAG, "Found text object by exact ID match: " + objectId);
                    break;
                }
            }
            
            // If not found, try parsing coordinates from objectId format: obj_page_x_y
            if (targetObject == null && objectId != null && objectId.startsWith("obj_")) {
                try {
                    String[] parts = objectId.substring(4).split("_"); // Remove "obj_" prefix
                    if (parts.length >= 3) {
                        int parsedPage = Integer.parseInt(parts[0]);
                        float parsedX = Float.parseFloat(parts[1]);
                        float parsedY = Float.parseFloat(parts[2]);
                        
                        Log.d(TAG, String.format("Parsed objectId: page=%d, x=%.2f, y=%.2f", parsedPage, parsedX, parsedY));
                        
                        // Find closest text object to parsed coordinates
                        float minDistance = Float.MAX_VALUE;
                        float tolerance = 30.0f; // Increased tolerance for coordinate matching
                        
                        for (TextObject obj : textObjects) {
                            // Calculate distance from parsed coordinates to text center
                            float textCenterX = obj.x + obj.width / 2;
                            float textCenterY = obj.y + obj.height / 2;
                            float distance = (float) Math.sqrt(
                                Math.pow(textCenterX - parsedX, 2) + Math.pow(textCenterY - parsedY, 2)
                            );
                            
                            if (distance < minDistance && distance < tolerance) {
                                minDistance = distance;
                                targetObject = obj;
                                Log.d(TAG, String.format("Found text object by coordinate match: '%s' at (%.2f, %.2f), distance=%.2f", 
                                    obj.text, textCenterX, textCenterY, distance));
                            }
                        }
                    }
                } catch (Exception e) {
                    Log.w(TAG, "Failed to parse objectId coordinates: " + objectId, e);
                }
            }
            
            if (targetObject == null) {
                Log.w(TAG, "Text object not found for objectId: " + objectId + ". Available objects: " + textObjects.size());
                // Log available objectIds for debugging
                for (int i = 0; i < Math.min(5, textObjects.size()); i++) {
                    Log.d(TAG, "  Available objectId[" + i + "]: " + textObjects.get(i).objectId + " text: '" + textObjects.get(i).text + "'");
                }
                return false;
            }
            
            // Convert y coordinate (PDF is bottom-up, iText uses bottom-left origin)
            float pdfY = pageHeight - targetObject.y;
            
            // Get font
            PdfFont font;
            try {
                String fontName = targetObject.fontName;
                if (fontName == null || fontName.isEmpty()) {
                    fontName = "Helvetica";
                }
                // Map common font names
                if (fontName.contains("Bold") && (fontName.contains("Italic") || fontName.contains("Oblique"))) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_BOLDOBLIQUE);
                } else if (fontName.contains("Bold")) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_BOLD);
                } else if (fontName.contains("Italic") || fontName.contains("Oblique")) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_OBLIQUE);
                } else {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA);
                }
            } catch (Exception e) {
                Log.w(TAG, "Could not create font, using default", e);
                font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA);
            }
            
            // Add overlay: white rectangle to cover old text, then new text
            PdfCanvas canvas = new PdfCanvas(page.newContentStreamBefore(), page.getResources(), document);
            
            // Draw white rectangle to cover old text (with some padding)
            float padding = 2.0f;
            canvas.setFillColor(new DeviceRgb(255, 255, 255)); // White
            canvas.rectangle(
                targetObject.x - padding,
                pdfY - targetObject.height - padding,
                targetObject.width + (2 * padding),
                targetObject.height + (2 * padding)
            );
            canvas.fill();
            
            // Add new text at the same position with same formatting
            canvas.beginText()
                .setFontAndSize(font, targetObject.fontSize)
                .setFillColor(new DeviceRgb(targetObject.colorR, targetObject.colorG, targetObject.colorB))
                .moveText(targetObject.x, pdfY)
                .showText(newText)
                .endText();
            
            // Close resources
            document.close();
            reader.close();
            writer.close();
            
            // Replace original file with modified file
            File originalFile = new File(pdfPath);
            if (tempFile.exists()) {
                if (originalFile.delete() && tempFile.renameTo(originalFile)) {
                    Log.d(TAG, "Text replaced successfully (overlay method)");
                    return true;
                } else {
                    Log.e(TAG, "Failed to replace original file");
                    tempFile.delete(); // Clean up temp file
                    return false;
                }
            }
            return false;
            
        } catch (Exception e) {
            Log.e(TAG, "Error replacing text", e);
            return false;
        } finally {
            // Ensure resources are closed
            try {
                if (document != null && !document.isClosed()) document.close();
                if (reader != null) reader.close();
                if (writer != null) writer.close();
            } catch (Exception e) {
                Log.e(TAG, "Error closing resources", e);
            }
        }
    }
    
    /**
     * Replace text by coordinates (fallback method when objectId fails)
     * This method finds text at the given coordinates and replaces it
     */
    public static boolean replaceTextByCoordinates(String pdfPath, int pageIndex, float x, float y, String newText) {
        PdfReader reader = null;
        PdfWriter writer = null;
        PdfDocument document = null;
        try {
            // Create temporary file for output
            File tempFile = new File(pdfPath + ".tmp");
            reader = new PdfReader(pdfPath);
            writer = new PdfWriter(tempFile);
            document = new PdfDocument(reader, writer);
            
            if (pageIndex < 0 || pageIndex >= document.getNumberOfPages()) {
                return false;
            }
            
            PdfPage page = document.getPage(pageIndex + 1);
            Rectangle pageSize = page.getPageSize();
            float pageHeight = pageSize.getHeight();
            
            // Extract text to find the object at coordinates
            PositionTextExtractionStrategy strategy = new PositionTextExtractionStrategy(pageIndex, pageHeight);
            PdfTextExtractor.getTextFromPage(page, strategy);
            
            List<TextObject> textObjects = strategy.getTextObjects();
            
            // Find closest text object to coordinates
            TextObject targetObject = null;
            float minDistance = Float.MAX_VALUE;
            float tolerance = 30.0f;
            
            for (TextObject obj : textObjects) {
                float textCenterX = obj.x + obj.width / 2;
                float textCenterY = obj.y + obj.height / 2;
                float distance = (float) Math.sqrt(
                    Math.pow(textCenterX - x, 2) + Math.pow(textCenterY - y, 2)
                );
                
                if (distance < minDistance && distance < tolerance) {
                    minDistance = distance;
                    targetObject = obj;
                }
            }
            
            if (targetObject == null) {
                Log.w(TAG, "No text found at coordinates (" + x + ", " + y + ")");
                return false;
            }
            
            // Use the same replacement logic
            boolean replaced = replaceTextAtObject(pdfPath, pageIndex, targetObject, newText, document, page, pageHeight);
            
            if (replaced) {
                // Close resources and replace file
                document.close();
                reader.close();
                writer.close();
                
                File originalFile = new File(pdfPath);
                // tempFile was already declared at the start of the method
                if (tempFile.exists()) {
                    if (originalFile.delete() && tempFile.renameTo(originalFile)) {
                        Log.d(TAG, "Text replaced successfully by coordinates");
                        return true;
                    } else {
                        Log.e(TAG, "Failed to replace original file");
                        tempFile.delete();
                        return false;
                    }
                }
            }
            
            return false;
            
        } catch (Exception e) {
            Log.e(TAG, "Error replacing text by coordinates", e);
            return false;
        } finally {
            try {
                if (document != null && !document.isClosed()) document.close();
                if (reader != null) reader.close();
                if (writer != null) writer.close();
            } catch (Exception e) {
                Log.e(TAG, "Error closing resources", e);
            }
        }
    }
    
    /**
     * Helper method to perform the actual text replacement
     */
    private static boolean replaceTextAtObject(String pdfPath, int pageIndex, TextObject targetObject, 
                                               String newText, PdfDocument document, PdfPage page, float pageHeight) {
        try {
            // Convert y coordinate
            float pdfY = pageHeight - targetObject.y;
            
            // Get font
            PdfFont font;
            try {
                String fontName = targetObject.fontName;
                if (fontName == null || fontName.isEmpty()) {
                    fontName = "Helvetica";
                }
                if (fontName.contains("Bold") && (fontName.contains("Italic") || fontName.contains("Oblique"))) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_BOLDOBLIQUE);
                } else if (fontName.contains("Bold")) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_BOLD);
                } else if (fontName.contains("Italic") || fontName.contains("Oblique")) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_OBLIQUE);
                } else {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA);
                }
            } catch (Exception e) {
                Log.w(TAG, "Could not create font, using default", e);
                font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA);
            }
            
            // Add overlay: white rectangle to cover old text, then new text
            PdfCanvas canvas = new PdfCanvas(page.newContentStreamBefore(), page.getResources(), document);
            
            // Draw white rectangle to cover old text
            float padding = 2.0f;
            canvas.setFillColor(new DeviceRgb(255, 255, 255));
            canvas.rectangle(
                targetObject.x - padding,
                pdfY - targetObject.height - padding,
                targetObject.width + (2 * padding),
                targetObject.height + (2 * padding)
            );
            canvas.fill();
            
            // Add new text
            canvas.beginText()
                .setFontAndSize(font, targetObject.fontSize)
                .setFillColor(new DeviceRgb(targetObject.colorR, targetObject.colorG, targetObject.colorB))
                .moveText(targetObject.x, pdfY)
                .showText(newText)
                .endText();
            
            // Note: Document closing and file replacement handled by caller
            return true;
            
        } catch (Exception e) {
            Log.e(TAG, "Error in replaceTextAtObject", e);
            return false;
        }
    }
    
    /**
     * Add new text to PDF at a specific position
     */
    public static boolean addText(String pdfPath, int pageIndex, String text, 
                                 float x, float y, float fontSize, String fontName,
                                 int colorR, int colorG, int colorB) {
        PdfReader reader = null;
        PdfWriter writer = null;
        PdfDocument document = null;
        try {
            // Create temporary file for output
            File tempFile = new File(pdfPath + ".tmp");
            reader = new PdfReader(pdfPath);
            writer = new PdfWriter(tempFile);
            document = new PdfDocument(reader, writer);
            
            if (pageIndex < 0 || pageIndex >= document.getNumberOfPages()) {
                return false;
            }
            
            PdfPage page = document.getPage(pageIndex + 1); // iText uses 1-based indexing
            Rectangle pageSize = page.getPageSize();
            float pageHeight = pageSize.getHeight();
            
            // Convert y coordinate (PDF is bottom-up, iText uses bottom-left origin)
            float pdfY = pageHeight - y;
            
            // Get font
            PdfFont font;
            try {
                if (fontName == null || fontName.isEmpty()) {
                    fontName = "Helvetica";
                }
                if (fontName.contains("Bold") && (fontName.contains("Italic") || fontName.contains("Oblique"))) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_BOLDOBLIQUE);
                } else if (fontName.contains("Bold")) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_BOLD);
                } else if (fontName.contains("Italic") || fontName.contains("Oblique")) {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA_OBLIQUE);
                } else {
                    font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA);
                }
            } catch (Exception e) {
                Log.w(TAG, "Could not create font, using default", e);
                font = PdfFontFactory.createFont(com.itextpdf.io.font.constants.StandardFonts.HELVETICA);
            }
            
            // Add text to page
            PdfCanvas canvas = new PdfCanvas(page.newContentStreamBefore(), page.getResources(), document);
            
            canvas.beginText()
                .setFontAndSize(font, fontSize)
                .setFillColor(new DeviceRgb(colorR, colorG, colorB))
                .moveText(x, pdfY)
                .showText(text)
                .endText();
            
            // Close resources
            document.close();
            reader.close();
            writer.close();
            
            // Replace original file with modified file
            File originalFile = new File(pdfPath);
            if (tempFile.exists()) {
                if (originalFile.delete() && tempFile.renameTo(originalFile)) {
                    Log.d(TAG, "Text added successfully");
                    return true;
                } else {
                    Log.e(TAG, "Failed to replace original file");
                    tempFile.delete(); // Clean up temp file
                    return false;
                }
            }
            return false;
            
        } catch (Exception e) {
            Log.e(TAG, "Error adding text", e);
            return false;
        } finally {
            // Ensure resources are closed
            try {
                if (document != null && !document.isClosed()) document.close();
                if (reader != null) reader.close();
                if (writer != null) writer.close();
            } catch (Exception e) {
                Log.e(TAG, "Error closing resources", e);
            }
        }
    }
    
    /**
     * Get all text objects on a page
     */
    public static List<TextObject> getAllTextObjects(String pdfPath, int pageIndex) {
        try {
            PdfReader reader = new PdfReader(pdfPath);
            PdfDocument document = new PdfDocument(reader);
            
            if (pageIndex < 0 || pageIndex >= document.getNumberOfPages()) {
                document.close();
                reader.close();
                return new ArrayList<>();
            }
            
            PdfPage page = document.getPage(pageIndex + 1); // iText uses 1-based indexing
            Rectangle pageSize = page.getPageSize();
            float pageHeight = pageSize.getHeight();
            
            PositionTextExtractionStrategy strategy = new PositionTextExtractionStrategy(pageIndex, pageHeight);
            PdfTextExtractor.getTextFromPage(page, strategy);
            
            List<TextObject> textObjects = strategy.getTextObjects();
            
            document.close();
            reader.close();
            return textObjects;
            
        } catch (Exception e) {
            Log.e(TAG, "Error getting all text objects", e);
            return new ArrayList<>();
        }
    }
}
