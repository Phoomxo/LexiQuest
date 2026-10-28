#include <windows.h>
int WINAPI F01FailingWideCharToMultiByte(UINT, DWORD, LPCWCH, int, LPSTR, int, LPCCH, LPBOOL) {
  SetLastError(ERROR_NO_UNICODE_TRANSLATION);
  return 0;
}
#define WideCharToMultiByte F01FailingWideCharToMultiByte
#define Utf8FromUtf16 F01FailedQuery
#define CreateAndAttachConsole F01UnusedConsole
#define GetCommandLineArguments F01UnusedArguments
#include "runner/utils.cpp"
