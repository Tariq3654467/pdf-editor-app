#ifndef PDF_ANNOTATION_EDITOR_H
#define PDF_ANNOTATION_EDITOR_H

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Add pen annotation (freehand path) to PDF content stream
 * 
 * @param env JNI environment
 * @param pdfPath Path to PDF file
 * @param pageIndex Page number (0-based)
 * @param pointsX Array of X coordinates in PDF space
 * @param pointsY Array of Y coordinates in PDF space
 * @param pointCount Number of points
 * @param colorR Red component (0-255)
 * @param colorG Green component (0-255)
 * @param colorB Blue component (0-255)
 * @param strokeWidth Stroke width in points
 * @return true if successful, false otherwise
 */
jboolean addPenAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                          jfloatArray pointsX, jfloatArray pointsY, jint pointCount,
                          jint colorR, jint colorG, jint colorB, jfloat strokeWidth);

/**
 * Add highlight annotation (filled rectangle) to PDF content stream
 * 
 * @param env JNI environment
 * @param pdfPath Path to PDF file
 * @param pageIndex Page number (0-based)
 * @param x X coordinate of rectangle start
 * @param y Y coordinate of rectangle start
 * @param width Width of rectangle
 * @param height Height of rectangle
 * @param colorR Red component (0-255)
 * @param colorG Green component (0-255)
 * @param colorB Blue component (0-255)
 * @param opacity Opacity (0.0-1.0)
 * @return true if successful, false otherwise
 */
jboolean addHighlightAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                jfloat x, jfloat y, jfloat width, jfloat height,
                                jint colorR, jint colorG, jint colorB, jfloat opacity);

/**
 * Add underline annotation (line) to PDF content stream
 * 
 * @param env JNI environment
 * @param pdfPath Path to PDF file
 * @param pageIndex Page number (0-based)
 * @param x1 X coordinate of line start
 * @param y1 Y coordinate of line start
 * @param x2 X coordinate of line end
 * @param y2 Y coordinate of line end
 * @param colorR Red component (0-255)
 * @param colorG Green component (0-255)
 * @param colorB Blue component (0-255)
 * @param strokeWidth Stroke width in points
 * @return true if successful, false otherwise
 */
jboolean addUnderlineAnnotation(JNIEnv *env, jstring pdfPath, jint pageIndex,
                                jfloat x1, jfloat y1, jfloat x2, jfloat y2,
                                jint colorR, jint colorG, jint colorB, jfloat strokeWidth);

#ifdef __cplusplus
}
#endif

#endif // PDF_ANNOTATION_EDITOR_H

