#include "flutter_window.h"
#include "resource.h"

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"

// Tray icon message ID
#ifndef WM_TRAYICON
#define WM_TRAYICON (WM_APP + 1)
#endif

static NOTIFYICONDATAW g_nid = {};

static void AddTrayIcon(HWND hwnd) {
  ZeroMemory(&g_nid, sizeof(g_nid));
  g_nid.cbSize = sizeof(g_nid);
  g_nid.hWnd = hwnd;
  g_nid.uID = 1;
  g_nid.uCallbackMessage = WM_TRAYICON;
  g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  // Try to load the app icon from Flutter assets (`assets/icon.ico`) at runtime.
  // Fallback to the compiled resource IDI_APP_ICON and then to a system icon.
  HICON hIcon = nullptr;
  {
    wchar_t exe_path[MAX_PATH];
    GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
    std::wstring dir(exe_path);
    const auto pos = dir.find_last_of(L"\\/");
    if (pos != std::wstring::npos) dir = dir.substr(0, pos);
    std::wstring asset_path = dir + L"\\data\\flutter_assets\\assets\\icon.ico";
    hIcon = reinterpret_cast<HICON>(LoadImageW(nullptr, asset_path.c_str(), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE));
  }
  if (!hIcon) {
    hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  }
  if (!hIcon) {
    hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  }
  g_nid.hIcon = hIcon;
  wcscpy_s(g_nid.szTip, L"Posti");
  Shell_NotifyIconW(NIM_ADD, &g_nid);
}

static void RemoveTrayIcon() {
  Shell_NotifyIconW(NIM_DELETE, &g_nid);
}

// Toggle registry Run entry for auto-start
static void ToggleAutoStart(HWND hwnd) {
  HKEY hKey;
  const wchar_t* subKey = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  LONG r = RegOpenKeyExW(HKEY_CURRENT_USER, subKey, 0, KEY_READ | KEY_WRITE, &hKey);
  if (r == ERROR_SUCCESS) {
    // check if value exists
    DWORD type = REG_SZ;
    DWORD dataSize = 0;
    if (RegQueryValueExW(hKey, L"Posti", nullptr, &type, nullptr, &dataSize) == ERROR_SUCCESS) {
      // exists -> delete
      RegDeleteValueW(hKey, L"Posti");
    } else {
      // create value with current exe path
      wchar_t path[MAX_PATH];
      GetModuleFileNameW(nullptr, path, MAX_PATH);
      RegSetValueExW(hKey, L"Posti", 0, REG_SZ, (const BYTE*)path, (DWORD)((wcslen(path) + 1) * sizeof(wchar_t)));
    }
    RegCloseKey(hKey);
  }
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // Add system tray icon (start hidden behavior is controlled from Dart)
  AddTrayIcon(GetHandle());

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  RemoveTrayIcon();
  Win32Window::OnDestroy();
} 

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Handle tray icon and command messages BEFORE passing to Flutter plugins,
  // so that no plugin can intercept and consume them.
  switch (message) {
    case WM_TRAYICON: {
      switch (lparam) {
        case WM_LBUTTONUP: {
          // toggle show/hide
          if (IsWindowVisible(hwnd)) {
            ShowWindow(hwnd, SW_HIDE);
          } else {
            ShowWindow(hwnd, SW_SHOW);
            SetForegroundWindow(hwnd);
          }
          return 0;
        }
        case WM_RBUTTONUP: {
          // show context menu
          POINT pt;
          GetCursorPos(&pt);
          HMENU hMenu = CreatePopupMenu();

          // determine whether the Run registry entry exists so we can show a check
          bool autostart = false;
          HKEY hKey;
          const wchar_t* subKey = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
          if (RegOpenKeyExW(HKEY_CURRENT_USER, subKey, 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            DWORD type = REG_SZ;
            DWORD dataSize = 0;
            if (RegQueryValueExW(hKey, L"Posti", nullptr, &type, nullptr, &dataSize) == ERROR_SUCCESS && dataSize > 0) {
              autostart = true;
            }
            RegCloseKey(hKey);
          }

          AppendMenuW(hMenu, MF_STRING | (autostart ? MF_CHECKED : 0), 1002, L"Start with Windows");
          AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
          AppendMenuW(hMenu, MF_STRING, 1003, L"Quit");
          SetForegroundWindow(hwnd); // required before TrackPopupMenu
          TrackPopupMenu(hMenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr);
          // Post a benign message so the menu dismisses reliably (Win32 best practice)
          PostMessage(hwnd, WM_NULL, 0, 0);
          DestroyMenu(hMenu);
          return 0;
        }
      }
      return 0;
    }

    case WM_COMMAND: {
      const int wmId = LOWORD(wparam);
      switch (wmId) {
        case 1002: // Toggle autostart
          ToggleAutoStart(hwnd);
          return 0;
        case 1003: // Quit
          PostQuitMessage(0);
          return 0;
      }
      break;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
} 
