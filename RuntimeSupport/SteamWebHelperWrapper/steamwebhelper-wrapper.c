/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 notpop
 * Copyright (c) 2026 Indie contributors
 *
 * Derived from notpop/steam-on-m1-wine's Steam WebHelper wrapper.
 * It forces Steam CEF into CPU rasterization and a single process to avoid
 * black/transparent browser surfaces in Wine on Apple Silicon.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

#define REAL_BINARY L"steamwebhelper_real.exe"
#define EXTRA_FLAGS L"--disable-gpu --single-process --no-sandbox"
#define WRAPPER_MARKER "INDIE_STEAM_WEBHELPER_WRAPPER_V1"

static const wchar_t *forwarded_arguments(void)
{
    const wchar_t *cursor = GetCommandLineW();
    int quoted = 0;
    if (!cursor) return L"";
    while (*cursor) {
        if (*cursor == L'\"') quoted = !quoted;
        else if (*cursor == L' ' && !quoted) break;
        ++cursor;
    }
    while (*cursor == L' ') ++cursor;
    return cursor;
}

int wmain(void)
{
    SetEnvironmentVariableA("INDIE_STEAM_WEBHELPER_WRAPPER", WRAPPER_MARKER);
    wchar_t self[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, self, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return 1;

    wchar_t *slash = wcsrchr(self, L'\\');
    if (!slash) return 2;
    *(slash + 1) = L'\0';

    size_t real_capacity = wcslen(self) + wcslen(REAL_BINARY) + 1;
    wchar_t *real = (wchar_t *)calloc(real_capacity, sizeof(wchar_t));
    if (!real) return 3;
    wcscpy(real, self);
    wcscat(real, REAL_BINARY);

    const wchar_t *tail = forwarded_arguments();
    size_t command_capacity = wcslen(real) + wcslen(EXTRA_FLAGS) + wcslen(tail) + 8;
    wchar_t *command = (wchar_t *)calloc(command_capacity, sizeof(wchar_t));
    if (!command) { free(real); return 4; }
    _snwprintf(command, command_capacity, L"\"%ls\" %ls %ls", real, EXTRA_FLAGS, tail);

    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    ZeroMemory(&startup, sizeof(startup));
    ZeroMemory(&process, sizeof(process));
    startup.cb = sizeof(startup);

    BOOL launched = CreateProcessW(real, command, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process);
    free(command);
    free(real);
    if (!launched) return 5;

    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exit_code = 1;
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return (int)exit_code;
}
