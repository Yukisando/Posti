#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Single-instance: if another Posti instance is running, activate its window
  // and exit immediately. We use a named mutex to detect an existing instance
  // and FindWindow to bring the existing window to the foreground.
  HANDLE single_instance_mutex = CreateMutexW(nullptr, TRUE, L"Local\\PostiSingletonMutex");
  if (single_instance_mutex) {
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
      HWND other = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
      if (other) {
        if (!IsWindowVisible(other)) ShowWindow(other, SW_SHOW);
        SetForegroundWindow(other);
      }
      CloseHandle(single_instance_mutex);
      return EXIT_SUCCESS;
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"posti", origin, size)) {
    return EXIT_FAILURE;
  }
  // Do not quit the process when the window is closed; we hide to tray instead.
  window.SetQuitOnClose(false);

  // Global hotkey logic removed — user requested external shortcut handling.

  // Register the app to start with Windows by default (HKCU Run)
  // Write the current executable path into HKCU\Software\Microsoft\Windows\CurrentVersion\Run
  {
    wchar_t exe_path[MAX_PATH];
    ::GetModuleFileName(nullptr, exe_path, MAX_PATH);
    HKEY hKey;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, LR"(Software\Microsoft\Windows\CurrentVersion\Run)", 0, KEY_WRITE, &hKey) == ERROR_SUCCESS) {
      RegSetValueExW(hKey, L"Posti", 0, REG_SZ, reinterpret_cast<const BYTE*>(exe_path), static_cast<DWORD>((wcslen(exe_path) + 1) * sizeof(wchar_t)));
      RegCloseKey(hKey);
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Clean up the single-instance mutex before exit.
  if (single_instance_mutex) {
    ReleaseMutex(single_instance_mutex);
    CloseHandle(single_instance_mutex);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
