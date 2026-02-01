#ifndef PDF_TEXT_EDITOR_H
#define PDF_TEXT_EDITOR_H

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Replace text in PDF content stream
 * 
 * @param env JNI environment
 * @param pdfPath Path to PDF file
 * @param pageIndex Page number (0-based)
 * @param objectId PDF object identifier
 * @param newText New text content
 * @return true if successful, false otherwise
 */
jboolean replaceTextInPDF(JNIEnv *env, jstring pdfPath, jint pageIndex,
                          jstring objectId, jstring newText);

/**
 * Save PDF document after editing
 * 
 * @param env JNI environment
 * @param pdfPath Path to PDF file
 * @return true if successful, false otherwise
 */
jboolean savePDF(JNIEnv *env, jstring pdfPath);

#ifdef __cplusplus
}
#endif

#endif // PDF_TEXT_EDITOR_H

