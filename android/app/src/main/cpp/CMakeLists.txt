cmake_minimum_required(VERSION 3.22.1)
project(ai_chat_bridge)

# Force Release build type and full optimizations even during Gradle debug builds
set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG "-O3 -DNDEBUG" CACHE STRING "" FORCE)
set(CMAKE_C_FLAGS_DEBUG "-O3 -DNDEBUG" CACHE STRING "" FORCE)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)

# Stability-first flags for mobile devices that may crash with aggressive kernels.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_CPU_REPACK OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)

if(NOT DEFINED LLAMA_SRC OR NOT EXISTS "${LLAMA_SRC}")
    # ── Priority 1: project-local submodule (PrismML fork – has dflash/Bonsai + Gemma support)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/llama.cpp/CMakeLists.txt")
        set(LLAMA_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/llama.cpp")
    # ── Priority 2: sibling directory checkout
    elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../llama.cpp/CMakeLists.txt")
        set(LLAMA_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../llama.cpp")
        message(WARNING "LLAMA_SRC resolved to sibling directory; dflash/Bonsai model support may be missing. "
                        "Prefer using the project-local third_party/llama.cpp submodule.")
    # ── Priority 3: workspace fallbacks (older forks – no dflash support)
    elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../IDP/llama.cpp/CMakeLists.txt")
        set(LLAMA_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../IDP/llama.cpp")
        message(WARNING "LLAMA_SRC resolved to IDP fallback path. This version does NOT support "
                        "dflash (Bonsai) models. Use the third_party/llama.cpp submodule instead.")
    elseif(EXISTS "/home/akash/Desktop/IDP/llama.cpp/CMakeLists.txt")
        set(LLAMA_SRC "/home/akash/Desktop/IDP/llama.cpp")
        message(WARNING "LLAMA_SRC resolved to /home/akash/Desktop/IDP/llama.cpp. This version does NOT "
                        "support dflash (Bonsai) models. Use the third_party/llama.cpp submodule instead.")
    elseif(EXISTS "/home/akash/Desktop/AI/llama.cpp/CMakeLists.txt")
        set(LLAMA_SRC "/home/akash/Desktop/AI/llama.cpp")
        message(WARNING "LLAMA_SRC resolved to /home/akash/Desktop/AI/llama.cpp. This version does NOT "
                        "support dflash (Bonsai) models. Use the third_party/llama.cpp submodule instead.")
    else()
        message(FATAL_ERROR "llama.cpp directory not found! Please initialise the git submodule:\n"
                            "  git submodule update --init --recursive android/third_party/llama.cpp\n"
                            "or set -DLLAMA_SRC=<path> pointing to the PrismML fork.")
    endif()
endif()
message(STATUS "Using llama.cpp source: ${LLAMA_SRC}")

set(LLAMA_ANDROID_SRC ${LLAMA_SRC}/examples/llama.android/lib/src/main/cpp)
if(NOT EXISTS "${LLAMA_ANDROID_SRC}/logging.h")
    message(FATAL_ERROR "Android llama.cpp support files not found under ${LLAMA_ANDROID_SRC}")
endif()

add_subdirectory(${LLAMA_SRC} llama_cpp_build)

add_library(ai_chat_jni SHARED ${CMAKE_CURRENT_SOURCE_DIR}/ai_chat.cpp)
set_target_properties(ai_chat_jni PROPERTIES OUTPUT_NAME "ai-chat")

target_include_directories(
    ai_chat_jni
    PRIVATE
    ${LLAMA_SRC}
    ${LLAMA_SRC}/common
    ${LLAMA_SRC}/include
    ${LLAMA_SRC}/ggml/include
    ${LLAMA_SRC}/ggml/src
    ${LLAMA_ANDROID_SRC}
)

target_link_libraries(
    ai_chat_jni
    llama
    llama-common
    android
    log
)
