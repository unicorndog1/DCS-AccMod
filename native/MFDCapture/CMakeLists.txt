cmake_minimum_required(VERSION 3.15)
project(MFDCapture VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Source files
set(SOURCES
    src/MFDCapture.cpp
)

set(HEADERS
    include/MFDCapture.h
)

# Create library
add_library(MFDCapture STATIC ${SOURCES} ${HEADERS})

# Include directories
target_include_directories(MFDCapture PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Link DirectX libraries
target_link_libraries(MFDCapture PUBLIC
    d3d11.lib
    dxgi.lib
    dxguid.lib
)

# Set output directory
set_target_properties(MFDCapture PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

# Optional: Build test executable
option(BUILD_MFD_TESTS "Build MFD capture test programs" ON)

if(BUILD_MFD_TESTS)
    add_executable(MFDCaptureTest
        test/test_capture.cpp
    )
    
    target_link_libraries(MFDCaptureTest PRIVATE
        MFDCapture
    )
    
    set_target_properties(MFDCaptureTest PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    )
endif()

# Installation
install(TARGETS MFDCapture
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
)

install(FILES ${HEADERS}
    DESTINATION include/MFDCapture
)
