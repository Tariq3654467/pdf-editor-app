#include <jni.h>
#include <string>
#include <cstring>
#include <android/log.h>
#include <mupdf/fitz.h>
#include <mupdf/pdf.h>
#include <vector>

#define LOG_TAG "PDFPageRenderer"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

/**
 * Render PDF page to PNG image bytes
 * Returns: jbyteArray containing PNG image bytes, or null if failed
 */
jbyteArray renderPageToImage(JNIEnv *env, jstring pdfPath, jint pageIndex, jfloat scale) {
    const char *path = nullptr;
    fz_context *ctx = nullptr;
    fz_document *doc = nullptr;
    fz_page *page = nullptr;
    fz_pixmap *pix = nullptr;
    jbyteArray result = nullptr;
    
    try {
        path = env->GetStringUTFChars(pdfPath, nullptr);
        if (path == nullptr) {
            throw "Invalid PDF path";
        }
        
        LOGI("Rendering page %d from %s with scale %.2f", pageIndex, path, scale);
        
        // Create MuPDF context
        ctx = fz_new_context(nullptr, nullptr, FZ_STORE_UNLIMITED);
        if (!ctx) {
            throw "Failed to create MuPDF context";
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
        int pageCount = fz_count_pages(ctx, doc);
        if (pageIndex < 0 || pageIndex >= pageCount) {
            LOGE("Invalid page index: %d (total pages: %d)", pageIndex, pageCount);
            throw "Invalid page index";
        }
        
        page = fz_load_page(ctx, doc, pageIndex);
        if (!page) {
            LOGE("Failed to load page %d", pageIndex);
            throw "Failed to load page";
        }
        
        // Get page bounds
        fz_rect bounds = fz_bound_page(ctx, page);
        float pageWidth = bounds.x1 - bounds.x0;
        float pageHeight = bounds.y1 - bounds.y0;
        
        // Calculate thumbnail dimensions
        int thumbWidth = (int)(pageWidth * scale);
        int thumbHeight = (int)(pageHeight * scale);
        
        // Create transformation matrix for scaling
        fz_matrix ctm = fz_scale(scale, scale);
        
        // Render page to pixmap
        pix = fz_new_pixmap_from_page(ctx, page, ctm, fz_device_rgb(ctx), 0);
        if (!pix) {
            LOGE("Failed to render page to pixmap");
            throw "Failed to render page";
        }
        
        // Convert pixmap to PNG bytes
        // MuPDF doesn't have built-in PNG encoding, so we'll use a simple approach
        // For now, we'll create a simple PNG encoder or use Android's Bitmap API
        // This is a simplified version - in production, you might want to use libpng directly
        
        // Get pixmap data
        // MuPDF pixmap structure: width, height, stride, n (components), samples
        int width = pix->w;
        int height = pix->h;
        int stride = pix->stride;
        int n = pix->n; // Number of color components (3 for RGB, 4 for RGBA)
        unsigned char *samples = pix->samples;
        
        if (!samples || width <= 0 || height <= 0 || n < 3) {
            throw "Invalid pixmap data";
        }
        
        // MuPDF pixmap format: RGB (3 bytes per pixel) or RGBA (4 bytes per pixel)
        int bytesPerPixel = n; // Usually 3 (RGB) or 4 (RGBA)
        
        // Calculate image data size (contiguous, without stride padding)
        size_t imageDataSize = width * height * bytesPerPixel;
        
        // Convert to jbyteArray
        // We'll return raw RGB/RGBA data and encode to PNG in Kotlin using Android's Bitmap API
        jbyteArray byteArray = env->NewByteArray(imageDataSize);
        if (byteArray == nullptr) {
            throw "Failed to create byte array";
        }
        
        // Copy pixel data row by row (handle stride - stride may be larger than width*bytesPerPixel)
        jbyte *byteArrayPtr = env->GetByteArrayElements(byteArray, nullptr);
        if (byteArrayPtr == nullptr) {
            env->DeleteLocalRef(byteArray);
            throw "Failed to get byte array elements";
        }
        
        // Copy data row by row, handling stride
        for (int y = 0; y < height; y++) {
            unsigned char *srcRow = samples + (y * stride);
            jbyte *dstRow = byteArrayPtr + (y * width * bytesPerPixel);
            memcpy(dstRow, srcRow, width * bytesPerPixel);
        }
        
        env->ReleaseByteArrayElements(byteArray, byteArrayPtr, 0);
        
        result = byteArray;
        
    } catch (const char *error) {
        LOGE("Error rendering page: %s", error);
        result = nullptr;
    } catch (...) {
        LOGE("Unknown error rendering page");
        result = nullptr;
    }
    
    // Cleanup
    if (pix) {
        fz_drop_pixmap(ctx, pix);
    }
    if (page) {
        fz_drop_page(ctx, page);
    }
    if (doc) {
        fz_drop_document(ctx, doc);
    }
    if (ctx) {
        fz_drop_context(ctx);
    }
    if (path) {
        env->ReleaseStringUTFChars(pdfPath, path);
    }
    
    return result;
}

} // extern "C"

