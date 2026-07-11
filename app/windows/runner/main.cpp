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

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  bool is_queue_screen = false;
  if (command_line != nullptr && wcsstr(command_line, L"--queue-screen") != nullptr) {
    is_queue_screen = true;
  }

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  if (is_queue_screen) {
    struct MonitorData {
      bool found_second = false;
      RECT second_rect = {0, 0, 0, 0};
    };

    struct MonitorEnumHelper {
      static BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor, HDC hdcMonitor, LPRECT lprcMonitor, LPARAM dwData) {
        MonitorData* data = reinterpret_cast<MonitorData*>(dwData);
        MONITORINFO info = {};
        info.cbSize = sizeof(info);
        if (GetMonitorInfo(hMonitor, &info)) {
          if (!(info.dwFlags & MONITORINFOF_PRIMARY)) {
            data->found_second = true;
            data->second_rect = info.rcMonitor;
            return FALSE; // Stop enumeration
          }
        }
        return TRUE;
      }
    };

    MonitorData data;
    EnumDisplayMonitors(nullptr, nullptr, MonitorEnumHelper::MonitorEnumProc, reinterpret_cast<LPARAM>(&data));
    if (data.found_second) {
      origin.x = data.second_rect.left + 10;
      origin.y = data.second_rect.top + 10;
    }
  }

  if (!window.Create(L"hotel_pos", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
