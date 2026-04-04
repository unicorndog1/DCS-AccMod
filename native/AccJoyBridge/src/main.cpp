#include "joystick_monitor.h"
#include <windows.h>

// Minimal Lua 5.1 declarations
extern "C" {
    typedef struct lua_State lua_State;
    typedef  int (*lua_CFunction) (lua_State *L);
    typedef ptrdiff_t lua_Integer;
    typedef double lua_Number;
    
    struct luaL_Reg {
        const char *name;
        lua_CFunction func;
    };
    
    // Lua C API function pointers - loaded at runtime from lua51.dll
    typedef void (*lua_pushboolean_fn)(lua_State *L, int b);
    typedef void (*lua_pushinteger_fn)(lua_State *L, lua_Integer n);
    typedef void (*lua_pushstring_fn)(lua_State *L, const char *s);
    typedef int (*lua_gettop_fn)(lua_State *L);
    typedef int (*lua_isnumber_fn)(lua_State *L, int idx);
    typedef lua_Integer (*lua_tointeger_fn)(lua_State *L, int idx);
    typedef void (*luaL_register_fn)(lua_State *L, const char *libname, const luaL_Reg *l);
}

// Global function pointers
static lua_pushboolean_fn g_lua_pushboolean = nullptr;
static lua_pushinteger_fn g_lua_pushinteger = nullptr;
static lua_pushstring_fn g_lua_pushstring = nullptr;
static lua_gettop_fn g_lua_gettop = nullptr;
static lua_isnumber_fn g_lua_isnumber = nullptr;
static lua_tointeger_fn g_lua_tointeger = nullptr;
static luaL_register_fn g_luaL_register = nullptr;

// Helper to load Lua functions dynamically
static bool LoadLuaAPI() {
    static bool s_loaded = false;
    if (s_loaded) return true;
    
    // Try multiple common Lua DLL names
    HMODULE lua_dll = GetModuleHandleA("lua51.dll");
    if (!lua_dll) lua_dll = GetModuleHandleA("luajit.dll");
    if (!lua_dll) lua_dll = GetModuleHandleA("lua5.1.dll");
    if (!lua_dll) lua_dll = GetModuleHandleA("lua.dll");
    
    // Last resort: log to a temp file for diagnostics
    if (!lua_dll) {
        HANDLE hFile = CreateFileA("C:\\TEMP\\AccJoyBridge_error.log", GENERIC_WRITE, 0, nullptr, 
                                   CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hFile != INVALID_HANDLE_VALUE) {
            const char* msg = "Failed to find Lua DLL (tried lua51.dll, luajit.dll, lua5.1.dll, lua.dll)\r\n";
            DWORD written;
            WriteFile(hFile, msg, (DWORD)strlen(msg), &written, nullptr);
            CloseHandle(hFile);
        }
        return false;
    }
    
    g_lua_pushboolean = (lua_pushboolean_fn)GetProcAddress(lua_dll, "lua_pushboolean");
    g_lua_pushinteger = (lua_pushinteger_fn)GetProcAddress(lua_dll, "lua_pushinteger");
    g_lua_pushstring = (lua_pushstring_fn)GetProcAddress(lua_dll, "lua_pushstring");
    g_lua_gettop = (lua_gettop_fn)GetProcAddress(lua_dll, "lua_gettop");
    g_lua_isnumber = (lua_isnumber_fn)GetProcAddress(lua_dll, "lua_isnumber");
    g_lua_tointeger = (lua_tointeger_fn)GetProcAddress(lua_dll, "lua_tointeger");
    g_luaL_register = (luaL_register_fn)GetProcAddress(lua_dll, "luaL_register");
    
    s_loaded = (g_lua_pushboolean && g_lua_pushinteger && g_lua_pushstring && 
               g_lua_gettop && g_lua_isnumber && g_lua_tointeger && g_luaL_register);
    
    // Log if API loading failed
    if (!s_loaded) {
        HANDLE hFile = CreateFileA("C:\\TEMP\\AccJoyBridge_error.log", GENERIC_WRITE, 0, nullptr, 
                                   CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hFile != INVALID_HANDLE_VALUE) {
            const char* msg = "Found Lua DLL but failed to load required API functions\r\n";
            DWORD written;
            WriteFile(hFile, msg, (DWORD)strlen(msg), &written, nullptr);
            CloseHandle(hFile);
        }
    }
    
    return s_loaded;
}

// Global instance
static JoystickMonitor* g_monitor = nullptr;

// Lua function: start(joystickIndex)
// Initializes and starts joystick monitoring
static int lua_start(lua_State* L) {
    if (!LoadLuaAPI()) {
        return 0;  // Failed to load Lua API
    }
    
    int joystickIndex = 1;  // Default to joystick 1
    
    if (g_lua_gettop(L) >= 1 && g_lua_isnumber(L, 1)) {
        joystickIndex = (int)g_lua_tointeger(L, 1);
    }
    
    if (g_monitor && g_monitor->IsRunning()) {
      g_monitor->Stop();
    }
    
    if (!g_monitor) {
        g_monitor = new JoystickMonitor();
    }
    
    if (!g_monitor->Initialize(joystickIndex)) {
        delete g_monitor;
        g_monitor = nullptr;
        g_lua_pushboolean(L, 0);
        g_lua_pushstring(L, "Failed to initialize joystick");
        return 2;
    }
    
    g_monitor->Start();
    g_lua_pushboolean(L, 1);
    return 1;
}

// Lua function: stop()
// Stops joystick monitoring
static int lua_stop(lua_State* L) {
    if (!LoadLuaAPI()) {
        return 0;
    }
    
    if (g_monitor) {
        g_monitor->Stop();
        delete g_monitor;
        g_monitor = nullptr;
    }
    
    g_lua_pushboolean(L, 1);
    return 1;
}

// Lua function: isRunning()
// Returns true if monitoring is active
static int lua_isRunning(lua_State* L) {
    if (!LoadLuaAPI()) {
        return 0;
    }
    
    bool running = g_monitor && g_monitor->IsRunning();
    g_lua_pushboolean(L, running ? 1 : 0);
    return 1;
}

// Lua function: listDevices()
// Returns a tab-separated list of devices: index<TAB>guid<TAB>instanceName<TAB>productName\n
static int lua_listDevices(lua_State* L) {
    if (!LoadLuaAPI()) {
        return 0;
    }

    std::vector<JoystickMonitor::DeviceInfo> devices = JoystickMonitor::EnumerateAttachedDevices();
    std::string payload;
    for (const auto& dev : devices) {
        payload += std::to_string(dev.index);
        payload += "\t";
        payload += dev.guid;
        payload += "\t";
        payload += dev.instanceName;
        payload += "\t";
        payload += dev.productName;
        payload += "\n";
    }

    g_lua_pushstring(L, payload.c_str());
    return 1;
}

// Lua module registration
static const luaL_Reg joybridge_funcs[] = {
    {"start", lua_start},
    {"stop", lua_stop},
    {"isRunning", lua_isRunning},
    {"listDevices", lua_listDevices},
    {nullptr, nullptr}
};

// Module entry point for Lua 5.1
extern "C" __declspec(dllexport) int luaopen_AccJoyBridge(lua_State* L) {
    if (!LoadLuaAPI()) {
        // If Lua API loading fails, we need to use raw stack manipulation
        // Push an error table instead of returning nothing (which makes require() return true)
        // Create a minimal table using direct memory - this is a fallback
        // Return NULL/false to signal error
        return 0;  // Module load failure - require() will error
    }
    g_luaL_register(L, "AccJoyBridge", joybridge_funcs);
    return 1;
}

// DLL entry point
extern "C" BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH:
        case DLL_THREAD_ATTACH:
        case DLL_THREAD_DETACH:
            break;
        case DLL_PROCESS_DETACH:
            if (g_monitor) {
                g_monitor->Stop();
                delete g_monitor;
                g_monitor = nullptr;
            }
            break;
    }
    return TRUE;
}
