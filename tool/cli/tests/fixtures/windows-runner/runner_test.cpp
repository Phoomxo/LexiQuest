// Compiles the actual runner translation units. Only the Flutter engine is a
// test double; HWND creation, WndProc dispatch and UTF-16 conversion use Win32.
#include <windows.h>
#include <cstdlib>
#include <cstdio>
#include <new>
#include <string>
#include "runner/utils.h"
#include "runner/flutter_window.h"

static bool bound_allocations = false;
static size_t rejected_allocation = 0;
void* operator new(size_t size) {
  if (bound_allocations && size > 1024 * 1024) {
    rejected_allocation = size;
    throw std::bad_alloc();
  }
  if (auto result = std::malloc(size ? size : 1)) return result;
  throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, size_t) noexcept { std::free(p); }
void RegisterPlugins(flutter::PluginRegistry*) {}
std::string F01FailedQuery(const wchar_t*);

class LifecycleWindow : public FlutterWindow {
 public:
  LifecycleWindow(const flutter::DartProject& p, std::wstring mode)
      : FlutterWindow(p), mode_(mode) {}
 protected:
  bool OnCreate() override {
    if (mode_ == L"font-before") Dispatch("before controller initialization");
    return FlutterWindow::OnCreate();
  }
  void OnDestroy() override {
    FlutterWindow::OnDestroy();
    if (mode_ == L"font-after" && GetHandle() && !sent_after_) {
      sent_after_ = true;
      Dispatch("after controller release before HWND destruction");
    }
  }
 private:
  void Dispatch(const char* stage) {
    std::printf("actual SendMessageW WM_FONTCHANGE: %s HWND=%p\n", stage, GetHandle());
    std::fflush(stdout);
    SendMessageW(GetHandle(), WM_FONTCHANGE, 0, 0);
  }
  std::wstring mode_;
  bool sent_after_ = false;
};

int wmain(int argc, wchar_t** argv) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  if (argc < 2) return 2;
  const std::wstring mode(argv[1]);
  if (mode == L"utf16-positive") {
    if (Utf8FromUtf16(nullptr) != "" || Utf8FromUtf16(L"") != "" ||
        Utf8FromUtf16(L"hello") != "hello" ||
        Utf8FromUtf16(L"\u0e44\u0e17\u0e22") != u8"\u0e44\u0e17\u0e22" ||
        Utf8FromUtf16(L"\U0001f600") != u8"\U0001f600") return 1;
  } else if (mode == L"utf16-invalid" || mode == L"utf16-query" || mode == L"utf16-cli") {
    const wchar_t malformed[] = {0xd800, 0};
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, malformed, -1,
                            nullptr, 0, nullptr, nullptr) != 0) return 3;
    bound_allocations = true;
    try {
      if (mode == L"utf16-cli") {
        if (argc != 3 || argv[2][0] != 0xd800) return 4;
        std::puts("actual invalid UTF-16 command-line argument reaches GetCommandLineArguments");
        const auto args = GetCommandLineArguments();
        if (args.size() != 2 || !args[1].empty()) return 5;
      } else {
        const auto result = mode == L"utf16-query" ? F01FailedQuery(L"valid") : Utf8FromUtf16(malformed);
        if (!result.empty()) return 6;
      }
    } catch (const std::bad_alloc&) {
      std::printf("FAIL: intercepted oversized allocation=%zu; no allocation performed\n", rejected_allocation);
      return 1;
    }
  } else {
    flutter::DartProject project;
    LifecycleWindow window(project, mode);
    if (!window.Create(L"F01 hidden test", {0, 0}, {40, 40})) return 7;
    if (mode == L"font-normal") {
      SendMessageW(window.GetHandle(), WM_FONTCHANGE, 0, 0);
      if (flutter::font_reloads != 1) return 8;
    }
    window.Destroy();
    if (mode != L"font-normal" && flutter::font_reloads != 0) return 9;
  }
  std::puts("PASS");
  return 0;
}
