/* A native Win32 launcher; no console, browser or managed UI runtime. */
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <bcrypt.h>
#include <wchar.h>
#include <stdio.h>
#include <string.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show) {
    wchar_t root[32768], executable[32768], command[32768], libraries[32768];
    unsigned char random[24];
    wchar_t cookie[49];
    char profile[32] = {0};
    FILE *settings = NULL;
    (void)instance; (void)previous; (void)args; (void)show;
    if (!GetModuleFileNameW(NULL, root, 32768)) return 1;
    wchar_t *last = wcsrchr(root, L'\\');
    if (!last) return 1;
    *last = 0;
    _snwprintf_s(libraries, 32768, _TRUNCATE, L"%s\\runtime-profile", root);
    if (_wfopen_s(&settings, libraries, L"rb") == 0) {
        fread(profile, 1, sizeof(profile) - 1, settings);
        fclose(settings);
    }
    int native = strcmp(profile, "native_cluster") == 0;
    if (!native && strcmp(profile, "legacy_apps") != 0) {
        MessageBoxW(NULL, L"The runtime profile is missing. Rebuild the Windows app.", L"Parvi", MB_OK | MB_ICONERROR);
        return 1;
    }
    if (BCryptGenRandom(NULL, random, sizeof(random), BCRYPT_USE_SYSTEM_PREFERRED_RNG)) return 1;
    for (int i = 0; i < 24; ++i) swprintf_s(cookie + i * 2, 49 - i * 2, L"%02x", random[i]);
    _snwprintf_s(executable, 32768, _TRUNCATE, L"%s\\runtime\\bin\\erl.exe", root);
    if (native) _snwprintf_s(command, 32768, _TRUNCATE,
        L"\"%s\" -noshell -noinput -name parvi_windows_%lu@127.0.0.1 -setcookie %s "
        L"-start_epmd false -proto_dist parvi_webrtc -kernel connect_all false dist_auto_connect never "
        L"-parvi runtime_profile native_cluster native_desk true -pa \"%s\\ebin\" -s parvi_windows main",
        executable, GetCurrentProcessId(), cookie, root);
    else _snwprintf_s(command, 32768, _TRUNCATE,
        L"\"%s\" -noshell -noinput -name parvi_windows_%lu@127.0.0.1 -setcookie %s "
        L"-kernel inet_dist_use_interface {127,0,0,1} -pa \"%s\\ebin\" -s parvi_windows main",
        executable, GetCurrentProcessId(), cookie, root);
    STARTUPINFOW startup = { sizeof(startup) };
    PROCESS_INFORMATION process = {0};
    _snwprintf_s(libraries, 32768, _TRUNCATE, L"%s\\native_lib", root);
    SetEnvironmentVariableW(L"ERL_LIBS", libraries);
    if (!native) SetEnvironmentVariableW(L"ERL_EPMD_ADDRESS", L"127.0.0.1");
    if (!CreateProcessW(executable, command, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                        NULL, root, &startup, &process)) {
        MessageBoxW(NULL, L"Could not start the bundled Erlang runtime. Rebuild the Windows app.",
                    L"Parvi", MB_OK | MB_ICONERROR);
        return 1;
    }
    CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hProcess);
    if (code) MessageBoxW(NULL, L"Parvi stopped unexpectedly. Run Apps/Windows/run.ps1 for diagnostics.",
                          L"Parvi", MB_OK | MB_ICONERROR);
    return (int)code;
}
