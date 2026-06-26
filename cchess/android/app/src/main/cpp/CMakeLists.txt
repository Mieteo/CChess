cmake_minimum_required(VERSION 3.22.1)

project("eleeye_engine" LANGUAGES CXX)

# ─── Compiler settings ───────────────────────────────────────────────────────
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# CCHESS_A3800: use ElephantEye in library mode (result via Search.mvResult,
#               no stdin/stdout UCI loop).
# NDEBUG: disable assert() calls for release performance.
add_compile_definitions(CCHESS_A3800 NDEBUG)

# ─── ElephantEye source files ─────────────────────────────────────────────────
set(ELEEYE_SRCS
    eleeye/pregen.cpp
    eleeye/position.cpp
    eleeye/genmoves.cpp
    eleeye/hash.cpp
    eleeye/book.cpp
    eleeye/movesort.cpp
    eleeye/preeval.cpp
    eleeye/evaluate.cpp
    eleeye/search.cpp
)

# Suppress warnings from third-party source so build output stays clean.
set_source_files_properties(${ELEEYE_SRCS}
    PROPERTIES COMPILE_FLAGS "-w"
)

# ─── Shared library (loaded by Dart FFI) ─────────────────────────────────────
add_library(
    eleeye_engine
    SHARED
    eleeye_ffi.cpp
    ${ELEEYE_SRCS}
)

# Allow ElephantEye headers to resolve "../base/base.h" from inside eleeye/.
target_include_directories(eleeye_engine PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# Link Android log library (useful for future debugging).
find_library(log-lib log)
target_link_libraries(eleeye_engine ${log-lib})
