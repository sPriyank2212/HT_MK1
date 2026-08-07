@echo off
rem ---------------------------------------------------------------------------
rem Generate the Windows platform scaffolding for gui_flutter.
rem
rem `lib\`, `test\` and `pubspec.yaml` are hand-written and must not be touched,
rem so this scaffolds into a scratch directory and copies only `windows\` and
rem `.metadata` back. Nothing under this folder is overwritten.
rem
rem Run once, after installing the Flutter SDK. Safe to re-run.
rem ---------------------------------------------------------------------------
setlocal enabledelayedexpansion
cd /d "%~dp0"

where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Flutter SDK not found on PATH.
  echo.
  echo   Install it from https://docs.flutter.dev/get-started/install/windows
  echo   and make sure "flutter --version" works in a new terminal, then run
  echo   this script again.
  echo.
  exit /b 1
)

if exist "windows\CMakeLists.txt" (
  echo windows\ already present - skipping scaffold.
  goto :deps
)

set "SCRATCH=%TEMP%\ht_mk1_scaffold_%RANDOM%"
echo Generating the Windows runner in %SCRATCH% ...
rem `call` is required: flutter resolves to flutter.bat, and one batch file
rem invoking another without `call` transfers control and never comes back -
rem the rest of this script would silently not run.
call flutter create --platforms=windows --project-name ht_mk1_gui "%SCRATCH%"
if errorlevel 1 (
  echo flutter create failed.
  exit /b 1
)

echo Copying windows\ into the project ...
xcopy /e /i /q /y "%SCRATCH%\windows" "windows" >nul
if exist "%SCRATCH%\.metadata" copy /y "%SCRATCH%\.metadata" ".metadata" >nul
rmdir /s /q "%SCRATCH%"

rem The generated runner titles the window with the project name and opens at
rem 1280x720. This console wants its real title and enough room for the
rem two-column Run screen (the design's first breakpoint is 1080px).
powershell -NoProfile -Command ^
  "$p='windows/runner/main.cpp';" ^
  "$t=Get-Content $p -Raw;" ^
  "$t=$t -replace 'L\"ht_mk1_gui\"','L\"HT_MK1 Console\"';" ^
  "$t=$t -replace 'Win32Window::Size size\(1280, 720\)','Win32Window::Size size(1480, 940)';" ^
  "Set-Content $p -Value $t -Encoding utf8"

rem Ship as HT_MK1_GUI.exe, the name the Python build used, so the shop-floor
rem shortcut does not change.
powershell -NoProfile -Command ^
  "$p='windows/CMakeLists.txt';" ^
  "$t=Get-Content $p -Raw;" ^
  "$t=$t -replace 'set\(BINARY_NAME \"ht_mk1_gui\"\)','set(BINARY_NAME \"HT_MK1_GUI\")';" ^
  "Set-Content $p -Value $t -Encoding utf8"

:deps
echo.
echo Fetching packages ...
call flutter pub get
if errorlevel 1 exit /b 1

echo.
echo Done. Next:
echo    flutter test                      run the suite
echo    flutter run -d windows --dart-entrypoint-args --sim
echo    flutter build windows --release   build\windows\x64\runner\Release\
echo.
endlocal
