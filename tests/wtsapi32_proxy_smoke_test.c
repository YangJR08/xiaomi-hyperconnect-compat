#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

static const char *const export_names[] = {
    "IsInteractiveUserSession", "QueryActiveSession", "QueryUserToken",
    "RegisterUsertokenForNoWinlogon", "WTSCloseServer", "WTSConnectSessionA",
    "WTSConnectSessionW", "WTSCreateListenerA", "WTSCreateListenerW",
    "WTSDisconnectSession", "WTSEnableChildSessions", "WTSEnumerateListenersA",
    "WTSEnumerateListenersW", "WTSEnumerateProcessesA", "WTSEnumerateProcessesExA",
    "WTSEnumerateProcessesExW", "WTSEnumerateProcessesW", "WTSEnumerateServersA",
    "WTSEnumerateServersW", "WTSEnumerateSessionsA", "WTSEnumerateSessionsExA",
    "WTSEnumerateSessionsExW", "WTSEnumerateSessionsW", "WTSFreeMemory",
    "WTSFreeMemoryExA", "WTSFreeMemoryExW", "WTSGetChildSessionId",
    "WTSGetListenerSecurityA", "WTSGetListenerSecurityW", "WTSIsChildSessionsEnabled",
    "WTSLogoffSession", "WTSOpenServerA", "WTSOpenServerExA", "WTSOpenServerExW",
    "WTSOpenServerW", "WTSQueryListenerConfigA", "WTSQueryListenerConfigW",
    "WTSQuerySessionInformationA", "WTSQuerySessionInformationW", "WTSQueryUserConfigA",
    "WTSQueryUserConfigW", "WTSQueryUserToken", "WTSRegisterSessionNotification",
    "WTSRegisterSessionNotificationEx", "WTSSendMessageA", "WTSSendMessageW",
    "WTSSetListenerSecurityA", "WTSSetListenerSecurityW", "WTSSetRenderHint",
    "WTSSetSessionInformationA", "WTSSetSessionInformationW", "WTSSetUserConfigA",
    "WTSSetUserConfigW", "WTSShutdownSystem", "WTSStartRemoteControlSessionA",
    "WTSStartRemoteControlSessionW", "WTSStopRemoteControlSession", "WTSTerminateProcess",
    "WTSUnRegisterSessionNotification", "WTSUnRegisterSessionNotificationEx",
    "WTSVirtualChannelClose", "WTSVirtualChannelOpen", "WTSVirtualChannelOpenEx",
    "WTSVirtualChannelPurgeInput", "WTSVirtualChannelPurgeOutput", "WTSVirtualChannelQuery",
    "WTSVirtualChannelRead", "WTSVirtualChannelWrite", "WTSWaitSystemEvent"
};

typedef BOOL (WINAPI *EnumerateSessionsWFn)(HANDLE, DWORD, DWORD, void **, DWORD *);
typedef void (WINAPI *FreeMemoryFn)(void *);

int wmain(int argc, wchar_t **argv)
{
    HMODULE proxy;
    HMODULE hook;
    EnumerateSessionsWFn enumerate_sessions;
    FreeMemoryFn free_memory;
    void *sessions = NULL;
    DWORD count = 0;
    size_t index;
    BOOL should_load_hook;

    if (argc != 3) {
        fwprintf(stderr, L"usage: %ls <proxy.dll> <load|skip>\n", argv[0]);
        return 2;
    }
    should_load_hook = _wcsicmp(argv[2], L"load") == 0;
    if (!should_load_hook && _wcsicmp(argv[2], L"skip") != 0) {
        return 3;
    }

    proxy = LoadLibraryExW(argv[1], NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!proxy) {
        fwprintf(stderr, L"LoadLibraryExW failed: %lu\n", GetLastError());
        return 4;
    }
    for (index = 0; index < ARRAYSIZE(export_names); ++index) {
        if (!GetProcAddress(proxy, export_names[index])) {
            fprintf(stderr, "missing export: %s\n", export_names[index]);
            return 5;
        }
    }

    hook = GetModuleHandleW(L"XiaomiHyperConnectModelHook.dll");
    if ((hook != NULL) != should_load_hook) {
        fwprintf(stderr, L"unexpected model-hook state: %ls\n", hook ? L"loaded" : L"not loaded");
        return 6;
    }

    enumerate_sessions = (EnumerateSessionsWFn)GetProcAddress(proxy, "WTSEnumerateSessionsW");
    free_memory = (FreeMemoryFn)GetProcAddress(proxy, "WTSFreeMemory");
    if (!enumerate_sessions(NULL, 0, 1, &sessions, &count)) {
        fwprintf(stderr, L"WTSEnumerateSessionsW failed: %lu\n", GetLastError());
        return 7;
    }
    if (sessions) {
        free_memory(sessions);
    }

    wprintf(L"wtsapi32 proxy smoke test passed; model hook %ls; sessions=%lu\n",
            hook ? L"loaded" : L"skipped", count);
    return 0;
}
