#ifndef PDF_TEXT_DETECTOR_H
#define PDF_TEXT_DETECTOR_H

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Detect text object at specific position in PDF
 * 
 * @param env JNI environment
 * @param pdfPath Path to PDF file
 * @param pageIndex Page number (0-based)
 * @param x X coordinate in PDF space
 * @param y Y coordinate in PDF space
 * @return PDFTextObject Java object or null if not found
 */
jobject detectTextAtPosition(JNIEnv *env, jstring pdfPath, jint pageIndex, jfloat x, jfloat y);

#ifdef __cplusplus
}
#endif

#endif // PDF_TEXT_DETECTOR_H

