#include "joystick_monitor.h"
#include <chrono>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <cstdarg>
#include <cmath>
#include <windows.h>
#include <objbase.h>

#pragma comment(lib, "dinput8.lib")
#pragma comment(lib, "dxguid.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "ole32.lib")

JoystickMonitor::JoystickMonitor() {
    // Initialize Winsock
    WSADATA wsaData;
    WSAStartup(MAKEWORD(2, 2), &wsaData);
    m_lastRecoveryLog = std::chrono::steady_clock::now() - std::chrono::seconds(30);
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

std::string JoystickMonitor::NarrowFromTChar(const TCHAR* value) {
    if (!value) {
        return std::string();
    }
#if defined(UNICODE) || defined(_UNICODE)
    int required = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    if (required <= 1) {
        return std::string();
    }
    std::string out(static_cast<size_t>(required - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, -1, &out[0], required, nullptr, nullptr);
    return out;
#else
    return std::string(value);
#endif
}

std::string JoystickMonitor::GuidToString(REFGUID guid) {
    wchar_t buffer[64] = {};
    if (StringFromGUID2(guid, buffer, 64) <= 0) {
        return std::string();
    }
    int required = WideCharToMultiByte(CP_UTF8, 0, buffer, -1, nullptr, 0, nullptr, nullptr);
    if (required <= 1) {
        return std::string();
    }
    std::string out(static_cast<size_t>(required - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, buffer, -1, &out[0], required, nullptr, nullptr);
    return out;
}

BOOL CALLBACK JoystickMonitor::EnumJoysticksCallback(const DIDEVICEINSTANCE* pdidInstance, VOID* pContext) {
    JoystickMonitor* monitor = static_cast<JoystickMonitor*>(pContext);
    if (!monitor || !pdidInstance) {
        return DIENUM_CONTINUE;
    }

    monitor->m_enumDevices.push_back(*pdidInstance);
    return DIENUM_CONTINUE;
}

bool JoystickMonitor::InitializeDirectInput() {
    HRESULT hr = DirectInput8Create(GetModuleHandle(nullptr), DIRECTINPUT_VERSION, 
                                     IID_IDirectInput8, (VOID**)&m_pDI, nullptr);
    if (FAILED(hr)) {
        LogLine("DirectInput8Create failed hr=0x%08lX", (unsigned long)hr);
        return false;
    }

    return InitializeJoystickDevices(m_targetJoystickIndex);
}

bool JoystickMonitor::EnumerateDeviceInstances() {
    m_enumDevices.clear();
    if (!m_pDI) {
        return false;
    }

    HRESULT hr = m_pDI->EnumDevices(DI8DEVCLASS_GAMECTRL, EnumJoysticksCallback, this, DIEDFL_ATTACHEDONLY);
    return SUCCEEDED(hr) && !m_enumDevices.empty();
}

bool JoystickMonitor::InitializeJoystickDevices(int preferredIndex) {
    ReleaseJoystickDevices();

    if (!EnumerateDeviceInstances()) {
        LogLine("No joystick devices found during enumeration");
        return false;
    }

    std::vector<int> selectedIndices;
    if (preferredIndex < 0) {
        for (size_t i = 0; i < m_enumDevices.size(); ++i) {
            selectedIndices.push_back(static_cast<int>(i));
        }
    } else if (preferredIndex < static_cast<int>(m_enumDevices.size())) {
        selectedIndices.push_back(preferredIndex);
    } else if (!m_enumDevices.empty()) {
        selectedIndices.push_back(0);
        LogLine("Preferred joystick index %d missing; fell back to index 0", preferredIndex);
    }

    if (selectedIndices.empty()) {
        LogLine("No selected joystick devices after filtering");
        return false;
    }

    bool hasAtLeastOne = false;
    for (int index : selectedIndices) {
        if (index < 0 || index >= static_cast<int>(m_enumDevices.size())) {
            continue;
        }

        DeviceContext ctx;
        ctx.info.index = index;
        ctx.info.guid = GuidToString(m_enumDevices[index].guidInstance);
        ctx.info.instanceName = NarrowFromTChar(m_enumDevices[index].tszInstanceName);
        ctx.info.productName = NarrowFromTChar(m_enumDevices[index].tszProductName);

        HRESULT createHr = m_pDI->CreateDevice(m_enumDevices[index].guidInstance, &ctx.device, nullptr);
        if (FAILED(createHr) || !ctx.device) {
            LogLine("CreateDevice failed for index %d hr=0x%08lX", index, (unsigned long)createHr);
            continue;
        }

        if (!ConfigureJoystickDevice(ctx)) {
            LogLine("ConfigureJoystickDevice failed for index %d", index);
            ctx.device->Release();
            ctx.device = nullptr;
            continue;
        }

        LogLine("Joystick initialized index=%d name=%s guid=%s",
            ctx.info.index,
            ctx.info.instanceName.c_str(),
            ctx.info.guid.c_str());
        m_devices.push_back(std::move(ctx));
        hasAtLeastOne = true;
    }

    if (!hasAtLeastOne) {
        LogLine("Failed to initialize any joystick devices");
    }

    return hasAtLeastOne;
}

bool JoystickMonitor::ConfigureJoystickDevice(DeviceContext& ctx) {
    if (!ctx.device) {
        return false;
    }

    HRESULT hr = ctx.device->SetDataFormat(&c_dfDIJoystick2);
    if (FAILED(hr)) {
        return false;
    }

    hr = ctx.device->SetCooperativeLevel(nullptr, DISCL_NONEXCLUSIVE | DISCL_BACKGROUND);
    if (FAILED(hr)) {
        return false;
    }

    DIDEVCAPS caps;
    caps.dwSize = sizeof(DIDEVCAPS);
    hr = ctx.device->GetCapabilities(&caps);
    if (SUCCEEDED(hr)) {
        ctx.lastButtonState.assign(caps.dwButtons, 0);
        ctx.lastAxisState.assign(caps.dwAxes, 0.0f);
        ctx.axisLastSent.assign(caps.dwAxes, 0.0f);
        ctx.axisPending.assign(caps.dwAxes, false);
    } else {
        ctx.lastButtonState.assign(32, 0);
        ctx.lastAxisState.assign(6, 0.0f);
        ctx.axisLastSent.assign(6, 0.0f);
        ctx.axisPending.assign(6, false);
    }

    hr = ctx.device->Acquire();
    return SUCCEEDED(hr) || hr == S_FALSE;
}

void JoystickMonitor::ReleaseJoystickDevices() {
    for (auto& ctx : m_devices) {
        if (ctx.device) {
            ctx.device->Unacquire();
            ctx.device->Release();
            ctx.device = nullptr;
        }
    }
    m_devices.clear();
}

bool JoystickMonitor::TryRecoverJoystick(HRESULT failureHr) {
    if (!m_pDI) {
        return false;
    }

    auto now = std::chrono::steady_clock::now();
    if ((now - m_lastRecoveryLog) >= std::chrono::seconds(5)) {
        LogLine("Attempting joystick re-enumeration after failure hr=0x%08lX", (unsigned long)failureHr);
        m_lastRecoveryLog = now;
    }

    return InitializeJoystickDevices(m_targetJoystickIndex);
}

void JoystickMonitor::CleanupDirectInput() {
    ReleaseJoystickDevices();
    
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

void JoystickMonitor::SendUDP(const std::string& message) {
    if (m_socket != INVALID_SOCKET) {
        sendto(m_socket, message.c_str(), static_cast<int>(message.size()), 0,
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
    auto lastTime = std::chrono::high_resolution_clock::now();

    while (!m_stopRequested) {
        if (m_devices.empty()) {
            if (!TryRecoverJoystick(E_FAIL)) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
                continue;
            }
        }

        auto now = std::chrono::high_resolution_clock::now();
        float deltaTime = std::chrono::duration<float>(now - lastTime).count();

        bool recoverRequested = false;
        for (size_t devIdx = 0; devIdx < m_devices.size(); ++devIdx) {
            auto& ctx = m_devices[devIdx];
            if (!ctx.device) {
                recoverRequested = true;
                continue;
            }

            DIJOYSTATE2 js = {};
            HRESULT hr = ctx.device->Poll();
            if (FAILED(hr)) {
                recoverRequested = true;
                continue;
            }

            hr = ctx.device->GetDeviceState(sizeof(DIJOYSTATE2), &js);
            if (FAILED(hr)) {
                recoverRequested = true;
                continue;
            }

            for (size_t i = 0; i < ctx.lastButtonState.size(); ++i) {
                BYTE current = (js.rgbButtons[i] & 0x80) ? 1 : 0;
                BYTE last = ctx.lastButtonState[i];

                if (current != last) {
                    const char* edge = current ? "PRESSED" : "RELEASED";
                    char msg[192] = {};
                    snprintf(msg, sizeof(msg), "JOY_%s_BTN_%zu_%s", ctx.info.guid.c_str(), i, edge);
                    SendUDP(std::string(msg));

                    if (ctx.info.index == 0) {
                        char legacyMsg[64] = {};
                        snprintf(legacyMsg, sizeof(legacyMsg), "BTN_%zu_%s", i, edge);
                        SendUDP(std::string(legacyMsg));
                    }
                }

                ctx.lastButtonState[i] = current;
            }

            LONG* axisValues[] = { &js.lX, &js.lY, &js.lZ, &js.lRx, &js.lRy, &js.lRz };
            size_t numAxes = std::min(static_cast<size_t>(6), ctx.lastAxisState.size());
            for (size_t i = 0; i < numAxes; ++i) {
                float current = (*axisValues[i] - 32767.5f) / 32767.5f;
                if (std::fabs(current - ctx.lastAxisState[i]) > AXIS_THRESHOLD) {
                    ctx.lastAxisState[i] = current;
                    ctx.axisPending[i] = true;
                }

                if (ctx.axisPending[i] && deltaTime >= UPDATE_FREQ) {
                    char msg[192] = {};
                    snprintf(msg, sizeof(msg), "JOY_%s_AXIS_%zu_%.4f", ctx.info.guid.c_str(), i, current);
                    SendUDP(std::string(msg));

                    if (ctx.info.index == 0) {
                        char legacyMsg[64] = {};
                        snprintf(legacyMsg, sizeof(legacyMsg), "AXIS_%zu_%.4f", i, current);
                        SendUDP(std::string(legacyMsg));
                    }

                    ctx.axisLastSent[i] = current;
                    ctx.axisPending[i] = false;
                }
            }
        }

        if (recoverRequested && !TryRecoverJoystick(E_FAIL)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        if (deltaTime >= UPDATE_FREQ) {
            lastTime = now;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(8));
    }
}

std::vector<JoystickMonitor::DeviceInfo> JoystickMonitor::EnumerateAttachedDevices() {
    std::vector<DeviceInfo> result;
    LPDIRECTINPUT8 di = nullptr;
    HRESULT createHr = DirectInput8Create(GetModuleHandle(nullptr), DIRECTINPUT_VERSION,
        IID_IDirectInput8, (VOID**)&di, nullptr);
    if (FAILED(createHr) || !di) {
        return result;
    }

    struct EnumContext {
        std::vector<DeviceInfo>* out;
        int index = 0;
    } ctx;
    ctx.out = &result;

    auto callback = [](const DIDEVICEINSTANCE* instance, VOID* user) -> BOOL {
        EnumContext* enumCtx = static_cast<EnumContext*>(user);
        DeviceInfo info;
        info.index = enumCtx->index++;
        info.guid = GuidToString(instance->guidInstance);
        info.instanceName = NarrowFromTChar(instance->tszInstanceName);
        info.productName = NarrowFromTChar(instance->tszProductName);
        enumCtx->out->push_back(info);
        return DIENUM_CONTINUE;
    };

    di->EnumDevices(DI8DEVCLASS_GAMECTRL, callback, &ctx, DIEDFL_ATTACHEDONLY);
    di->Release();
    return result;
}

void JoystickMonitor::LogLine(const char* fmt, ...) {
    char userTemp[MAX_PATH] = {0};
    DWORD len = GetTempPathA(MAX_PATH, userTemp);
    const char* fileName = "AccJoyBridge.log";

    char path[MAX_PATH] = {0};
    if (len > 0 && len < MAX_PATH) {
        snprintf(path, sizeof(path), "%s%s", userTemp, fileName);
    } else {
        snprintf(path, sizeof(path), "C:\\TEMP\\%s", fileName);
    }

    FILE* f = nullptr;
#if defined(_MSC_VER)
    fopen_s(&f, path, "a");
#else
    f = fopen(path, "a");
#endif
    if (!f) {
        return;
    }

    SYSTEMTIME st;
    GetLocalTime(&st);
    fprintf(f, "%04d-%02d-%02d %02d:%02d:%02d.%03d ",
            st.wYear, st.wMonth, st.wDay,
            st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);

    va_list args;
    va_start(args, fmt);
    vfprintf(f, fmt, args);
    va_end(args);

    fputc('\n', f);
    fclose(f);
}
