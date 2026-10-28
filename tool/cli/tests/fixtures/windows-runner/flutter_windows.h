#pragma once
#include <windows.h>
inline UINT FlutterDesktopGetDpiForMonitor(HMONITOR) { return 96; }
inline void FlutterDesktopResyncOutputStreams() {}
