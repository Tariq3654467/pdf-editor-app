cmake_minimum_required(VERSION 3.22.1)
project("pdf_editor_native")

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
)

# Note: All C++ source files have been removed
# This CMakeLists.txt is kept for reference but will not build anything

