#pragma once

#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#include <thread>
#include <atomic>
#include <vector>
#include <winsock2.h>

class JoystickMonitor {
public:
    JoystickMonitor();
    ~JoystickMonitor();

    bool Initialize(int joystickIndex = 1);
    void Start();
    void Stop();
    bool IsRunning() const { return m_running; }

private:
    void MonitorThread();
    bool InitializeDirectInput();
    void CleanupDirectInput();
    bool InitializeSocket();
    void CleanupSocket();
    void SendUDP(const char* message);
    
    static BOOL CALLBACK EnumJoysticksCallback(const DIDEVICEINSTANCE* pdidInstance, VOID* pContext);

    LPDIRECTINPUT8 m_pDI = nullptr;
    LPDIRECTINPUTDEVICE8 m_pJoystick = nullptr;
    SOCKET m_socket = INVALID_SOCKET;
    sockaddr_in m_serverAddr = {};
    
    std::thread m_thread;
    std::atomic<bool> m_running{ false };
    std::atomic<bool> m_stopRequested{ false };
    
    int m_targetJoystickIndex = 1;
    int m_currentJoystickIndex = 0;
    
    std::vector<BYTE> m_lastButtonState;
    std::vector<float> m_lastAxisState;
    std::vector<float> m_axisLastSent;
    std::vector<bool> m_axisPending;
    
    static constexpr float UPDATE_FREQ = 1.0f / 120.0f;
    static constexpr float AXIS_THRESHOLD = 0.001f;
};
