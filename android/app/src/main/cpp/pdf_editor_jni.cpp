#include <jni.h>
#include <string>
#include <android/log.h>
#include "pdf_annotation_editor.h"
#include "pdf_text_quad_extractor.h"

#define LOG_TAG "PDFEditorNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

// Forward declarations
jobject detectTextAtPosition(JNIEnv *env, jstring pdfPath, jint pageIndex, jfloat x, jfloat y);
jboolean replaceTextInPDF(JNIEnv *env, jstring pdfPath, jint pageIndex, jstring objectId, jstring newText);
jboolean savePDF(JNIEnv *env, jstring pdfPath);
jboolean addPenAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                          jfloatArray pointsX, jfloatArray pointsY, jint pointCount,
                          jint colorR, jint colorG, jint colorB, jfloat strokeWidth);
jboolean addHighlightAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                jfloat x, jfloat y, jfloat width, jfloat height,
                                jint colorR, jint colorG, jint colorB, jfloat opacity);
jboolean addUnderlineAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                jfloat x1, jfloat y1, jfloat x2, jfloat y2,
                                jint colorR, jint colorG, jint colorB, jfloat strokeWidth);
jstring getTextQuadsForSelection(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                 jfloat startX, jfloat startY, jfloat endX, jfloat endY);
jbyteArray renderPageToImage(JNIEnv *env, jstring pdfPath, jint pageIndex, jfloat scale);

/**
 * Load PDF document
 * Returns: true if successful, false otherwise
 */
JNIEXPORT jboolean JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_loadPdf(JNIEnv *env, jobject thiz, jstring pdfPath) {
    const char *path = env->GetStringUTFChars(pdfPath, nullptr);
    if (path == nullptr) {
        return JNI_FALSE;
    }
    
    LOGI("Loading PDF: %s", path);
    
    // TODO: Implement MuPDF document loading
    // For now, just check if file exists
    FILE *file = fopen(path, "rb");
    if (file) {
        fclose(file);
        env->ReleaseStringUTFChars(pdfPath, path);
        return JNI_TRUE;
    }
    
    env->ReleaseStringUTFChars(pdfPath, path);
    return JNI_FALSE;
}

/**
 * Get text object at specific position
 * Returns: PDFTextObject with text content, font info, bounds, etc.
 */
JNIEXPORT jobject JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_getTextAt(JNIEnv *env, jobject thiz,
                                                              jstring pdfPath, jint pageIndex,
                                                              jfloat x, jfloat y) {
    LOGI("getTextAt: page=%d, x=%.2f, y=%.2f", pageIndex, x, y);
    
    // Call the text detection function
    return detectTextAtPosition(env, pdfPath, pageIndex, x, y);
}

/**
 * Replace text in PDF
 * Returns: true if successful
 */
JNIEXPORT jboolean JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_replaceText(JNIEnv *env, jobject thiz,
                                                                jstring pdfPath, jint pageIndex,
                                                                jstring objectId, jstring newText) {
    LOGI("replaceText: page=%d", pageIndex);
    
    return replaceTextInPDF(env, pdfPath, pageIndex, objectId, newText);
}

/**
 * Save PDF after editing
 * Returns: true if successful
 */
JNIEXPORT jboolean JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_savePdf(JNIEnv *env, jobject thiz, jstring pdfPath) {
    const char *path = env->GetStringUTFChars(pdfPath, nullptr);
    if (path == nullptr) {
        return JNI_FALSE;
    }
    
    LOGI("Saving PDF: %s", path);
    
    jboolean result = savePDF(env, pdfPath);
    
    env->ReleaseStringUTFChars(pdfPath, path);
    return result;
}

/**
 * Add pen annotation to PDF
 */
JNIEXPORT jboolean JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_addPenAnnotation(JNIEnv *env, jobject thiz,
                                                                     jstring pdfPath, jint pageIndex,
                                                                     jfloatArray pointsX, jfloatArray pointsY, jint pointCount,
                                                                     jint colorR, jint colorG, jint colorB, jfloat strokeWidth) {
    return addPenAnnotation(env, pdfPath, pageIndex, pointsX, pointsY, pointCount,
                            colorR, colorG, colorB, strokeWidth);
}

/**
 * Add highlight annotation to PDF
 */
JNIEXPORT jboolean JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_addHighlightAnnotation(JNIEnv *env, jobject thiz,
                                                                          jstring pdfPath, jint pageIndex,
                                                                          jfloat x, jfloat y, jfloat width, jfloat height,
                                                                          jint colorR, jint colorG, jint colorB, jfloat opacity) {
    return addHighlightAnnotation(env, pdfPath, pageIndex, x, y, width, height,
                                   colorR, colorG, colorB, opacity);
}

/**
 * Add underline annotation to PDF
 */
JNIEXPORT jboolean JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_addUnderlineAnnotation(JNIEnv *env, jobject thiz,
                                                                         jstring pdfPath, jint pageIndex,
                                                                         jfloat x1, jfloat y1, jfloat x2, jfloat y2,
                                                                         jint colorR, jint colorG, jint colorB, jfloat strokeWidth) {
    return addUnderlineAnnotation(env, pdfPath, pageIndex, x1, y1, x2, y2,
                                   colorR, colorG, colorB, strokeWidth);
}

/**
 * Get text quads for selection range
 */
JNIEXPORT jstring JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_getTextQuadsForSelection(JNIEnv *env, jobject thiz,
                                                                             jstring pdfPath, jint pageIndex,
                                                                             jfloat startX, jfloat startY,
                                                                             jfloat endX, jfloat endY) {
    return getTextQuadsForSelection(env, pdfPath, pageIndex, startX, startY, endX, endY);
}

/**
 * Render PDF page to image bytes (PNG format)
 */
JNIEXPORT jbyteArray JNICALL
Java_com_example_pdf_1editor_1app_PDFEditorNative_renderPageToImage(JNIEnv *env, jobject thiz,
                                                                     jstring pdfPath, jint pageIndex,
                                                                     jfloat scale) {
    return renderPageToImage(env, pdfPath, pageIndex, scale);
}

} // extern "C"

