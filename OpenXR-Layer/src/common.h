// Common header for OpenXR layer
// Shared types, declarations, and includes

#pragma once

// Windows and networking headers (must come before OpenXR)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

// COM and DirectX
#include <unknwn.h>
#include <d3d11.h>
#include <dxgi.h>

// OpenXR headers (must come after D3D11)
#define XR_USE_GRAPHICS_API_D3D11
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include <openxr/openxr_loader_negotiation.h>

// Standard library
#include <vector>
#include <string>
#include <cstdio>

// RAII wrapper for Windows CRITICAL_SECTION (avoids VS2026 std::mutex header bugs)
class CriticalSectionLock {
    CRITICAL_SECTION& cs;
public:
    explicit CriticalSectionLock(CRITICAL_SECTION& critSec) : cs(critSec) {
        EnterCriticalSection(&cs);
    }
    ~CriticalSectionLock() {
        LeaveCriticalSection(&cs);
    }
    CriticalSectionLock(const CriticalSectionLock&) = delete;
    CriticalSectionLock& operator=(const CriticalSectionLock&) = delete;
};

// Circle/dot data structure for UDP communication
struct CircleData {
    float x;           // Screen X coordinate (0.0 to 1.0, normalized)
    float y;           // Screen Y coordinate (0.0 to 1.0, normalized)
    float radius;      // Radius (normalized, same scale as x/y)
    float r, g, b, a;  // Color RGBA (0.0 to 1.0)
    bool filled;       // true = filled circle, false = hollow ring
    float thickness;   // Ring thickness (normalized, same scale as radius)
    char label[64];    // Text label to display above circle (unit type)
    
    CircleData() : x(0), y(0), radius(0), r(0), g(0), b(0), a(0), filled(false), thickness(0) {
        label[0] = '\0';
    }
};

// Global state
struct LayerState {
    std::vector<CircleData> circles;
    CRITICAL_SECTION circlesMutex;  // Using Windows CRITICAL_SECTION instead of std::mutex
    SOCKET udpSocket;
    bool udpInitialized;
    HANDLE udpThread;
    volatile bool running;
    float quadTanHalfFov;  // tan(verticalFOV/2) from LUA — used to size the quad
    float quadAspect;      // width/height aspect ratio from LUA
    XrEyeVisibility quadEyeVisibility; // Which eye(s) see the overlay (default: BOTH)
    float quadDistance;    // Distance in world coordinates for quad positioning (from LUA)
    
    LayerState();
};

// Global state instance (defined in main.cpp)
extern LayerState g_state;

// Next layer's dispatch table (defined in main.cpp)
extern PFN_xrGetInstanceProcAddr g_nextGetInstanceProcAddr;
extern PFN_xrCreateSession g_nextCreateSession;
extern PFN_xrDestroySession g_nextDestroySession;
extern PFN_xrEndFrame g_nextEndFrame;
extern PFN_xrCreateSwapchain g_nextCreateSwapchain;
extern PFN_xrDestroySwapchain g_nextDestroySwapchain;
extern PFN_xrEnumerateSwapchainImages g_nextEnumerateSwapchainImages;
extern PFN_xrAcquireSwapchainImage g_nextAcquireSwapchainImage;
extern PFN_xrWaitSwapchainImage g_nextWaitSwapchainImage;
extern PFN_xrReleaseSwapchainImage g_nextReleaseSwapchainImage;
extern PFN_xrCreateReferenceSpace g_nextCreateReferenceSpace;
extern PFN_xrDestroySpace g_nextDestroySpace;

// Logging functions (defined in main.cpp)
void LogMessage(const char* message);
void LogFormat(const char* format, ...);

template<typename... Args>
void LogFormat(const char* format, Args... args) {
    char buffer[1024];
    snprintf(buffer, sizeof(buffer), format, args...);
    LogMessage(buffer);
}
