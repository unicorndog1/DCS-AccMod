#pragma once

// Minimal Lua 5.1 declarations for building without Lua SDK
// This allows the DLL to be compiled and loaded at runtime by Lua

#ifdef __cplusplus
extern "C" {
#endif

// Lua types
typedef struct lua_State lua_State;
typedef double lua_Number;
typedef ptrdiff_t lua_Integer;

// Lua function types
typedef int (*lua_CFunction) (lua_State *L);

// Lua registry pseudo-indices
#define LUA_REGISTRYINDEX	(-10000)
#define LUA_ENVIRONINDEX	(-10001)
#define LUA_GLOBALSINDEX	(-10002)

// Lua API functions (we won't link these, they're provided by Lua at runtime)
typedef void (*lua_pushboolean_t)(lua_State *L, int b);
typedef void (*lua_pushinteger_t)(lua_State *L, lua_Integer n);
typedef void (*lua_pushstring_t)(lua_State *L, const char *s);
typedef int (*lua_gettop_t)(lua_State *L);
typedef int (*lua_isnumber_t)(lua_State *L, int idx);
typedef lua_Integer (*lua_tointeger_t)(lua_State *L, int idx);

// We'll use dynamic function pointers loaded from the Lua state at runtime
// For now, implement stubs that will work
extern lua_pushboolean_t lua_pushboolean;
extern lua_pushinteger_t lua_pushinteger;
extern lua_pushstring_t lua_pushstring;
extern lua_gettop_t lua_gettop;
extern lua_isnumber_t lua_isnumber;
extern lua_tointeger_t lua_tointeger;

// luaL (Lua auxiliary library) functions
typedef struct luaL_Reg {
    const char *name;
    lua_CFunction func;
} luaL_Reg;

typedef void (*luaL_register_t)(lua_State *L, const char *libname, const luaL_Reg *l);
extern luaL_register_t luaL_register;

#ifdef __cplusplus
}
#endif
