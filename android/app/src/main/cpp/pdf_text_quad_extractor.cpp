#include <jni.h>
#include <string>
#include <vector>
#include <cmath>
#include <sstream>
#include <android/log.h>
#include "mupdf/fitz.h"
#include "mupdf/pdf.h"
#include "pdf_text_quad_extractor.h"

#define LOG_TAG "PDFTextQuadExtractor"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/**
 * Text quad structure
 */
struct TextQuad {
    float topLeftX, topLeftY;
    float topRightX, topRightY;
    float bottomLeftX, bottomLeftY;
    float bottomRightX, bottomRightY;
    std::string text;
};

/**
 * Convert quad to JSON string
 */
std::string quadToJson(const TextQuad& quad) {
    std::ostringstream oss;
    oss << "{"
        << "\"topLeft\":{\"x\":" << quad.topLeftX << ",\"y\":" << quad.topLeftY << "},"
        << "\"topRight\":{\"x\":" << quad.topRightX << ",\"y\":" << quad.topRightY << "},"
        << "\"bottomLeft\":{\"x\":" << quad.bottomLeftX << ",\"y\":" << quad.bottomLeftY << "},"
        << "\"bottomRight\":{\"x\":" << quad.bottomRightX << ",\"y\":" << quad.bottomRightY << "},"
        << "\"text\":\"" << quad.text << "\""
        << "}";
    return oss.str();
}

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Get text quads for selection range
 */
jstring getTextQuadsForSelection(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                  jfloat startX, jfloat startY, jfloat endX, jfloat endY) {
    const char *path = nullptr;
    fz_context *ctx = nullptr;
    fz_document *doc = nullptr;
    fz_page *page = nullptr;
    fz_stext_page *stext = nullptr;
    jstring result = nullptr;
    
    try {
        path = env->GetStringUTFChars(pdfPath, nullptr);
        if (path == nullptr) {
            throw "Invalid PDF path";
        }
        
        // Normalize selection rectangle (PDF uses bottom-left origin)
        float minX = std::min(startX, endX);
        float maxX = std::max(startX, endX);
        float minY = std::min(startY, endY);
        float maxY = std::max(startY, endY);
        
        LOGI("Getting text quads: page=%d, rect=(%.2f,%.2f)->(%.2f,%.2f)",
             pageIndex, minX, minY, maxX, maxY);
        
        // Create MuPDF context
        ctx = fz_new_context(nullptr, nullptr, FZ_STORE_UNLIMITED);
        if (!ctx) {
            throw "Failed to create MuPDF context";
        }
        
        fz_register_document_handlers(ctx);
        
        // Open PDF document
        doc = fz_open_document(ctx, path);
        if (!doc) {
            LOGE("Failed to open PDF: %s", path);
            throw "Failed to open document";
        }
        
        // Load page
        if (pageIndex < 0 || pageIndex >= fz_count_pages(ctx, doc)) {
            LOGE("Invalid page index: %d", pageIndex);
            throw "Invalid page index";
        }
        
        page = fz_load_page(ctx, doc, pageIndex);
        if (!page) {
            LOGE("Failed to load page %d", pageIndex);
            throw "Failed to load page";
        }
        
        // Extract structured text
        fz_stext_options opts = { 0 };
        stext = fz_new_stext_page_from_page(ctx, page, &opts);
        if (!stext) {
            LOGE("Failed to extract text from page");
            throw "Failed to extract text";
        }
        
        // Collect quads for characters/lines within selection
        std::vector<TextQuad> quads;
        
        // Iterate through text blocks
        for (fz_stext_block *block = stext->first_block; block; block = block->next) {
            if (block->type != FZ_STEXT_BLOCK_TEXT) {
                continue;
            }
            
            // Iterate through lines
            for (fz_stext_line *line = block->u.t.first_line; line; line = line->next) {
                fz_rect line_bbox = line->bbox;
                
                // Check if line intersects selection rectangle
                bool lineIntersects = !(line_bbox.x1 < minX || line_bbox.x0 > maxX ||
                                       line_bbox.y1 < minY || line_bbox.y0 > maxY);
                
                if (lineIntersects) {
                    // Collect characters in this line
                    std::string lineText;
                    fz_rect charQuad = { 0 };
                    bool firstChar = true;
                    fz_stext_char *prevChar = nullptr;
                    
                    for (fz_stext_char *ch = line->first_char; ch; ch = ch->next) {
                        // Calculate character bbox from origin and size
                        // Character width is approximated from font size (typically 0.6 * size for most fonts)
                        float charWidth = ch->size * 0.6f;
                        float charHeight = ch->size;
                        
                        // If we have previous char, use distance between origins for width
                        if (prevChar) {
                            float dx = ch->origin.x - prevChar->origin.x;
                            if (dx > 0 && dx < charWidth * 2) {
                                charWidth = dx;
                            }
                        }
                        
                        fz_rect char_bbox;
                        char_bbox.x0 = ch->origin.x;
                        char_bbox.y0 = ch->origin.y - charHeight * 0.8f; // Baseline to top
                        char_bbox.x1 = ch->origin.x + charWidth;
                        char_bbox.y1 = ch->origin.y + charHeight * 0.2f; // Baseline to bottom
                        
                        // Check if character is in selection
                        bool charInSelection = !(char_bbox.x1 < minX || char_bbox.x0 > maxX ||
                                                char_bbox.y1 < minY || char_bbox.y0 > maxY);
                        
                        if (charInSelection) {
                            // Add character to current text
                            if (ch->c >= 32 && ch->c < 127) {
                                lineText += (char)ch->c;
                            } else if (ch->c > 127) {
                                lineText += (char)ch->c;
                            }
                            
                            // Merge character bbox into quad
                            if (firstChar) {
                                charQuad = char_bbox;
                                firstChar = false;
                            } else {
                                // Expand quad to include this character
                                charQuad.x0 = std::min(charQuad.x0, char_bbox.x0);
                                charQuad.y0 = std::min(charQuad.y0, char_bbox.y0);
                                charQuad.x1 = std::max(charQuad.x1, char_bbox.x1);
                                charQuad.y1 = std::max(charQuad.y1, char_bbox.y1);
                            }
                        } else if (!lineText.empty()) {
                            // End of selection in this line, create quad
                            TextQuad quad;
                            quad.topLeftX = charQuad.x0;
                            quad.topLeftY = charQuad.y0;
                            quad.topRightX = charQuad.x1;
                            quad.topRightY = charQuad.y0;
                            quad.bottomLeftX = charQuad.x0;
                            quad.bottomLeftY = charQuad.y1;
                            quad.bottomRightX = charQuad.x1;
                            quad.bottomRightY = charQuad.y1;
                            quad.text = lineText;
                            quads.push_back(quad);
                            
                            lineText.clear();
                            firstChar = true;
                        }
                        
                        prevChar = ch;
                    }
                    
                    // Add final quad for this line if text collected
                    if (!lineText.empty()) {
                        TextQuad quad;
                        quad.topLeftX = charQuad.x0;
                        quad.topLeftY = charQuad.y0;
                        quad.topRightX = charQuad.x1;
                        quad.topRightY = charQuad.y0;
                        quad.bottomLeftX = charQuad.x0;
                        quad.bottomLeftY = charQuad.y1;
                        quad.bottomRightX = charQuad.x1;
                        quad.bottomRightY = charQuad.y1;
                        quad.text = lineText;
                        quads.push_back(quad);
                    }
                }
            }
        }
        
        // Build JSON array of quads
        std::ostringstream json;
        json << "[";
        for (size_t i = 0; i < quads.size(); i++) {
            if (i > 0) json << ",";
            json << quadToJson(quads[i]);
        }
        json << "]";
        
        std::string jsonStr = json.str();
        result = env->NewStringUTF(jsonStr.c_str());
        LOGI("Extracted %zu text quads", quads.size());
        
    } catch (const char *error) {
        LOGE("Error in getTextQuadsForSelection: %s", error);
    } catch (...) {
        LOGE("Unknown error in getTextQuadsForSelection");
    }
    
    // Cleanup
    if (stext) fz_drop_stext_page(ctx, stext);
    if (page) fz_drop_page(ctx, page);
    if (doc) fz_drop_document(ctx, doc);
    if (ctx) fz_drop_context(ctx);
    if (path) env->ReleaseStringUTFChars(pdfPath, path);
    
    return result;
}

#ifdef __cplusplus
}
#endif

