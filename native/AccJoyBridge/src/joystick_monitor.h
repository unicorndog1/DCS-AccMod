#pragma once

#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#include <thread>
#include <atomic>
#include <vector>
#include <string>
#include <winsock2.h>
#include <chrono>

class JoystickMonitor {
public:
    struct DeviceInfo {
        int index = 0;
        std::string guid;
        std::string instanceName;
        std::string productName;
    };

    JoystickMonitor();
    ~JoystickMonitor();

    bool Initialize(int joystickIndex = -1);
    void Start();
    void Stop();
    bool IsRunning() const { return m_running; }

    static std::vector<DeviceInfo> EnumerateAttachedDevices();

private:
    struct DeviceContext {
        DeviceInfo info;
        LPDIRECTINPUTDEVICE8 device = nullptr;
        std::vector<BYTE> lastButtonState;
        std::vector<float> lastAxisState;
        std::vector<float> axisLastSent;
        std::vector<bool> axisPending;
    };

    void MonitorThread();
    bool InitializeDirectInput();
    bool EnumerateDeviceInstances();
    bool InitializeJoystickDevices(int preferredIndex);
    bool ConfigureJoystickDevice(DeviceContext& ctx);
    bool TryRecoverJoystick(HRESULT failureHr);
    void ReleaseJoystickDevices();
    void CleanupDirectInput();
    bool InitializeSocket();
    void CleanupSocket();
    void SendUDP(const std::string& message);
    void LogLine(const char* fmt, ...);
    static std::string GuidToString(REFGUID guid);
    static std::string NarrowFromTChar(const TCHAR* value);
    static BOOL CALLBACK EnumJoysticksCallback(const DIDEVICEINSTANCE* pdidInstance, VOID* pContext);
    
    LPDIRECTINPUT8 m_pDI = nullptr;
    SOCKET m_socket = INVALID_SOCKET;
    sockaddr_in m_serverAddr = {};
    
    std::thread m_thread;
    std::atomic<bool> m_running{ false };
    std::atomic<bool> m_stopRequested{ false };
    
    int m_targetJoystickIndex = -1;
    std::chrono::steady_clock::time_point m_lastRecoveryLog;
    std::vector<DIDEVICEINSTANCE> m_enumDevices;
    std::vector<DeviceContext> m_devices;
    
    static constexpr float UPDATE_FREQ = 1.0f / 120.0f;
    static constexpr float AXIS_THRESHOLD = 0.001f;
};
