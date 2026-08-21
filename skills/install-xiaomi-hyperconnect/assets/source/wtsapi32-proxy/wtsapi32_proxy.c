#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>

/*
 * x64 wtsapi32 proxy for Xiaomi HyperConnect runtime directories.
 *
 * It forwards the legacy hook's complete export surface to the genuine
 * System32 wtsapi32.dll. For normal application processes it then loads the
 * renamed model hook from the same directory. The official Xiaomi uninstaller
 * also imports wtsapi32.dll, so Uninstall.exe deliberately receives only the
 * system forwarding behavior and never loads the model hook.
 */

#define TARGET_COUNT 69

HMODULE g_real_wtsapi32;
HMODULE g_model_hook;
void *g_wts_targets[TARGET_COUNT];

static const char *const g_target_names[TARGET_COUNT] = {
    "IsInteractiveUserSession",
    "QueryActiveSession",
    "QueryUserToken",
    "RegisterUsertokenForNoWinlogon",
    "WTSCloseServer",
    "WTSConnectSessionA",
    "WTSConnectSessionW",
    "WTSCreateListenerA",
    "WTSCreateListenerW",
    "WTSDisconnectSession",
    "WTSEnableChildSessions",
    "WTSEnumerateListenersA",
    "WTSEnumerateListenersW",
    "WTSEnumerateProcessesA",
    "WTSEnumerateProcessesExA",
    "WTSEnumerateProcessesExW",
    "WTSEnumerateProcessesW",
    "WTSEnumerateServersA",
    "WTSEnumerateServersW",
    "WTSEnumerateSessionsA",
    "WTSEnumerateSessionsExA",
    "WTSEnumerateSessionsExW",
    "WTSEnumerateSessionsW",
    "WTSFreeMemory",
    "WTSFreeMemoryExA",
    "WTSFreeMemoryExW",
    "WTSGetChildSessionId",
    "WTSGetListenerSecurityA",
    "WTSGetListenerSecurityW",
    "WTSIsChildSessionsEnabled",
    "WTSLogoffSession",
    "WTSOpenServerA",
    "WTSOpenServerExA",
    "WTSOpenServerExW",
    "WTSOpenServerW",
    "WTSQueryListenerConfigA",
    "WTSQueryListenerConfigW",
    "WTSQuerySessionInformationA",
    "WTSQuerySessionInformationW",
    "WTSQueryUserConfigA",
    "WTSQueryUserConfigW",
    "WTSQueryUserToken",
    "WTSRegisterSessionNotification",
    "WTSRegisterSessionNotificationEx",
    "WTSSendMessageA",
    "WTSSendMessageW",
    "WTSSetListenerSecurityA",
    "WTSSetListenerSecurityW",
    "WTSSetRenderHint",
    "WTSSetSessionInformationA",
    "WTSSetSessionInformationW",
    "WTSSetUserConfigA",
    "WTSSetUserConfigW",
    "WTSShutdownSystem",
    "WTSStartRemoteControlSessionA",
    "WTSStartRemoteControlSessionW",
    "WTSStopRemoteControlSession",
    "WTSTerminateProcess",
    "WTSUnRegisterSessionNotification",
    "WTSUnRegisterSessionNotificationEx",
    "WTSVirtualChannelClose",
    "WTSVirtualChannelOpen",
    "WTSVirtualChannelOpenEx",
    "WTSVirtualChannelPurgeInput",
    "WTSVirtualChannelPurgeOutput",
    "WTSVirtualChannelQuery",
    "WTSVirtualChannelRead",
    "WTSVirtualChannelWrite",
    "WTSWaitSystemEvent"
};

static BOOL append_filename(wchar_t *path, DWORD capacity, const wchar_t *filename)
{
    size_t length = wcslen(path);
    size_t filename_length = wcslen(filename);

    if (length == 0 || length + 1 + filename_length + 1 > capacity) {
        return FALSE;
    }
    if (path[length - 1] != L'\\') {
        path[length++] = L'\\';
        path[length] = L'\0';
    }
    return wcscat_s(path, capacity, filename) == 0;
}

static BOOL is_official_uninstaller_process(void)
{
    wchar_t process_path[MAX_PATH];
    wchar_t *base_name;
    DWORD length = GetModuleFileNameW(NULL, process_path, ARRAYSIZE(process_path));

    if (length == 0 || length >= ARRAYSIZE(process_path)) {
        return FALSE;
    }
    base_name = wcsrchr(process_path, L'\\');
    base_name = base_name ? base_name + 1 : process_path;
    return _wcsicmp(base_name, L"Uninstall.exe") == 0;
}

static BOOL initialize_proxy(HMODULE self)
{
    wchar_t path[MAX_PATH];
    wchar_t *last_slash;
    DWORD length;
    int index;
    BOOL uninstaller = is_official_uninstaller_process();

    length = GetSystemDirectoryW(path, ARRAYSIZE(path));
    if (length == 0 || length >= ARRAYSIZE(path) ||
        !append_filename(path, ARRAYSIZE(path), L"wtsapi32.dll")) {
        return FALSE;
    }
    g_real_wtsapi32 = LoadLibraryW(path);
    if (!g_real_wtsapi32) {
        return FALSE;
    }

    if (uninstaller) {
        /* Both verified Xiaomi uninstallers import only these three WTS APIs. */
        static const int uninstaller_targets[] = { 22, 23, 41 };
        for (index = 0; index < (int)ARRAYSIZE(uninstaller_targets); ++index) {
            int target = uninstaller_targets[index];
            g_wts_targets[target] =
                (void *)GetProcAddress(g_real_wtsapi32, g_target_names[target]);
            if (!g_wts_targets[target]) {
                return FALSE;
            }
        }
    }
    else {
        for (index = 0; index < TARGET_COUNT; ++index) {
            g_wts_targets[index] =
                (void *)GetProcAddress(g_real_wtsapi32, g_target_names[index]);
            if (!g_wts_targets[index]) {
                return FALSE;
            }
        }
    }

    if (uninstaller) {
        OutputDebugStringW(L"Xiaomi wtsapi32 proxy: uninstaller bypass active");
        return TRUE;
    }

    length = GetModuleFileNameW(self, path, ARRAYSIZE(path));
    if (length == 0 || length >= ARRAYSIZE(path)) {
        return FALSE;
    }
    last_slash = wcsrchr(path, L'\\');
    if (!last_slash) {
        return FALSE;
    }
    *(last_slash + 1) = L'\0';
    if (!append_filename(path, ARRAYSIZE(path), L"XiaomiHyperConnectModelHook.dll")) {
        return FALSE;
    }
    g_model_hook = LoadLibraryExW(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!g_model_hook) {
        OutputDebugStringW(L"Xiaomi wtsapi32 proxy: failed to load sibling model hook");
        return FALSE;
    }

    OutputDebugStringW(L"Xiaomi wtsapi32 proxy: initialized with model hook");
    return TRUE;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        return initialize_proxy(instance);
    }
    return TRUE;
}

#define FORWARDER(name, offset)                  \
    __attribute__((naked)) void WINAPI name(void) \
    {                                             \
        __asm__ volatile("jmp *g_wts_targets+" #offset "(%rip)"); \
    }

FORWARDER(IsInteractiveUserSession, 0)
FORWARDER(QueryActiveSession, 8)
FORWARDER(QueryUserToken, 16)
FORWARDER(RegisterUsertokenForNoWinlogon, 24)
FORWARDER(WTSCloseServer, 32)
FORWARDER(WTSConnectSessionA, 40)
FORWARDER(WTSConnectSessionW, 48)
FORWARDER(WTSCreateListenerA, 56)
FORWARDER(WTSCreateListenerW, 64)
FORWARDER(WTSDisconnectSession, 72)
FORWARDER(WTSEnableChildSessions, 80)
FORWARDER(WTSEnumerateListenersA, 88)
FORWARDER(WTSEnumerateListenersW, 96)
FORWARDER(WTSEnumerateProcessesA, 104)
FORWARDER(WTSEnumerateProcessesExA, 112)
FORWARDER(WTSEnumerateProcessesExW, 120)
FORWARDER(WTSEnumerateProcessesW, 128)
FORWARDER(WTSEnumerateServersA, 136)
FORWARDER(WTSEnumerateServersW, 144)
FORWARDER(WTSEnumerateSessionsA, 152)
FORWARDER(WTSEnumerateSessionsExA, 160)
FORWARDER(WTSEnumerateSessionsExW, 168)
FORWARDER(WTSEnumerateSessionsW, 176)
FORWARDER(WTSFreeMemory, 184)
FORWARDER(WTSFreeMemoryExA, 192)
FORWARDER(WTSFreeMemoryExW, 200)
FORWARDER(WTSGetChildSessionId, 208)
FORWARDER(WTSGetListenerSecurityA, 216)
FORWARDER(WTSGetListenerSecurityW, 224)
FORWARDER(WTSIsChildSessionsEnabled, 232)
FORWARDER(WTSLogoffSession, 240)
FORWARDER(WTSOpenServerA, 248)
FORWARDER(WTSOpenServerExA, 256)
FORWARDER(WTSOpenServerExW, 264)
FORWARDER(WTSOpenServerW, 272)
FORWARDER(WTSQueryListenerConfigA, 280)
FORWARDER(WTSQueryListenerConfigW, 288)
FORWARDER(WTSQuerySessionInformationA, 296)
FORWARDER(WTSQuerySessionInformationW, 304)
FORWARDER(WTSQueryUserConfigA, 312)
FORWARDER(WTSQueryUserConfigW, 320)
FORWARDER(WTSQueryUserToken, 328)
FORWARDER(WTSRegisterSessionNotification, 336)
FORWARDER(WTSRegisterSessionNotificationEx, 344)
FORWARDER(WTSSendMessageA, 352)
FORWARDER(WTSSendMessageW, 360)
FORWARDER(WTSSetListenerSecurityA, 368)
FORWARDER(WTSSetListenerSecurityW, 376)
FORWARDER(WTSSetRenderHint, 384)
FORWARDER(WTSSetSessionInformationA, 392)
FORWARDER(WTSSetSessionInformationW, 400)
FORWARDER(WTSSetUserConfigA, 408)
FORWARDER(WTSSetUserConfigW, 416)
FORWARDER(WTSShutdownSystem, 424)
FORWARDER(WTSStartRemoteControlSessionA, 432)
FORWARDER(WTSStartRemoteControlSessionW, 440)
FORWARDER(WTSStopRemoteControlSession, 448)
FORWARDER(WTSTerminateProcess, 456)
FORWARDER(WTSUnRegisterSessionNotification, 464)
FORWARDER(WTSUnRegisterSessionNotificationEx, 472)
FORWARDER(WTSVirtualChannelClose, 480)
FORWARDER(WTSVirtualChannelOpen, 488)
FORWARDER(WTSVirtualChannelOpenEx, 496)
FORWARDER(WTSVirtualChannelPurgeInput, 504)
FORWARDER(WTSVirtualChannelPurgeOutput, 512)
FORWARDER(WTSVirtualChannelQuery, 520)
FORWARDER(WTSVirtualChannelRead, 528)
FORWARDER(WTSVirtualChannelWrite, 536)
FORWARDER(WTSWaitSystemEvent, 544)
