/*
 * WinTuxTray.exe - minimal system-tray monitor for WinTux.
 *
 * Lives in the notification area. Polls every 3 seconds for a running
 * qemu-system-x86_64.exe child. Right-click menu:
 *   Launch WinTux / Open SSH Shell / Kill WinTux VM / Settings / Exit
 *
 * Icon loaded from the embedded wintux.ico (same resource as the main
 * launcher, so compiled against the same resources.rc).
 *
 * Build (cross-compile from Linux):
 *   x86_64-w64-mingw32-windres resources.rc -o resources.o
 *   x86_64-w64-mingw32-gcc -O2 -o WinTuxTray.exe tray.c resources.o \
 *       -lshell32 -lgdi32 -mwindows -municode
 *
 * (c) 2026 Glitch Linux
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <stdio.h>

#define IDI_APP            101
#define WM_TRAY_NOTIFY     (WM_USER + 1)
#define TRAY_UID           0xC00C

#define IDM_LAUNCH         1001
#define IDM_SSH            1002
#define IDM_KILL           1003
#define IDM_SETTINGS       1004
#define IDM_EXIT           1005

static HINSTANCE g_hInst;
static HWND      g_hWnd;
static HICON     g_hIcon;
static NOTIFYICONDATAW g_nid;
static WCHAR     g_installDir[MAX_PATH];
static WCHAR     g_launcherExe[MAX_PATH];
static WCHAR     g_sshBat[MAX_PATH];
static BOOL      g_qemuRunning = FALSE;

static void BuildPaths(void) {
    GetModuleFileNameW(NULL, g_launcherExe, MAX_PATH);
    wcscpy(g_installDir, g_launcherExe);
    WCHAR *slash = wcsrchr(g_installDir, L'\\');
    if (slash) *slash = 0;
    wsprintfW(g_launcherExe, L"%s\\WinTux.exe", g_installDir);
    wsprintfW(g_sshBat,      L"%s\\qemu\\wintux-open-ssh.bat", g_installDir);
}

static BOOL IsQemuRunning(void) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return FALSE;
    PROCESSENTRY32W pe; pe.dwSize = sizeof(pe);
    BOOL found = FALSE;
    if (Process32FirstW(snap, &pe)) {
        do {
            if (_wcsicmp(pe.szExeFile, L"qemu-system-x86_64.exe") == 0) {
                found = TRUE; break;
            }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return found;
}

static void KillQemu(void) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return;
    PROCESSENTRY32W pe; pe.dwSize = sizeof(pe);
    if (Process32FirstW(snap, &pe)) {
        do {
            if (_wcsicmp(pe.szExeFile, L"qemu-system-x86_64.exe") == 0) {
                HANDLE p = OpenProcess(PROCESS_TERMINATE, FALSE, pe.th32ProcessID);
                if (p) { TerminateProcess(p, 0); CloseHandle(p); }
            }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
}

static void LaunchExe(const WCHAR *exe, const WCHAR *args) {
    SHELLEXECUTEINFOW sei; ZeroMemory(&sei, sizeof(sei));
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;
    sei.lpFile = exe;
    sei.lpParameters = args;
    sei.lpDirectory = g_installDir;
    sei.nShow = SW_SHOWNORMAL;
    if (ShellExecuteExW(&sei) && sei.hProcess) CloseHandle(sei.hProcess);
}

static void UpdateIconState(void) {
    BOOL running = IsQemuRunning();
    if (running == g_qemuRunning) return;
    g_qemuRunning = running;
    wcscpy(g_nid.szTip, running ? L"WinTux  [VM running]" : L"WinTux  [VM stopped]");
    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}

static void ShowTrayMenu(void) {
    HMENU m = CreatePopupMenu();
    BOOL running = IsQemuRunning();

    AppendMenuW(m, MF_STRING | (running ? MF_GRAYED : 0), IDM_LAUNCH,   L"Launch WinTux");
    AppendMenuW(m, MF_STRING | (running ? 0 : MF_GRAYED), IDM_SSH,      L"Open SSH Shell");
    AppendMenuW(m, MF_STRING | (running ? 0 : MF_GRAYED), IDM_KILL,     L"Kill WinTux VM");
    AppendMenuW(m, MF_SEPARATOR, 0, NULL);
    AppendMenuW(m, MF_STRING, IDM_SETTINGS, L"Open WinTux Settings...");
    AppendMenuW(m, MF_SEPARATOR, 0, NULL);
    AppendMenuW(m, MF_STRING, IDM_EXIT,     L"Exit WinTux Tray");

    POINT pt; GetCursorPos(&pt);
    SetForegroundWindow(g_hWnd);  /* required for menu dismissal to work */
    TrackPopupMenu(m, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.x, pt.y, 0, g_hWnd, NULL);
    PostMessage(g_hWnd, WM_NULL, 0, 0);
    DestroyMenu(m);
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_TRAY_NOTIFY:
        if (LOWORD(lp) == WM_RBUTTONUP || LOWORD(lp) == WM_LBUTTONUP) {
            ShowTrayMenu();
        } else if (LOWORD(lp) == WM_LBUTTONDBLCLK) {
            LaunchExe(g_launcherExe, NULL);
        }
        return 0;

    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case IDM_LAUNCH:
            /* Launch the main GUI; the user clicks "Launch WinTux" there.
             * (A direct-launch flag could skip the GUI entirely later.) */
            LaunchExe(g_launcherExe, NULL);
            break;
        case IDM_SSH:
            if (GetFileAttributesW(g_sshBat) != INVALID_FILE_ATTRIBUTES) {
                LaunchExe(g_sshBat, NULL);
            } else {
                MessageBoxW(hwnd, L"wintux-open-ssh.bat not found next to the installation.", L"WinTux Tray", MB_OK|MB_ICONERROR);
            }
            break;
        case IDM_KILL:
            if (MessageBoxW(hwnd, L"Terminate the running WinTux VM?",
                            L"WinTux Tray", MB_YESNO|MB_ICONQUESTION) == IDYES) {
                KillQemu();
                UpdateIconState();
            }
            break;
        case IDM_SETTINGS:
            LaunchExe(g_launcherExe, NULL);
            break;
        case IDM_EXIT:
            Shell_NotifyIconW(NIM_DELETE, &g_nid);
            PostQuitMessage(0);
            break;
        }
        return 0;

    case WM_TIMER:
        UpdateIconState();
        return 0;

    case WM_DESTROY:
        Shell_NotifyIconW(NIM_DELETE, &g_nid);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, LPWSTR cmdLine, int nShow) {
    (void)hPrev; (void)cmdLine; (void)nShow;
    g_hInst = hInst;

    /* Prevent multiple tray instances */
    HANDLE mutex = CreateMutexW(NULL, TRUE, L"Global\\WinTuxTray_Singleton");
    if (mutex && GetLastError() == ERROR_ALREADY_EXISTS) return 0;

    BuildPaths();

    /* Load the icon from embedded resource (IDI_APP = 101) */
    g_hIcon = (HICON)LoadImageW(hInst, MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON,
                                16, 16, LR_DEFAULTCOLOR);
    if (!g_hIcon) g_hIcon = LoadIconW(NULL, IDI_APPLICATION);

    /* Hidden message-only window */
    WNDCLASSEXW wc = {0};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = L"WinTuxTrayWnd";
    RegisterClassExW(&wc);
    g_hWnd = CreateWindowExW(0, L"WinTuxTrayWnd", L"WinTux Tray",
                             0, 0, 0, 0, 0, HWND_MESSAGE, NULL, hInst, NULL);

    /* Register the tray icon */
    ZeroMemory(&g_nid, sizeof(g_nid));
    g_nid.cbSize = sizeof(g_nid);
    g_nid.hWnd = g_hWnd;
    g_nid.uID = TRAY_UID;
    g_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAY_NOTIFY;
    g_nid.hIcon = g_hIcon;
    wcscpy(g_nid.szTip, L"WinTux  [checking...]");
    Shell_NotifyIconW(NIM_ADD, &g_nid);

    /* Poll every 3 seconds */
    SetTimer(g_hWnd, 1, 3000, NULL);
    UpdateIconState();  /* immediate first update */

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    if (mutex) { ReleaseMutex(mutex); CloseHandle(mutex); }
    return 0;
}
