#include "joystick_monitor.h"
#include <chrono>
#include <cstring>
#include <cstdio>
#include <algorithm>

#pragma comment(lib, "dinput8.lib")
#pragma comment(lib, "dxguid.lib")
#pragma comment(lib, "ws2_32.lib")

JoystickMonitor::JoystickMonitor() {
    // Initialize Winsock
    WSADATA wsaData;
    WSAStartup(MAKEWORD(2, 2), &wsaData);
}

JoystickMonitor::~JoystickMonitor() {
    Stop();
    CleanupSocket();
    CleanupDirectInput();
    WSACleanup();
}

bool JoystickMonitor::Initialize(int joystickIndex) {
    m_targetJoystickIndex = joystickIndex;
    
    if (!InitializeDirectInput()) {
        return false;
    }
    
    if (!InitializeSocket()) {
        CleanupDirectInput();
        return false;
    }
    
    return true;
}

BOOL CALLBACK JoystickMonitor::EnumJoysticksCallback(const DIDEVICEINSTANCE* pdidInstance, VOID* pContext) {
    JoystickMonitor* monitor = static_cast<JoystickMonitor*>(pContext);
    
    if (monitor->m_currentJoystickIndex == monitor->m_targetJoystickIndex) {
        // This is the joystick we want, create device
        HRESULT hr = monitor->m_pDI->CreateDevice(pdidInstance->guidInstance, &monitor->m_pJoystick, nullptr);
        if (SUCCEEDED(hr)) {
            return DIENUM_STOP;
        }
    }
    
    monitor->m_currentJoystickIndex++;
    return DIENUM_CONTINUE;
}

bool JoystickMonitor::InitializeDirectInput() {
    HRESULT hr = DirectInput8Create(GetModuleHandle(nullptr), DIRECTINPUT_VERSION, 
                                     IID_IDirectInput8, (VOID**)&m_pDI, nullptr);
    if (FAILED(hr)) {
        return false;
    }
    
    m_currentJoystickIndex = 0;
    hr = m_pDI->EnumDevices(DI8DEVCLASS_GAMECTRL, EnumJoysticksCallback, this, DIEDFL_ATTACHEDONLY);
    if (FAILED(hr) || !m_pJoystick) {
        return false;
    }
    
    hr = m_pJoystick->SetDataFormat(&c_dfDIJoystick2);
    if (FAILED(hr)) {
        return false;
    }
    
    hr = m_pJoystick->SetCooperativeLevel(nullptr, DISCL_NONEXCLUSIVE | DISCL_BACKGROUND);
    if (FAILED(hr)) {
        return false;
    }
    
    // Get device capabilities
    DIDEVCAPS caps;
    caps.dwSize = sizeof(DIDEVCAPS);
    hr = m_pJoystick->GetCapabilities(&caps);
    if (SUCCEEDED(hr)) {
        m_lastButtonState.resize(caps.dwButtons, 0);
        m_lastAxisState.resize(caps.dwAxes, 0.0f);
        m_axisLastSent.resize(caps.dwAxes, 0.0f);
        m_axisPending.resize(caps.dwAxes, false);
    }
    
    hr = m_pJoystick->Acquire();
    if (FAILED(hr)) {
        return false;
    }
    
    return true;
}

void JoystickMonitor::CleanupDirectInput() {
    if (m_pJoystick) {
        m_pJoystick->Unacquire();
        m_pJoystick->Release();
        m_pJoystick = nullptr;
    }
    
    if (m_pDI) {
        m_pDI->Release();
        m_pDI = nullptr;
    }
}

bool JoystickMonitor::InitializeSocket() {
    m_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (m_socket == INVALID_SOCKET) {
        return false;
    }
    
    m_serverAddr.sin_family = AF_INET;
    m_serverAddr.sin_port = htons(7778);
    m_serverAddr.sin_addr.s_addr = inet_addr("127.0.0.1");
    
    return true;
}

void JoystickMonitor::CleanupSocket() {
    if (m_socket != INVALID_SOCKET) {
        closesocket(m_socket);
        m_socket = INVALID_SOCKET;
    }
}

void JoystickMonitor::SendUDP(const char* message) {
    if (m_socket != INVALID_SOCKET) {
        sendto(m_socket, message, (int)strlen(message), 0, 
               (sockaddr*)&m_serverAddr, sizeof(m_serverAddr));
    }
}

void JoystickMonitor::Start() {
    if (m_running) {
        return;
    }
    
    m_stopRequested = false;
    m_running = true;
    m_thread = std::thread(&JoystickMonitor::MonitorThread, this);
}

void JoystickMonitor::Stop() {
    if (!m_running) {
        return;
    }
    
    m_stopRequested = true;
    if (m_thread.joinable()) {
        m_thread.join();
    }
    m_running = false;
}

void JoystickMonitor::MonitorThread() {
    DIJOYSTATE2 js;
    auto lastTime = std::chrono::high_resolution_clock::now();
    
    while (!m_stopRequested) {
        HRESULT hr = m_pJoystick->Poll();
        if (FAILED(hr)) {
            hr = m_pJoystick->Acquire();
            if (FAILED(hr)) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
                continue;
            }
        }
        
        hr = m_pJoystick->GetDeviceState(sizeof(DIJOYSTATE2), &js);
        if (FAILED(hr)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }
        
        auto now = std::chrono::high_resolution_clock::now();
        float deltaTime = std::chrono::duration<float>(now - lastTime).count();
        
        // Check buttons
        for (size_t i = 0; i < m_lastButtonState.size(); ++i) {
            BYTE current = (js.rgbButtons[i] & 0x80) ? 1 : 0;
            BYTE last = m_lastButtonState[i];
            
            if (current && !last) {
                char msg[64];
                snprintf(msg, sizeof(msg), "BTN_%zu_PRESSED", i);
                SendUDP(msg);
            }
            else if (!current && last) {
                char msg[64];
                snprintf(msg, sizeof(msg), "BTN_%zu_RELEASED", i);
                SendUDP(msg);
            }
            
            m_lastButtonState[i] = current;
        }
        
        // Check axes
        LONG* axisValues[] = { &js.lX, &js.lY, &js.lZ, &js.lRx, &js.lRy, &js.lRz };
        size_t numAxes = std::min(size_t(6), m_lastAxisState.size());
        
        for (size_t i = 0; i < numAxes; ++i) {
            float current = (*axisValues[i] - 32767.5f) / 32767.5f;  // Normalize to -1.0 to 1.0
            
            if (fabs(current - m_lastAxisState[i]) > AXIS_THRESHOLD) {
                m_lastAxisState[i] = current;
                m_axisPending[i] = true;
            }
            
            if (m_axisPending[i] && deltaTime >= UPDATE_FREQ) {
                char msg[64];
                snprintf(msg, sizeof(msg), "AXIS_%zu_%.4f", i, current);
                SendUDP(msg);
                m_axisLastSent[i] = current;
                m_axisPending[i] = false;
            }
        }
        
        if (deltaTime >= UPDATE_FREQ) {
            lastTime = now;
        }
        
        std::this_thread::sleep_for(std::chrono::milliseconds(8));  // ~120Hz
    }
}
