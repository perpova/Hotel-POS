import 'dart:ffi';
import 'package:flutter/foundation.dart';

class WindowHelper {
  static bool _isFullScreen = false;
  static bool get isFullScreen => _isFullScreen;

  static int _savedStyle = 0;

  static void enableFullScreen() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (!_isFullScreen) {
      _performToggle();
    }
  }

  static void disableFullScreen() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (_isFullScreen) {
      _performToggle();
    }
  }

  static void toggleFullScreen() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    _performToggle();
  }

  static void _performToggle() {
    try {
      final user32 = DynamicLibrary.open('user32.dll');

      final getActiveWindow = user32.lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow');
      final getWindowLong = user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('GetWindowLongA');
      final setWindowLong = user32.lookupFunction<Int32 Function(IntPtr, Int32, Int32), int Function(int, int, int)>('SetWindowLongA');
      final setWindowPos = user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
          int Function(int, int, int, int, int, int, int)>('SetWindowPos');
      final getSystemMetrics = user32.lookupFunction<Int32 Function(Int32), int Function(int)>('GetSystemMetrics');
      final showWindow = user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');

      final hwnd = getActiveWindow();
      if (hwnd == 0) return;

      const GWL_STYLE = -16;
      const WS_OVERLAPPEDWINDOW = 0x00CF0000;
      const WS_POPUP = 0x80000000;
      const WS_VISIBLE = 0x10000000;

      const SWP_SHOWWINDOW = 0x0040;
      const SWP_FRAMECHANGED = 0x0020;

      const SM_CXSCREEN = 0;
      const SM_CYSCREEN = 1;

      if (!_isFullScreen) {
        // Enter Fullscreen: Save current style, hide title bar & borders, expand window
        final currentStyle = getWindowLong(hwnd, GWL_STYLE);
        if (currentStyle != 0 && currentStyle != (WS_POPUP | WS_VISIBLE)) {
          _savedStyle = currentStyle;
        }

        final screenWidth = getSystemMetrics(SM_CXSCREEN);
        final screenHeight = getSystemMetrics(SM_CYSCREEN);

        setWindowLong(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
        setWindowPos(hwnd, 0, 0, 0, screenWidth, screenHeight, SWP_SHOWWINDOW | SWP_FRAMECHANGED);

        _isFullScreen = true;
      } else {
        // Exit Fullscreen: Restore standard window title bar & border
        final style = _savedStyle != 0 ? _savedStyle : (WS_OVERLAPPEDWINDOW | WS_VISIBLE);
        setWindowLong(hwnd, GWL_STYLE, style);

        showWindow(hwnd, 9); // SW_RESTORE
        setWindowPos(hwnd, 0, 50, 50, 1280, 800, SWP_SHOWWINDOW | SWP_FRAMECHANGED);

        _isFullScreen = false;
      }
    } catch (e) {
      debugPrint('WindowHelper toggle error: $e');
    }
  }
}
