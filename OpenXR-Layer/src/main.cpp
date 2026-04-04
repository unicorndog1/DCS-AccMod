// DCS AccMod OpenXR Layer - Main DLL entry point
// Handles UDP communication and layer lifecycle

#include "common.h"
#include <cstdio>
#include <cstring>
#include <share.h>

// Log file handle
static FILE* g_logFile = nullptr;

// Logging implementation
void LogMessage(const char* message) {
    if (!g_logFile) {
        char logPath[MAX_PATH];
        GetTempPathA(MAX_PATH, logPath);
        strcat_s(logPath, "DCS_AccMod_OpenXR.log");
        g_logFile = _fsopen(logPath, "a", _SH_DENYNO); // shared read access
    }
    
    if (g_logFile) {
        fprintf(g_logFile, "%s\n", message);
        fflush(g_logFile);
    }
}

void LogFormat(const char* format, ...) {
    if (!g_logFile) {
        char logPath[MAX_PATH];
        GetTempPathA(MAX_PATH, logPath);
        strcat_s(logPath, "DCS_AccMod_OpenXR.log");
        g_logFile = _fsopen(logPath, "a", _SH_DENYNO); // shared read access
    }
    
    if (g_logFile) {
        va_list args;
        va_start(args, format);
        vfprintf(g_logFile, format, args);
        va_end(args);
        fprintf(g_logFile, "\n");
        fflush(g_logFile);
    }
}

// Global layer state
LayerState g_state;

// Next layer function pointers
PFN_xrGetInstanceProcAddr g_nextGetInstanceProcAddr = nullptr;
PFN_xrCreateSession g_nextCreateSession = nullptr;
PFN_xrDestroySession g_nextDestroySession = nullptr;
PFN_xrEndFrame g_nextEndFrame = nullptr;
PFN_xrCreateSwapchain g_nextCreateSwapchain = nullptr;
PFN_xrDestroySwapchain g_nextDestroySwapchain = nullptr;
PFN_xrEnumerateSwapchainImages g_nextEnumerateSwapchainImages = nullptr;
PFN_xrAcquireSwapchainImage g_nextAcquireSwapchainImage = nullptr;
PFN_xrWaitSwapchainImage g_nextWaitSwapchainImage = nullptr;
PFN_xrReleaseSwapchainImage g_nextReleaseSwapchainImage = nullptr;
PFN_xrCreateReferenceSpace g_nextCreateReferenceSpace = nullptr;
PFN_xrDestroySpace g_nextDestroySpace = nullptr;

// Constructor for LayerState
LayerState::LayerState() {
    InitializeCriticalSection(&circlesMutex);
    udpSocket = INVALID_SOCKET;
    udpInitialized = false;
    udpThread = nullptr;
    running = false;
    quadTanHalfFov = 1.0f;  // default: 90° vertical FOV
    quadAspect = 1.778f;    // default: 16:9
    quadEyeVisibility = XR_EYE_VISIBILITY_BOTH;
    quadDistance = 1.0f;    // default: 1 meter
}

// UDP receiver thread
DWORD WINAPI UDPReceiverThread(LPVOID param) {
    LogMessage("UDP receiver thread started");
    
    char buffer[4096];
    while (g_state.running) {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(g_state.udpSocket, &readfds);
        
        timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 100000; // 100ms timeout
        
        int result = select(0, &readfds, nullptr, nullptr, &timeout);
        if (result > 0) {
            int bytesRead = recv(g_state.udpSocket, buffer, sizeof(buffer) - 1, 0);
            if (bytesRead > 0) {
                buffer[bytesRead] = '\0';
                
                // Parse UDP packet
                // Format: "C,x,y,radius,r,g,b,a,filled" for circle
                //         "A" to clear all circles
                //         "U,x,y,radius,r,g,b,a,filled" to update/add
                
                if (buffer[0] == 'A') {
                    // Clear all circles
                    CriticalSectionLock lock(g_state.circlesMutex);
                    g_state.circles.clear();
                }
                else if (buffer[0] == 'V') {
                    // View config: "V,tanHalfFov,aspect,eyeVis,distance"
                    // eyeVis: 0=both, 1=left, 2=right
                    // distance: world-space distance for quad positioning
                    float tanHalfFov = 0.0f, aspect = 0.0f, distance = 0.0f;
                    int eyeVis = 0;
                    int parsed = sscanf_s(buffer + 2, "%f,%f,%d,%f", &tanHalfFov, &aspect, &eyeVis, &distance);
                    if (parsed >= 2 && tanHalfFov > 0.1f && aspect > 0.1f) {
                        {
                            CriticalSectionLock lock(g_state.circlesMutex);
                            g_state.quadTanHalfFov = tanHalfFov;
                            g_state.quadAspect = aspect;
                            if (parsed >= 3 && eyeVis >= 0 && eyeVis <= 2) {
                                g_state.quadEyeVisibility = (XrEyeVisibility)eyeVis;
                            }
                            if (parsed >= 4 && distance > 0.01f) {
                                g_state.quadDistance = distance;
                            }
                        }
                        LogFormat("Updated quad config: tanHalfFov=%.4f aspect=%.4f eye=%d distance=%.4f", tanHalfFov, aspect, (int)g_state.quadEyeVisibility, g_state.quadDistance);
                    }
                }
                else if (buffer[0] == 'B') {
                    // Batched circles: "B,count,circle1;circle2;circle3;..."
                    // Each circle has format: "x,y,radius,r,g,b,a,filled,thickness,labelR,labelG,labelB,labelA,label"
                    int count = 0;
                    char* dataStart = strchr(buffer + 2, ',');
                    if (dataStart) {
                        sscanf_s(buffer + 2, "%d", &count);
                        dataStart++; // Skip the comma after count
                        
                        if (count > 0 && count < 100) { // Sanity check
                            CriticalSectionLock lock(g_state.circlesMutex);
                            
                            char* context = nullptr;
                            char* circleStr = strtok_s(dataStart, ";", &context);
                            int parsedCount = 0;
                            
                            while (circleStr != nullptr && parsedCount < count) {
                                CircleData circle;
                                int filled;
                                float thickness = 0.0f;
                                char tempLabel[256] = {0};
                                
                                // Try extended format first
                                int parsed = sscanf_s(circleStr, "%f,%f,%f,%f,%f,%f,%f,%d,%f,%f,%f,%f,%f,%255[^\n]",
                                            &circle.x, &circle.y, &circle.radius,
                                            &circle.r, &circle.g, &circle.b, &circle.a, &filled, &thickness,
                                            &circle.labelR, &circle.labelG, &circle.labelB, &circle.labelA,
                                            tempLabel, (unsigned)sizeof(tempLabel));

                                bool parsedExtendedPacket = (parsed >= 13);
                                if (!parsedExtendedPacket) {
                                    memset(tempLabel, 0, sizeof(tempLabel));
                                    parsed = sscanf_s(circleStr, "%f,%f,%f,%f,%f,%f,%f,%d,%f,%255[^\n]",
                                                &circle.x, &circle.y, &circle.radius,
                                                &circle.r, &circle.g, &circle.b, &circle.a, &filled, &thickness,
                                                tempLabel, (unsigned)sizeof(tempLabel));
                                }
                                
                                if (parsed >= 8) {
                                    circle.filled = (filled != 0);
                                    circle.thickness = thickness;

                                    if (!parsedExtendedPacket) {
                                        circle.labelR = circle.r;
                                        circle.labelG = circle.g;
                                        circle.labelB = circle.b;
                                        circle.labelA = circle.a;
                                    }
                                    
                                    if ((parsedExtendedPacket && parsed >= 14) || (!parsedExtendedPacket && parsed >= 10)) {
                                        strncpy_s(circle.label, sizeof(circle.label), tempLabel, _TRUNCATE);
                                    } else {
                                        circle.label[0] = '\\0';
                                    }
                                    
                                    g_state.circles.push_back(circle);
                                    parsedCount++;
                                }
                                
                                circleStr = strtok_s(nullptr, ";", &context);
                            }
                            
                            LogFormat("Received batch: %d circles", parsedCount);
                        }
                    }
                }
                else if (buffer[0] == 'C' || buffer[0] == 'U') {
                    // Parse circle data:
                    // "C,x,y,radius,r,g,b,a,filled,thickness,labelR,labelG,labelB,labelA,label"
                    // Fallback for older senders:
                    // "C,x,y,radius,r,g,b,a,filled,thickness,label"
                    CircleData circle;
                    int filled;
                    float thickness = 0.0f;
                    char tempLabel[256] = {0};
                    
                    int parsed = sscanf_s(buffer + 2, "%f,%f,%f,%f,%f,%f,%f,%d,%f,%f,%f,%f,%f,%255[^\n]",
                                &circle.x, &circle.y, &circle.radius,
                                &circle.r, &circle.g, &circle.b, &circle.a, &filled, &thickness,
                                &circle.labelR, &circle.labelG, &circle.labelB, &circle.labelA,
                                tempLabel, (unsigned)sizeof(tempLabel));

                    bool parsedExtendedPacket = (parsed >= 13);
                    if (!parsedExtendedPacket) {
                        memset(tempLabel, 0, sizeof(tempLabel));
                        parsed = sscanf_s(buffer + 2, "%f,%f,%f,%f,%f,%f,%f,%d,%f,%255[^\n]",
                                    &circle.x, &circle.y, &circle.radius,
                                    &circle.r, &circle.g, &circle.b, &circle.a, &filled, &thickness,
                                    tempLabel, (unsigned)sizeof(tempLabel));
                    }
                    
                    if (parsed >= 8) {
                        circle.filled = (filled != 0);
                        circle.thickness = thickness;

                        if (!parsedExtendedPacket) {
                            circle.labelR = circle.r;
                            circle.labelG = circle.g;
                            circle.labelB = circle.b;
                            circle.labelA = circle.a;
                        }
                        
                        if ((parsedExtendedPacket && parsed >= 14) || (!parsedExtendedPacket && parsed >= 10)) {
                            strncpy_s(circle.label, sizeof(circle.label), tempLabel, _TRUNCATE);
                        } else {
                            circle.label[0] = '\0';
                        }
                        
                        CriticalSectionLock lock(g_state.circlesMutex);
                        if (buffer[0] == 'C') {
                            g_state.circles.push_back(circle);
                        } else {
                            // Update: replace or add
                            if (!g_state.circles.empty()) {
                                g_state.circles[0] = circle;
                            } else {
                                g_state.circles.push_back(circle);
                            }
                        }
                        
                        LogFormat("Received circle: x=%.2f y=%.2f r=%.3f a=%.2f filled=%d t=%.4f label=%s",
                                 circle.x, circle.y, circle.radius, circle.a, filled, circle.thickness, circle.label);
                    }
                }
            }
        }
    }
    
    LogMessage("UDP receiver thread exiting");
    return 0;
}

// Initialize UDP socket
bool InitializeUDP() {
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        LogMessage("WSAStartup failed");
        return false;
    }
    
    g_state.udpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (g_state.udpSocket == INVALID_SOCKET) {
        LogMessage("Socket creation failed");
        WSACleanup();
        return false;
    }
    
    // Bind to port 7779
    sockaddr_in serverAddr = {};
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = INADDR_ANY;
    serverAddr.sin_port = htons(7779);
    
    if (bind(g_state.udpSocket, (sockaddr*)&serverAddr, sizeof(serverAddr)) == SOCKET_ERROR) {
        LogMessage("Bind failed");
        closesocket(g_state.udpSocket);
        WSACleanup();
        return false;
    }
    
    LogMessage("UDP socket bound to port 7779");
    
    g_state.running = true;
    g_state.udpThread = CreateThread(nullptr, 0, UDPReceiverThread, nullptr, 0, nullptr);
    if (!g_state.udpThread) {
        LogMessage("Failed to create UDP thread");
        closesocket(g_state.udpSocket);
        WSACleanup();
        return false;
    }
    
    g_state.udpInitialized = true;
    LogMessage("UDP initialized successfully");
    return true;
}

// Cleanup UDP
void ShutdownUDP() {
    if (g_state.udpInitialized) {
        g_state.running = false;
        
        if (g_state.udpThread) {
            WaitForSingleObject(g_state.udpThread, 1000);
            CloseHandle(g_state.udpThread);
            g_state.udpThread = nullptr;
        }
        
        if (g_state.udpSocket != INVALID_SOCKET) {
            closesocket(g_state.udpSocket);
            g_state.udpSocket = INVALID_SOCKET;
        }
        
        WSACleanup();
        g_state.udpInitialized = false;
        LogMessage("UDP shutdown complete");
    }
}

// DLL entry point
BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID reserved) {
    switch (reason) {
    case DLL_PROCESS_ATTACH:
        LogMessage("=== DCS AccMod OpenXR Layer Loaded ===");
        InitializeUDP();
        break;
        
    case DLL_PROCESS_DETACH:
        ShutdownUDP();
        DeleteCriticalSection(&g_state.circlesMutex);
        LogMessage("=== DCS AccMod OpenXR Layer Unloaded ===");
        if (g_logFile) {
            fclose(g_logFile);
            g_logFile = nullptr;
        }
        break;
    }
    return TRUE;
}
