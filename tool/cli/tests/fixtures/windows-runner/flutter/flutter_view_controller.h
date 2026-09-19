#pragma once
#include <windows.h>
#include <optional>
#include <functional>
#include "dart_project.h"
#include "plugin_registry.h"
namespace flutter {
inline int font_reloads = 0;
class FlutterEngine : public PluginRegistry {
 public:
  int reloads = 0;
  void ReloadSystemFonts() { ++reloads; ++font_reloads; }
  void SetNextFrameCallback(std::function<void()>) {}
};
class FlutterView {
 public:
  FlutterView() : window_(CreateWindowW(L"STATIC", L"test", 0, 0, 0, 20, 20,
                                      nullptr, nullptr, GetModuleHandleW(nullptr), nullptr)) {}
  ~FlutterView() { if (IsWindow(window_)) DestroyWindow(window_); }
  HWND GetNativeWindow() { return window_; }
 private:
  HWND window_;
};
class FlutterViewController {
 public:
  FlutterViewController(int, int, const DartProject&) {}
  FlutterEngine* engine() { return &engine_; }
  FlutterView* view() { return &view_; }
  std::optional<LRESULT> HandleTopLevelWindowProc(HWND, UINT, WPARAM, LPARAM) { return std::nullopt; }
  void ForceRedraw() {}
 private:
  FlutterEngine engine_;
  FlutterView view_;
};
}
