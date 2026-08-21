#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>

static void print_loaded_proxy_modules(void)
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, 0);
    MODULEENTRY32W entry;

    if (snapshot == INVALID_HANDLE_VALUE) {
        fwprintf(stderr, L"CreateToolhelp32Snapshot failed: %lu\n", GetLastError());
        return;
    }

    ZeroMemory(&entry, sizeof(entry));
    entry.dwSize = sizeof(entry);
    if (Module32FirstW(snapshot, &entry)) {
        do {
            if (lstrcmpiW(entry.szModule, L"msimg32.dll") == 0 ||
                lstrcmpiW(entry.szModule, L"wtsapi32.dll") == 0) {
                wprintf(L"loaded: %ls -> %ls\n", entry.szModule, entry.szExePath);
            }
        } while (Module32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
}

int wmain(int argc, wchar_t **argv)
{
    static const char *exports[] = {
        "vSetDdrawflag", "AlphaBlend", "DllInitialize", "GradientFill", "TransparentBlt"
    };
    HMODULE module;
    HMODULE hook;
    BOOL should_load_hook;
    size_t i;

    if (argc != 3) {
        fwprintf(stderr, L"Usage: %ls <full-path-to-msimg32.dll> <load|skip>\n", argv[0]);
        return 2;
    }
    should_load_hook = _wcsicmp(argv[2], L"load") == 0;
    if (!should_load_hook && _wcsicmp(argv[2], L"skip") != 0) {
        return 3;
    }

    module = LoadLibraryW(argv[1]);
    if (!module) {
        fwprintf(stderr, L"LoadLibrary failed: %lu\n", GetLastError());
        return 4;
    }

    for (i = 0; i < ARRAYSIZE(exports); ++i) {
        FARPROC address = GetProcAddress(module, exports[i]);
        printf("%s: %s\n", exports[i], address ? "OK" : "MISSING");
        if (!address) {
            FreeLibrary(module);
            return 5;
        }
    }

    hook = GetModuleHandleW(L"wtsapi32.dll");
    if ((hook != NULL) != should_load_hook) {
        fwprintf(stderr, L"unexpected sibling-hook state: %ls\n",
                 hook ? L"loaded" : L"not loaded");
        FreeLibrary(module);
        return 6;
    }

    print_loaded_proxy_modules();

    FreeLibrary(module);
    return 0;
}
