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
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../llama.cpp")
        set(LLAMA_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../llama.cpp")
    elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../IDP/llama.cpp")
        set(LLAMA_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../IDP/llama.cpp")
    elseif(EXISTS "/home/akash/Desktop/IDP/llama.cpp")
        set(LLAMA_SRC "/home/akash/Desktop/IDP/llama.cpp")
    elseif(EXISTS "/home/akash/Desktop/AI/llama.cpp")
        set(LLAMA_SRC "/home/akash/Desktop/AI/llama.cpp")
    else()
        message(FATAL_ERROR "llama.cpp directory not found! Please clone llama.cpp or set LLAMA_SRC.")
    endif()
endif()
set(LLAMA_ANDROID_SRC ${LLAMA_SRC}/examples/llama.android/lib/src/main/cpp)

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
    common
    android
    log
)
