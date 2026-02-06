cmake_minimum_required(VERSION 3.22.1)
project("pdf_editor_native")

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# MuPDF libraries location (pre-built .so files in libs/)
set(MUPDF_LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../libs")

# Include directories
# MuPDF headers are in main/include/mupdf/
# The include path should point to the parent of 'mupdf' directory
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
    ${CMAKE_CURRENT_SOURCE_DIR}/../include/mupdf
)

# JNI interface
add_library(pdf_editor_native SHARED
    pdf_editor_jni.cpp
    pdf_text_editor.cpp
    pdf_text_detector.cpp
    pdf_annotation_editor.cpp
    pdf_text_quad_extractor.cpp
    pdf_page_renderer.cpp
)

# Add library search path BEFORE linking
# This must be called before target_link_libraries
link_directories(${MUPDF_LIBS_DIR}/${ANDROID_ABI})

# Link MuPDF Java wrapper library
# The library is in architecture-specific folders in libs/
# Use full path to ensure linker finds it
target_link_libraries(pdf_editor_native
    ${MUPDF_LIBS_DIR}/${ANDROID_ABI}/libmupdf_java.so
    log
    android
)

