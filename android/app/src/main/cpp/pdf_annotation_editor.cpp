#include <jni.h>
#include <string>
#include <vector>
#include <cmath>
#include <android/log.h>
#include "mupdf/fitz.h"
#include "mupdf/pdf.h"
#include "pdf_annotation_editor.h"

#define LOG_TAG "PDFAnnotationEditor"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Add pen annotation (freehand path) to PDF content stream
 */
jboolean addPenAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                          jfloatArray pointsX, jfloatArray pointsY, jint pointCount,
                          jint colorR, jint colorG, jint colorB, jfloat strokeWidth) {
    const char *path = nullptr;
    jfloat *xArray = nullptr;
    jfloat *yArray = nullptr;
    
    fz_context *ctx = nullptr;
    fz_document *doc = nullptr;
    pdf_document *pdf = nullptr;
    fz_page *fz_page_obj = nullptr;
    pdf_page *page = nullptr;
    
    jboolean result = JNI_FALSE;
    
    try {
        path = env->GetStringUTFChars(pdfPath, nullptr);
        if (path == nullptr || pointCount <= 0) {
            throw "Invalid arguments";
        }
        
        xArray = env->GetFloatArrayElements(pointsX, nullptr);
        yArray = env->GetFloatArrayElements(pointsY, nullptr);
        if (xArray == nullptr || yArray == nullptr) {
            throw "Failed to get point arrays";
        }
        
        LOGI("Adding pen annotation: page=%d, points=%d, color=(%d,%d,%d), width=%.2f",
             pageIndex, pointCount, colorR, colorG, colorB, strokeWidth);
        
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
        
        pdf = pdf_specifics(ctx, doc);
        if (!pdf) {
            LOGE("Document is not a PDF");
            throw "Not a PDF document";
        }
        
        // Load page
        if (pageIndex < 0 || pageIndex >= fz_count_pages(ctx, doc)) {
            LOGE("Invalid page index: %d", pageIndex);
            throw "Invalid page index";
        }
        
        fz_page_obj = fz_load_page(ctx, doc, pageIndex);
        if (!fz_page_obj) {
            LOGE("Failed to load page %d", pageIndex);
            throw "Failed to load page";
        }
        
        page = pdf_page_from_fz_page(ctx, fz_page_obj);
        if (!page) {
            LOGE("Failed to get PDF page object");
            throw "Failed to get PDF page";
        }
        
        // Create content stream buffer for drawing path
        fz_buffer *buf = fz_new_buffer(ctx, 1024);
        fz_output *out = fz_new_output_with_buffer(ctx, buf);
        
        // Write PDF drawing commands using fz_write_printf
        // Set color (RGB values 0-1)
        fz_write_printf(ctx, out, "%.3f %.3f %.3f RG\n", 
                       colorR / 255.0f, colorG / 255.0f, colorB / 255.0f);
        
        // Set line width
        fz_write_printf(ctx, out, "%.3f w\n", strokeWidth);
        
        // Round line cap and join
        fz_write_string(ctx, out, "1 J\n"); // Round line cap
        fz_write_string(ctx, out, "1 j\n"); // Round line join
        
        // Draw path
        if (pointCount > 0) {
            fz_write_printf(ctx, out, "%.2f %.2f m\n", xArray[0], yArray[0]);
            for (int i = 1; i < pointCount; i++) {
                fz_write_printf(ctx, out, "%.2f %.2f l\n", xArray[i], yArray[i]);
            }
            fz_write_string(ctx, out, "S\n"); // Stroke path
        }
        
        fz_close_output(ctx, out);
        fz_drop_output(ctx, out);
        
        // Append buffer to page contents
        // Get page object dictionary
        pdf_obj *page_obj = pdf_lookup_page_obj(ctx, pdf, pageIndex);
        if (!page_obj) {
            LOGE("Failed to get page object");
            throw "Failed to get page object";
        }
        
        pdf_obj *contents_obj = pdf_page_contents(ctx, page);
        pdf_obj *new_stream = pdf_add_stream(ctx, pdf, buf, nullptr, 0);
        
        // If contents is an array, append; otherwise create array
        if (pdf_is_array(ctx, contents_obj)) {
            pdf_array_push(ctx, contents_obj, new_stream);
        } else {
            pdf_obj *contents_array = pdf_new_array(ctx, pdf, 2);
            if (contents_obj && !pdf_is_null(ctx, contents_obj)) {
                pdf_array_push(ctx, contents_array, contents_obj);
            }
            pdf_array_push(ctx, contents_array, new_stream);
            pdf_dict_put(ctx, page_obj, PDF_NAME(Contents), contents_array);
        }
        
        pdf_drop_obj(ctx, new_stream);
        fz_drop_buffer(ctx, buf);
        
        result = JNI_TRUE;
        LOGI("Pen annotation added successfully");
        
    } catch (const char *error) {
        LOGE("Error in addPenAnnotation: %s", error);
        result = JNI_FALSE;
    } catch (...) {
        LOGE("Unknown error in addPenAnnotation");
        result = JNI_FALSE;
    }
    
    // Cleanup
    if (yArray) env->ReleaseFloatArrayElements(pointsY, yArray, JNI_ABORT);
    if (xArray) env->ReleaseFloatArrayElements(pointsX, xArray, JNI_ABORT);
    if (fz_page_obj) fz_drop_page(ctx, fz_page_obj);
    if (doc) fz_drop_document(ctx, doc);
    if (ctx) fz_drop_context(ctx);
    if (path) env->ReleaseStringUTFChars(pdfPath, path);
    
    return result;
}

/**
 * Add highlight annotation (filled rectangle) to PDF content stream
 */
jboolean addHighlightAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                jfloat x, jfloat y, jfloat width, jfloat height,
                                jint colorR, jint colorG, jint colorB, jfloat opacity) {
    const char *path = nullptr;
    
    fz_context *ctx = nullptr;
    fz_document *doc = nullptr;
    pdf_document *pdf = nullptr;
    fz_page *fz_page_obj = nullptr;
    pdf_page *page = nullptr;
    
    jboolean result = JNI_FALSE;
    
    try {
        path = env->GetStringUTFChars(pdfPath, nullptr);
        if (path == nullptr) {
            throw "Invalid arguments";
        }
        
        LOGI("Adding highlight annotation: page=%d, rect=(%.2f,%.2f,%.2f,%.2f), color=(%d,%d,%d), opacity=%.2f",
             pageIndex, x, y, width, height, colorR, colorG, colorB, opacity);
        
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
        
        pdf = pdf_specifics(ctx, doc);
        if (!pdf) {
            LOGE("Document is not a PDF");
            throw "Not a PDF document";
        }
        
        // Load page
        if (pageIndex < 0 || pageIndex >= fz_count_pages(ctx, doc)) {
            LOGE("Invalid page index: %d", pageIndex);
            throw "Invalid page index";
        }
        
        fz_page_obj = fz_load_page(ctx, doc, pageIndex);
        if (!fz_page_obj) {
            LOGE("Failed to load page %d", pageIndex);
            throw "Failed to load page";
        }
        
        page = pdf_page_from_fz_page(ctx, fz_page_obj);
        if (!page) {
            LOGE("Failed to get PDF page object");
            throw "Failed to get PDF page";
        }
        
        // Create content stream buffer
        fz_buffer *buf = fz_new_buffer(ctx, 512);
        fz_output *out = fz_new_output_with_buffer(ctx, buf);
        
        // Write PDF drawing commands for filled rectangle
        fz_write_printf(ctx, out, "%.3f %.3f %.3f rg\n", 
                        colorR / 255.0f, colorG / 255.0f, colorB / 255.0f);
        
        fz_write_printf(ctx, out, "%.2f %.2f %.2f %.2f re\n", x, y, width, height);
        
        fz_write_string(ctx, out, "f\n"); // Fill rectangle
        
        fz_close_output(ctx, out);
        fz_drop_output(ctx, out);
        
        // Append buffer to page contents
        pdf_obj *page_obj = pdf_lookup_page_obj(ctx, pdf, pageIndex);
        if (!page_obj) {
            LOGE("Failed to get page object");
            throw "Failed to get page object";
        }
        
        pdf_obj *contents_obj = pdf_page_contents(ctx, page);
        pdf_obj *new_stream = pdf_add_stream(ctx, pdf, buf, nullptr, 0);
        
        if (pdf_is_array(ctx, contents_obj)) {
            pdf_array_push(ctx, contents_obj, new_stream);
        } else {
            pdf_obj *contents_array = pdf_new_array(ctx, pdf, 2);
            if (contents_obj && !pdf_is_null(ctx, contents_obj)) {
                pdf_array_push(ctx, contents_array, contents_obj);
            }
            pdf_array_push(ctx, contents_array, new_stream);
            pdf_dict_put(ctx, page_obj, PDF_NAME(Contents), contents_array);
        }
        
        pdf_drop_obj(ctx, new_stream);
        fz_drop_buffer(ctx, buf);
        
        result = JNI_TRUE;
        LOGI("Highlight annotation added successfully");
        
    } catch (const char *error) {
        LOGE("Error in addHighlightAnnotation: %s", error);
        result = JNI_FALSE;
    } catch (...) {
        LOGE("Unknown error in addHighlightAnnotation");
        result = JNI_FALSE;
    }
    
    // Cleanup
    if (fz_page_obj) fz_drop_page(ctx, fz_page_obj);
    if (doc) fz_drop_document(ctx, doc);
    if (ctx) fz_drop_context(ctx);
    if (path) env->ReleaseStringUTFChars(pdfPath, path);
    
    return result;
}

/**
 * Add underline annotation (line) to PDF content stream
 */
jboolean addUnderlineAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                jfloat x1, jfloat y1, jfloat x2, jfloat y2,
                                jint colorR, jint colorG, jint colorB, jfloat strokeWidth) {
    const char *path = nullptr;
    
    fz_context *ctx = nullptr;
    fz_document *doc = nullptr;
    pdf_document *pdf = nullptr;
    fz_page *fz_page_obj = nullptr;
    pdf_page *page = nullptr;
    
    jboolean result = JNI_FALSE;
    
    try {
        path = env->GetStringUTFChars(pdfPath, nullptr);
        if (path == nullptr) {
            throw "Invalid arguments";
        }
        
        LOGI("Adding underline annotation: page=%d, line=(%.2f,%.2f)->(%.2f,%.2f), color=(%d,%d,%d), width=%.2f",
             pageIndex, x1, y1, x2, y2, colorR, colorG, colorB, strokeWidth);
        
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
        
        pdf = pdf_specifics(ctx, doc);
        if (!pdf) {
            LOGE("Document is not a PDF");
            throw "Not a PDF document";
        }
        
        // Load page
        if (pageIndex < 0 || pageIndex >= fz_count_pages(ctx, doc)) {
            LOGE("Invalid page index: %d", pageIndex);
            throw "Invalid page index";
        }
        
        fz_page_obj = fz_load_page(ctx, doc, pageIndex);
        if (!fz_page_obj) {
            LOGE("Failed to load page %d", pageIndex);
            throw "Failed to load page";
        }
        
        page = pdf_page_from_fz_page(ctx, fz_page_obj);
        if (!page) {
            LOGE("Failed to get PDF page object");
            throw "Failed to get PDF page";
        }
        
        // Create content stream buffer
        fz_buffer *buf = fz_new_buffer(ctx, 256);
        fz_output *out = fz_new_output_with_buffer(ctx, buf);
        
        // Write PDF drawing commands for line
        fz_write_printf(ctx, out, "%.3f %.3f %.3f RG\n", 
                        colorR / 255.0f, colorG / 255.0f, colorB / 255.0f);
        
        fz_write_printf(ctx, out, "%.3f w\n", strokeWidth);
        
        fz_write_printf(ctx, out, "%.2f %.2f m\n", x1, y1);
        
        fz_write_printf(ctx, out, "%.2f %.2f l\n", x2, y2);
        
        fz_write_string(ctx, out, "S\n"); // Stroke line
        
        fz_close_output(ctx, out);
        fz_drop_output(ctx, out);
        
        // Append buffer to page contents
        pdf_obj *page_obj = pdf_lookup_page_obj(ctx, pdf, pageIndex);
        if (!page_obj) {
            LOGE("Failed to get page object");
            throw "Failed to get page object";
        }
        
        pdf_obj *contents_obj = pdf_page_contents(ctx, page);
        pdf_obj *new_stream = pdf_add_stream(ctx, pdf, buf, nullptr, 0);
        
        if (pdf_is_array(ctx, contents_obj)) {
            pdf_array_push(ctx, contents_obj, new_stream);
        } else {
            pdf_obj *contents_array = pdf_new_array(ctx, pdf, 2);
            if (contents_obj && !pdf_is_null(ctx, contents_obj)) {
                pdf_array_push(ctx, contents_array, contents_obj);
            }
            pdf_array_push(ctx, contents_array, new_stream);
            pdf_dict_put(ctx, page_obj, PDF_NAME(Contents), contents_array);
        }
        
        pdf_drop_obj(ctx, new_stream);
        fz_drop_buffer(ctx, buf);
        
        result = JNI_TRUE;
        LOGI("Underline annotation added successfully");
        
    } catch (const char *error) {
        LOGE("Error in addUnderlineAnnotation: %s", error);
        result = JNI_FALSE;
    } catch (...) {
        LOGE("Unknown error in addUnderlineAnnotation");
        result = JNI_FALSE;
    }
    
    // Cleanup
    if (fz_page_obj) fz_drop_page(ctx, fz_page_obj);
    if (doc) fz_drop_document(ctx, doc);
    if (ctx) fz_drop_context(ctx);
    if (path) env->ReleaseStringUTFChars(pdfPath, path);
    
    return result;
}

#ifdef __cplusplus
}
#endif

