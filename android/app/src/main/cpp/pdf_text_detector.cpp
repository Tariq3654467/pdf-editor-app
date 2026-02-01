#include <jni.h>
#include <string>
#include <vector>
#include <cmath>
#include <cfloat>
#include <cstdio>
#include <android/log.h>
#include "mupdf/fitz.h"
#include "mupdf/pdf.h"
#include "pdf_text_detector.h"

#define LOG_TAG "PDFTextDetector"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Helper to check and clear JNI exceptions
static void checkJNIException(JNIEnv *env, const char *context) {
    jthrowable exc = env->ExceptionOccurred();
    if (exc) {
        env->ExceptionClear();
        LOGE("JNI Exception in %s", context);
    }
}

/**
 * Text object structure for detection
 */
struct TextObject {
    std::string text;
    std::string fontName;
    float fontSize;
    float x, y, width, height;
    std::string objectId; // PDF object reference
    int pageIndex;
};

/**
 * Calculate distance between point and text object
 */
float calculateDistance(float x, float y, const TextObject& obj) {
    float centerX = obj.x + obj.width / 2.0f;
    float centerY = obj.y + obj.height / 2.0f;
    float dx = x - centerX;
    float dy = y - centerY;
    return std::sqrt(dx * dx + dy * dy);
}

/**
 * Check if point is inside text object bounds
 */
bool isPointInBounds(float x, float y, const TextObject& obj) {
    return (x >= obj.x && x <= obj.x + obj.width &&
            y >= obj.y && y <= obj.y + obj.height);
}

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Detect text object at position using MuPDF
 * 
 * This function will:
 * 1. Load PDF page
 * 2. Extract all text objects with their bounds
 * 3. Find the nearest text object to the tap position
 * 4. Return text object information
 */
jobject detectTextAtPosition(JNIEnv *env, jstring pdfPath, jint pageIndex, jfloat x, jfloat y) {
    LOGI("Detecting text at page %d, position (%.2f, %.2f)", pageIndex, x, y);
    
    const char *path = env->GetStringUTFChars(pdfPath, nullptr);
    if (path == nullptr) {
        LOGE("Failed to get PDF path");
        return nullptr;
    }
    
    fz_context *ctx = nullptr;
    fz_document *doc = nullptr;
    fz_page *page = nullptr;
    fz_stext_page *stext = nullptr;
    
    jobject result = nullptr;
    
    try {
        // Create MuPDF context
        ctx = fz_new_context(nullptr, nullptr, FZ_STORE_UNLIMITED);
        if (!ctx) {
            LOGE("Failed to create MuPDF context");
            env->ReleaseStringUTFChars(pdfPath, path);
            return nullptr;
        }
        
        // Register PDF document handler
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
        
        // Extract structured text with bounds
        fz_stext_options opts = { 0 };
        stext = fz_new_stext_page_from_page(ctx, page, &opts);
        if (!stext) {
            LOGE("Failed to extract text from page");
            throw "Failed to extract text";
        }
        
        // Find text object closest to (x, y)
        TextObject nearestText;
        float minDistance = FLT_MAX;
        bool found = false;
        
        // Iterate through text blocks
        for (fz_stext_block *block = stext->first_block; block; block = block->next) {
            if (block->type != FZ_STEXT_BLOCK_TEXT) {
                continue;
            }
            
            // Iterate through lines in block
            for (fz_stext_line *line = block->u.t.first_line; line; line = line->next) {
                // Get line bounding box
                fz_rect line_bbox = line->bbox;
                
                // Check if point is near this line
                float lineCenterX = (line_bbox.x0 + line_bbox.x1) / 2.0f;
                float lineCenterY = (line_bbox.y0 + line_bbox.y1) / 2.0f;
                float distance = std::sqrt((x - lineCenterX) * (x - lineCenterX) + 
                                          (y - lineCenterY) * (y - lineCenterY));
                
                // Collect text from line
                std::string lineText;
                float fontSize = 12.0f;
                std::string fontName = "Helvetica";
                
                for (fz_stext_char *ch = line->first_char; ch; ch = ch->next) {
                    if (ch->c >= 32 && ch->c < 127) { // Printable ASCII
                        lineText += (char)ch->c;
                    } else if (ch->c > 127) {
                        // Handle UTF-8 (simplified)
                        lineText += (char)ch->c;
                    }
                    
                    // Get font info from first char
                    if (lineText.length() == 1 && ch->font) {
                        fontSize = ch->size;
                        // Try to get font name (may need adjustment based on MuPDF version)
                        const char *font_name = fz_font_name(ctx, ch->font);
                        if (font_name) {
                            fontName = font_name;
                        }
                    }
                }
                
                if (!lineText.empty() && distance < minDistance) {
                    minDistance = distance;
                    nearestText.text = lineText;
                    nearestText.fontName = fontName;
                    nearestText.fontSize = fontSize;
                    nearestText.x = line_bbox.x0;
                    nearestText.y = line_bbox.y0;
                    nearestText.width = line_bbox.x1 - line_bbox.x0;
                    nearestText.height = line_bbox.y1 - line_bbox.y0;
                    nearestText.pageIndex = pageIndex;
                    // Generate object ID from position and text hash
                    char objId[256];
                    snprintf(objId, sizeof(objId), "obj_%d_%d_%d", pageIndex, 
                            (int)(line_bbox.x0 * 100), (int)(line_bbox.y0 * 100));
                    nearestText.objectId = objId;
                    found = true;
                }
            }
        }
        
        // Create Java object if text found
        if (found) {
            jclass textObjectClass = env->FindClass("com/example/pdf_editor_app/PDFEditorNative$PDFTextObject");
            if (!textObjectClass) {
                LOGE("Failed to find PDFTextObject class");
                // Check for exception
                jthrowable exc = env->ExceptionOccurred();
                if (exc) {
                    env->ExceptionClear();
                    LOGE("Exception while finding class");
                }
            } else {
                // Constructor signature: (String, String, float, float, float, float, float, String, int)
                // Parameters: text, fontName, fontSize, x, y, width, height, objectId, pageIndex
                // Note: 5 floats (FFFFF), not 6
                jmethodID constructor = env->GetMethodID(textObjectClass, "<init>",
                    "(Ljava/lang/String;Ljava/lang/String;FFFFFLjava/lang/String;I)V");
                
                if (!constructor) {
                    LOGE("Failed to find PDFTextObject constructor");
                    // Check for exception
                    jthrowable exc = env->ExceptionOccurred();
                    if (exc) {
                        env->ExceptionClear();
                        LOGE("Exception while finding constructor - signature may be wrong");
                        // Try to get error message
                        jclass excClass = env->GetObjectClass(exc);
                        if (excClass) {
                            jmethodID getMessage = env->GetMethodID(excClass, "toString", "()Ljava/lang/String;");
                            if (getMessage) {
                                jstring msg = (jstring)env->CallObjectMethod(exc, getMessage);
                                if (msg) {
                                    const char *msgStr = env->GetStringUTFChars(msg, nullptr);
                                    if (msgStr) {
                                        LOGE("Exception message: %s", msgStr);
                                        env->ReleaseStringUTFChars(msg, msgStr);
                                    }
                                    env->DeleteLocalRef(msg);
                                }
                            }
                            env->DeleteLocalRef(excClass);
                        }
                    }
                } else {
                    jstring text = env->NewStringUTF(nearestText.text.c_str());
                    jstring fontName = env->NewStringUTF(nearestText.fontName.c_str());
                    jstring objectId = env->NewStringUTF(nearestText.objectId.c_str());
                    
                    if (text && fontName && objectId) {
                        result = env->NewObject(textObjectClass, constructor,
                            text, fontName, nearestText.fontSize,
                            nearestText.x, nearestText.y,
                            nearestText.width, nearestText.height,
                            objectId, nearestText.pageIndex);
                        
                        if (!result) {
                            LOGE("Failed to create PDFTextObject instance");
                            jthrowable exc = env->ExceptionOccurred();
                            if (exc) {
                                env->ExceptionClear();
                                LOGE("Exception while creating object");
                            }
                        } else {
                            LOGI("Successfully created PDFTextObject");
                        }
                    } else {
                        LOGE("Failed to create string parameters");
                    }
                    
                    if (text) env->DeleteLocalRef(text);
                    if (fontName) env->DeleteLocalRef(fontName);
                    if (objectId) env->DeleteLocalRef(objectId);
                }
                env->DeleteLocalRef(textObjectClass);
            }
        }
        
    } catch (const char *error) {
        LOGE("Error in detectTextAtPosition: %s", error);
    } catch (...) {
        LOGE("Unknown error in detectTextAtPosition");
    }
    
    // Cleanup
    if (stext) fz_drop_stext_page(ctx, stext);
    if (page) fz_drop_page(ctx, page);
    if (doc) fz_drop_document(ctx, doc);
    if (ctx) fz_drop_context(ctx);
    
    env->ReleaseStringUTFChars(pdfPath, path);
    
    return result;
}

#ifdef __cplusplus
}
#endif

