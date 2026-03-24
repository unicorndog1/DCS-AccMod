cmake_minimum_required(VERSION 3.15)
project(DCS_AccMod_OpenXR_Layer)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find OpenXR SDK
set(OPENXR_SDK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../OpenXR-SDK" CACHE PATH "OpenXR SDK path")
if(NOT EXISTS "${OPENXR_SDK_ROOT}")
    set(OPENXR_SDK_ROOT "$ENV{OPENXR_SDK_ROOT}")
endif()

if(NOT EXISTS "${OPENXR_SDK_ROOT}")
    message(FATAL_ERROR "OpenXR SDK not found. Set OPENXR_SDK_ROOT or run download_openxr.bat")
endif()

message(STATUS "Using OpenXR SDK: ${OPENXR_SDK_ROOT}")

# Include directories
include_directories(${OPENXR_SDK_ROOT}/include)

# Source files
set(SOURCES
    src/main.cpp
    src/render.cpp
)

# Create the DLL (API Layer)
add_library(DCS_AccMod_OpenXR_Layer SHARED ${SOURCES})

# Set properties
set_target_properties(DCS_AccMod_OpenXR_Layer PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Link libraries (API layers don't link against openxr_loader, only use headers)
target_link_libraries(DCS_AccMod_OpenXR_Layer
    d3d11
    dxgi
    ws2_32
)

# Windows-specific: Export DLL functions
if(WIN32)
    target_compile_definitions(DCS_AccMod_OpenXR_Layer PRIVATE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )
endif()
