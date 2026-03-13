#include <jni.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include <sstream>
#include <cctype>
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
    int pageIndex;
    std::string text;
    std::string objectId;
};

/**
 * Check if text contains alphanumeric characters
 */
bool hasAlphanumeric(const std::string& text) {
    for (char c : text) {
        if (std::isalnum(static_cast<unsigned char>(c))) {
            return true;
        }
    }
    return false;
}

/**
 * Generate objectId from quad center and page index
 * Format: obj_<pageIndex>_<round(centerX*100)>_<round(centerY*100)>
 */
std::string generateObjectId(int pageIndex, float centerX, float centerY) {
    std::ostringstream oss;
    oss << "obj_" << pageIndex << "_" 
        << static_cast<int>(std::round(centerX * 100.0f)) << "_"
        << static_cast<int>(std::round(centerY * 100.0f));
    return oss.str();
}

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
        << "\"pageIndex\":" << quad.pageIndex << ","
        << "\"text\":\"" << quad.text << "\","
        << "\"objectId\":\"" << quad.objectId << "\""
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
        
        const float minX = std::min(startX, endX);
        const float minY = std::min(startY, endY);
        const float maxX = std::max(startX, endX);
        const float maxY = std::max(startY, endY);

        constexpr float TAP_TOLERANCE = 12.0f; // PDF units
        fz_rect tapRect;
        tapRect.x0 = minX;
        tapRect.y0 = minY;
        tapRect.x1 = maxX;
        tapRect.y1 = maxY;

        // For point taps, expand a tiny rect so nearby words are still found.
        if ((tapRect.x1 - tapRect.x0) < 1.0f && (tapRect.y1 - tapRect.y0) < 1.0f) {
            const float tapX = (startX + endX) / 2.0f;
            const float tapY = (startY + endY) / 2.0f;
            tapRect.x0 = tapX - TAP_TOLERANCE;
            tapRect.y0 = tapY - TAP_TOLERANCE;
            tapRect.x1 = tapX + TAP_TOLERANCE;
            tapRect.y1 = tapY + TAP_TOLERANCE;
        }
        
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
        
        // Get page bounds for debug validation
        fz_rect pageRect = fz_bound_page(ctx, page);
        float pageHeight = pageRect.y1;
        LOGI("Selection rect: (%.2f, %.2f) -> (%.2f, %.2f), pageHeight=%.2f",
             tapRect.x0, tapRect.y0, tapRect.x1, tapRect.y1, pageHeight);
        
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
        // Process ALL text blocks - filter only at word level to ensure we never miss words
        int totalBlocks = 0;
        int processedBlocks = 0;
        int totalWords = 0;
        int acceptedWords = 0;
        
        for (fz_stext_block *block = stext->first_block; block; block = block->next) {
            if (block->type != FZ_STEXT_BLOCK_TEXT) {
                continue;
            }
            
            totalBlocks++;
            
            // Process ALL lines in ALL text blocks
            // Word-level filtering will catch only relevant words
            for (fz_stext_line *line = block->u.t.first_line; line; line = line->next) {
                    // Build all words in this line, then check if word bounding box intersects tap rect
                    std::string wordText;
                    fz_rect wordQuad = { 0 };
                    bool firstChar = true;
                    fz_stext_char *prevChar = nullptr;
                    
                    // Helper to finalize current word and create quad if word bounding box intersects tap rect
                    auto finalizeWord = [&]() {
                        if (!wordText.empty() && hasAlphanumeric(wordText)) {
                            totalWords++;
                            
                            // Expand word bounding box significantly for intersection check
                            // Use larger expansion to catch nearby words
                            constexpr float WORD_EXPANSION = 15.0f; // PDF units - increased from 5.0f
                            fz_rect expandedWordRect = wordQuad;
                            expandedWordRect.x0 -= WORD_EXPANSION;
                            expandedWordRect.y0 -= WORD_EXPANSION;
                            expandedWordRect.x1 += WORD_EXPANSION;
                            expandedWordRect.y1 += WORD_EXPANSION;
                            
                            // Check if expanded word rect intersects tap rect
                            // Use fz_intersect_rect logic: intersection exists if rects overlap
                            bool wordIntersects = !(expandedWordRect.x1 < tapRect.x0 || 
                                                    expandedWordRect.x0 > tapRect.x1 ||
                                                    expandedWordRect.y1 < tapRect.y0 || 
                                                    expandedWordRect.y0 > tapRect.y1);
                            
                            if (wordIntersects) {
                                acceptedWords++;
                                float centerX = (wordQuad.x0 + wordQuad.x1) / 2.0f;
                                float centerY = (wordQuad.y0 + wordQuad.y1) / 2.0f;
                                
                                TextQuad quad;
                                quad.topLeftX = wordQuad.x0;
                                quad.topLeftY = wordQuad.y0;
                                quad.topRightX = wordQuad.x1;
                                quad.topRightY = wordQuad.y0;
                                quad.bottomLeftX = wordQuad.x0;
                                quad.bottomLeftY = wordQuad.y1;
                                quad.bottomRightX = wordQuad.x1;
                                quad.bottomRightY = wordQuad.y1;
                                quad.pageIndex = pageIndex;
                                quad.text = wordText;
                                quad.objectId = generateObjectId(pageIndex, centerX, centerY);
                                quads.push_back(quad);
                                
                                LOGI("Accepted word '%s' — rect intersect (word: %.2f,%.2f->%.2f,%.2f, tap: %.2f,%.2f->%.2f,%.2f)",
                                     wordText.c_str(), wordQuad.x0, wordQuad.y0, wordQuad.x1, wordQuad.y1,
                                     tapRect.x0, tapRect.y0, tapRect.x1, tapRect.y1);
                            } else {
                                LOGI("Rejected word '%s' — no rect intersection (word: %.2f,%.2f->%.2f,%.2f, tap: %.2f,%.2f->%.2f,%.2f)",
                                     wordText.c_str(), wordQuad.x0, wordQuad.y0, wordQuad.x1, wordQuad.y1,
                                     tapRect.x0, tapRect.y0, tapRect.x1, tapRect.y1);
                            }
                        } else if (!wordText.empty()) {
                            LOGI("Rejected word '%s' — no alphanumeric characters", wordText.c_str());
                        }
                        wordText.clear();
                        firstChar = true;
                    };
                    
                    // Build all words in the line first
                    for (fz_stext_char *ch = line->first_char; ch; ch = ch->next) {
                        // Calculate character bbox from origin and size
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
                        char_bbox.y0 = ch->origin.y - charHeight * 0.8f;
                        char_bbox.x1 = ch->origin.x + charWidth;
                        char_bbox.y1 = ch->origin.y + charHeight * 0.2f;
                        
                        // Determine if this is a word boundary character
                        bool isWordBoundary = (ch->c == 32 || ch->c == 9 || 
                                              (ch->c >= 0 && ch->c < 32) ||
                                              (std::ispunct(static_cast<unsigned char>(ch->c)) && ch->c != '_'));
                        
                        // Add character to current word
                        if (ch->c >= 32 && ch->c < 127) {
                            wordText += (char)ch->c;
                        } else if (ch->c > 127) {
                            wordText += (char)ch->c;
                        }
                        
                        // Merge character bbox into word quad
                        if (firstChar) {
                            wordQuad = char_bbox;
                            firstChar = false;
                        } else {
                            wordQuad.x0 = std::min(wordQuad.x0, char_bbox.x0);
                            wordQuad.y0 = std::min(wordQuad.y0, char_bbox.y0);
                            wordQuad.x1 = std::max(wordQuad.x1, char_bbox.x1);
                            wordQuad.y1 = std::max(wordQuad.y1, char_bbox.y1);
                        }
                        
                        // If we hit a word boundary, finalize the word
                        if (isWordBoundary && !wordText.empty()) {
                            finalizeWord();
                        }
                        
                        prevChar = ch;
                    }
                    
                    // Finalize last word if any
                    finalizeWord();
                }
            
            if (totalWords > 0) {
                processedBlocks++;
            }
        }
        
        // Log diagnostic information
        if (quads.size() == 0) {
            LOGI("Diagnostics: totalBlocks=%d, processedBlocks=%d, totalWords=%d, acceptedWords=%d",
                 totalBlocks, processedBlocks, totalWords, acceptedWords);
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
        
        if (quads.size() == 0) {
            LOGI("Extracted 0 text quads — no words found intersecting tap rect (%.2f,%.2f)->(%.2f,%.2f)",
                 tapRect.x0, tapRect.y0, tapRect.x1, tapRect.y1);
        } else {
            LOGI("Extracted %zu text quads", quads.size());
        }
        
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

