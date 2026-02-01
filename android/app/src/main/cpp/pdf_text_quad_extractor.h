#ifndef PDF_TEXT_QUAD_EXTRACTOR_H
#define PDF_TEXT_QUAD_EXTRACTOR_H

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Get text quads (bounding boxes) for text selection range
 * 
 * @param env JNI environment
 * @param pdfPath Path to PDF file
 * @param pageIndex Page number (0-based)
 * @param startX Start X coordinate in PDF space
 * @param startY Start Y coordinate in PDF space
 * @param endX End X coordinate in PDF space
 * @param endY End Y coordinate in PDF space
 * @return JSON string containing array of quads, or null if error
 */
jstring getTextQuadsForSelection(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                 jfloat startX, jfloat startY, jfloat endX, jfloat endY);

#ifdef __cplusplus
}
#endif

#endif // PDF_TEXT_QUAD_EXTRACTOR_H

