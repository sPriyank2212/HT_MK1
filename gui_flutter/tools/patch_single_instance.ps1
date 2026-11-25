# Makes the Windows runner single-instance: a second launch brings the first
# window to the front and exits instead of opening another window.
#
# windows\ is generated (and git-ignored), so this patches the generated
# windows\runner\main.cpp; it is safe to run on every build (does nothing when
# the guard is already there). Called from build_exe.cmd and build_client_exe.cmd.
#
# (A name with no "Local\" prefix is already per logon session.)
# The mutex name contains the window title, and the build scripts rewrite the
# title literal per app, so the console and the client app each allow one
# window of their own, not one between them.
param([string]$Path = 'windows\runner\main.cpp')

$t = Get-Content -LiteralPath $Path -Raw
if ($t -match 'CreateMutexW') { Write-Host "single-instance guard already present"; return }

# 1. the title becomes one constant
if ($t -notmatch 'window\.Create\(L"([^"]*)"') { throw "main.cpp: window.Create(L`"...`") not found" }
$title = $Matches[1]
$t = $t -replace 'window\.Create\(L"[^"]*"', 'window.Create(kAppTitle'
$t = $t -replace '(#include <windows\.h>)', "`$1`r`n#include <string>"
$t = $t -replace '(int APIENTRY wWinMain)', "static const wchar_t kAppTitle[] = L`"$title`";`r`n`r`n`$1"

# 2. the guard, first thing in wWinMain
$guard = @'

  // One window only: a second launch brings the first one forward and exits.
  std::wstring mutex_name =
      std::wstring(L"HT_MK1_SingleInstance_") + kAppTitle;
  for (auto &ch : mutex_name) {
    if (ch == L' ') ch = L'_';
  }
  HANDLE single_instance = ::CreateMutexW(nullptr, TRUE, mutex_name.c_str());
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kAppTitle);
    if (existing != nullptr) {
      if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
'@
$guard = $guard -replace "`r?`n", "`r`n"
$t = $t -replace '(int show_command\)\s*\{)', "`$1$guard"
if ($t -notmatch 'CreateMutexW') { throw "main.cpp: could not insert the guard" }
Set-Content -LiteralPath $Path -Value $t -Encoding utf8
Write-Host "single-instance guard added to $Path (title: $title)"
