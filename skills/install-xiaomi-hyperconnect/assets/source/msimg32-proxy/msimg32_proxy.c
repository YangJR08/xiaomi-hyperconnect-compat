#define WIN32_LEAN_AND_MEAN
#include <windows.h>

/*
 * Minimal x64 msimg32 proxy for Xiaomi PC Manager's installer.
 *
 * The new installer loads msimg32.dll but no longer imports wtsapi32.dll.
 * This proxy forwards every public msimg32 export to the genuine System32
 * library and explicitly loads the existing sibling wtsapi32.dll model hook.
 */

static HMODULE g_self;
static HMODULE g_real_msimg32;
static HMODULE g_model_hook;
static INIT_ONCE g_init_once = INIT_ONCE_STATIC_INIT;

typedef BOOL (WINAPI *AlphaBlendFn)(HDC, int, int, int, int, HDC, int, int, int, int, BLENDFUNCTION);
typedef BOOL (WINAPI *GradientFillFn)(HDC, PTRIVERTEX, ULONG, PVOID, ULONG, ULONG);
typedef BOOL (WINAPI *TransparentBltFn)(HDC, int, int, int, int, HDC, int, int, int, int, UINT);
typedef BOOL (WINAPI *DllInitializeFn)(HINSTANCE, DWORD, LPVOID);
typedef void (WINAPI *VSetDdrawflagFn)(void);

static AlphaBlendFn g_alpha_blend;
static GradientFillFn g_gradient_fill;
static TransparentBltFn g_transparent_blt;
static DllInitializeFn g_dll_initialize;
static VSetDdrawflagFn g_vset_ddrawflag;

static BOOL append_filename(wchar_t *path, DWORD capacity, const wchar_t *filename)
{
    size_t len = lstrlenW(path);
    if (len == 0 || len + 1 + lstrlenW(filename) + 1 > capacity) {
        return FALSE;
    }
    if (path[len - 1] != L'\\') {
        path[len++] = L'\\';
        path[len] = L'\0';
    }
    return lstrcatW(path, filename) != NULL;
}

static BOOL CALLBACK initialize_proxy(PINIT_ONCE once, PVOID parameter, PVOID *context)
{
    wchar_t real_path[MAX_PATH];
    wchar_t hook_path[MAX_PATH];
    wchar_t *last_slash;
    DWORD length;

    (void)once;
    (void)parameter;
    (void)context;

    length = GetSystemDirectoryW(real_path, ARRAYSIZE(real_path));
    if (length == 0 || length >= ARRAYSIZE(real_path) ||
        !append_filename(real_path, ARRAYSIZE(real_path), L"msimg32.dll")) {
        return FALSE;
    }

    g_real_msimg32 = LoadLibraryW(real_path);
    if (!g_real_msimg32) {
        return FALSE;
    }

    g_alpha_blend = (AlphaBlendFn)GetProcAddress(g_real_msimg32, "AlphaBlend");
    g_gradient_fill = (GradientFillFn)GetProcAddress(g_real_msimg32, "GradientFill");
    g_transparent_blt = (TransparentBltFn)GetProcAddress(g_real_msimg32, "TransparentBlt");
    g_dll_initialize = (DllInitializeFn)GetProcAddress(g_real_msimg32, "DllInitialize");
    g_vset_ddrawflag = (VSetDdrawflagFn)GetProcAddress(g_real_msimg32, "vSetDdrawflag");
    if (!g_alpha_blend || !g_gradient_fill || !g_transparent_blt ||
        !g_dll_initialize || !g_vset_ddrawflag) {
        return FALSE;
    }

    length = GetModuleFileNameW(g_self, hook_path, ARRAYSIZE(hook_path));
    if (length == 0 || length >= ARRAYSIZE(hook_path)) {
        return FALSE;
    }
    last_slash = wcsrchr(hook_path, L'\\');
    if (!last_slash) {
        return FALSE;
    }
    *(last_slash + 1) = L'\0';
    if (!append_filename(hook_path, ARRAYSIZE(hook_path), L"wtsapi32.dll")) {
        return FALSE;
    }

    g_model_hook = LoadLibraryExW(hook_path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!g_model_hook) {
        OutputDebugStringW(L"Xiaomi model proxy: failed to load sibling wtsapi32.dll");
        return FALSE;
    }

    OutputDebugStringW(L"Xiaomi model proxy: initialized");
    return TRUE;
}

static BOOL ensure_initialized(void)
{
    return InitOnceExecuteOnce(&g_init_once, initialize_proxy, NULL, NULL);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = instance;
        DisableThreadLibraryCalls(instance);
        return ensure_initialized();
    }
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI AlphaBlend(
    HDC dst, int x_dst, int y_dst, int width_dst, int height_dst,
    HDC src, int x_src, int y_src, int width_src, int height_src,
    BLENDFUNCTION blend)
{
    return ensure_initialized() && g_alpha_blend
        ? g_alpha_blend(dst, x_dst, y_dst, width_dst, height_dst,
                        src, x_src, y_src, width_src, height_src, blend)
        : FALSE;
}

__declspec(dllexport) BOOL WINAPI GradientFill(
    HDC dc, PTRIVERTEX vertices, ULONG vertex_count,
    PVOID mesh, ULONG mesh_count, ULONG mode)
{
    return ensure_initialized() && g_gradient_fill
        ? g_gradient_fill(dc, vertices, vertex_count, mesh, mesh_count, mode)
        : FALSE;
}

__declspec(dllexport) BOOL WINAPI TransparentBlt(
    HDC dst, int x_dst, int y_dst, int width_dst, int height_dst,
    HDC src, int x_src, int y_src, int width_src, int height_src,
    UINT transparent)
{
    return ensure_initialized() && g_transparent_blt
        ? g_transparent_blt(dst, x_dst, y_dst, width_dst, height_dst,
                            src, x_src, y_src, width_src, height_src, transparent)
        : FALSE;
}

__declspec(dllexport) BOOL WINAPI DllInitialize(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    return ensure_initialized() && g_dll_initialize
        ? g_dll_initialize(instance, reason, reserved)
        : FALSE;
}

__declspec(dllexport) void WINAPI vSetDdrawflag(void)
{
    if (ensure_initialized() && g_vset_ddrawflag) {
        g_vset_ddrawflag();
    }
}
