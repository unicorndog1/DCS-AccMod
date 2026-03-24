cmake_minimum_required(VERSION 3.15)
project(AccJoyBridge VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find Lua (optional, use manual paths if not found)
find_package(Lua)
if(NOT LUA_FOUND)
    message(STATUS "Lua not found via find_package, using manual configuration")
    # Manual Lua configuration - adjust these paths as needed
    set(LUA_INCLUDE_DIR "" CACHE PATH "Lua include directory")
    set(LUA_LIBRARIES "" CACHE FILEPATH "Lua library (optional for runtime loading)")
    
    # If no paths provided, we'll compile without Lua headers and use runtime loading
    if(NOT LUA_INCLUDE_DIR)
        message(STATUS "No Lua include path specified - using minimal Lua declarations")
        set(USE_MINIMAL_LUA TRUE)
    endif()
endif()

# Source files
set(SOURCES
    src/main.cpp
    src/joystick_monitor.cpp
)

set(HEADERS
    src/joystick_monitor.h
)

# Create the DLL
add_library(AccJoyBridge SHARED ${SOURCES} ${HEADERS})

# Include directories
if(USE_MINIMAL_LUA)
    target_include_directories(AccJoyBridge PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    target_compile_definitions(AccJoyBridge PRIVATE USE_MINIMAL_LUA)
else()
    target_include_directories(AccJoyBridge PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${LUA_INCLUDE_DIR}
    )
endif()

# Link libraries
if(LUA_LIBRARIES)
    target_link_libraries(AccJoyBridge PRIVATE
        ${LUA_LIBRARIES}
        dinput8
        dxguid
        ws2_32
    )
else()
    target_link_libraries(AccJoyBridge PRIVATE
        dinput8
        dxguid
        ws2_32
    )
endif()

# Set output directory
set_target_properties(AccJoyBridge PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    OUTPUT_NAME "AccJoyBridge"
)

# Windows-specific settings
if(WIN32)
    target_compile_definitions(AccJoyBridge PRIVATE
        _WIN32_WINNT=0x0601
        NOMINMAX
        WIN32_LEAN_AND_MEAN
    )
endif()
