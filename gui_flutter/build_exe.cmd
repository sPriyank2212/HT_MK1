@echo off
rem ===========================================================================
rem  build_exe.cmd - Integrated Harness Tester MKI, source to .exe
rem
rem  The customer's window layout, terminology and PDF/CSV report format.
rem  Entry point: lib\main.dart.
rem
rem  Produces, in dist\:
rem    Harness_Tester.exe        real hardware: --serial auto
rem    Harness_Tester_demo.exe   built-in simulator: --sim (no instrument)
rem
rem  Usage:
rem    build_exe.cmd                run analyze + tests, then build
rem    build_exe.cmd --skip-tests
rem    build_exe.cmd --skip-analyze
rem
rem  Needs Flutter, the Visual Studio C++ workload, Developer Mode and 7-Zip.
rem  On a fresh checkout it generates the windows\ runner itself (windows\ is
rem  git-ignored; it is re-created from the Flutter scaffold plus the patches below).
rem ===========================================================================
setlocal

set "SKIP_TESTS="
set "SKIP_ANALYZE="
:args
if "%~1"=="" goto args_done
if /i "%~1"=="--skip-tests"   set "SKIP_TESTS=1"
if /i "%~1"=="--skip-analyze" set "SKIP_ANALYZE=1"
shift
goto args
:args_done

cd /d "%~dp0"

for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "Get-Date -Format yyyy-MM-ddTHH:mm:ss"`) do set "BUILD_STAMP=%%t"
if not defined BUILD_STAMP set "BUILD_STAMP=unstamped"

set "REL=build\windows\x64\runner\Release"
set "SFX=tools\7zsd_LZMA2_x64.sfx"
set "MAINCPP=windows\runner\main.cpp"

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: flutter is not on PATH. Install the Flutter SDK, or run build_exe.cmd which searches for it.
  exit /b 1
)
if exist "windows\CMakeLists.txt" goto have_windows
echo   generating windows\ ...
rem Scaffold into a scratch directory and copy only windows\ back, so lib\,
rem test\ and pubspec.yaml are never touched by `flutter create`.
set "SCRATCH=%TEMP%\ht_mk1_scaffold_%RANDOM%"
call flutter create --platforms=windows --project-name ht_mk1_gui "%SCRATCH%"
if errorlevel 1 goto fail
xcopy /e /i /q /y "%SCRATCH%\windows" "windows" >nul
if exist "%SCRATCH%\.metadata" copy /y "%SCRATCH%\.metadata" ".metadata" >nul
rmdir /s /q "%SCRATCH%"

rem The generated runner titles the window with the project name, opens at
rem 1280x720, and names the exe ht_mk1_gui. Fix all of that.
powershell -NoProfile -Command ^
  "$p='windows/runner/main.cpp'; $t=Get-Content $p -Raw;" ^
  "$t=$t -replace 'L\"ht_mk1_gui\"','L\"Integrated Harness Tester MKI\"';" ^
  "$t=$t -replace 'Win32Window::Size size\(1280, 720\)','Win32Window::Size size(1480, 940)';" ^
  "Set-Content $p -Value $t -Encoding utf8"
powershell -NoProfile -Command ^
  "$p='windows/CMakeLists.txt'; $t=Get-Content $p -Raw;" ^
  "$t=$t -replace 'set\(BINARY_NAME \"ht_mk1_gui\"\)','set(BINARY_NAME \"HT_MK1_GUI\")';" ^
  "Set-Content $p -Value $t -Encoding utf8"
powershell -NoProfile -Command ^
  "$p='windows/runner/Runner.rc'; $t=Get-Content $p -Raw;" ^
  "$t=$t -replace '\"CompanyName\", \"com.example\"','\"CompanyName\", \"HT_MK1\"';" ^
  "$t=$t -replace '\"FileDescription\", \"ht_mk1_gui\"','\"FileDescription\", \"Integrated Harness Tester MKI\"';" ^
  "$t=$t -replace '\"InternalName\", \"ht_mk1_gui\"','\"InternalName\", \"HT_MK1_GUI\"';" ^
  "$t=$t -replace '\"OriginalFilename\", \"ht_mk1_gui.exe\"','\"OriginalFilename\", \"HT_MK1_GUI.exe\"';" ^
  "$t=$t -replace '\"ProductName\", \"ht_mk1_gui\"','\"ProductName\", \"Integrated Harness Tester MKI\"';" ^
  "Set-Content $p -Value $t -Encoding utf8"
rem Open maximized, and use the company logo as the window/taskbar/exe icon.
powershell -NoProfile -Command ^
  "$p='windows/runner/win32_window.cpp'; $t=Get-Content $p -Raw;" ^
  "$t=$t -replace 'SW_SHOWNORMAL','SW_SHOWMAXIMIZED';" ^
  "Set-Content $p -Value $t -Encoding utf8"
copy /y "tools\app_icon.ico" "windows\runner\resources\app_icon.ico" >nul
:have_windows
if not exist "%SFX%" (
  echo ERROR: %SFX% is missing.
  exit /b 1
)

set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"
if not exist "%SEVENZIP%" set "SEVENZIP=%ProgramFiles(x86)%\7-Zip\7z.exe"
if not exist "%SEVENZIP%" set "SEVENZIP=%ProgramData%\chocolatey\tools\7z.exe"
if not exist "%SEVENZIP%" set "SEVENZIP=%LOCALAPPDATA%\scoop\apps\7zip\current\7z.exe"
if not exist "%SEVENZIP%" (
  echo ERROR: 7-Zip not found. Install it ^(winget install 7zip.7zip^) and re-run.
  exit /b 1
)

echo ============================================================
echo  [1/4] packages
echo ============================================================
call flutter pub get
if errorlevel 1 goto fail

echo.
echo ============================================================
echo  [2/4] analyze and test
echo ============================================================
if defined SKIP_ANALYZE goto skip_analyze
call flutter analyze
if errorlevel 1 goto fail
:skip_analyze
if defined SKIP_TESTS goto skip_tests
call flutter test
if errorlevel 1 goto fail
:skip_tests

echo.
echo ============================================================
echo  [3/4] release build
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File tools\patch_single_instance.ps1 -Path %MAINCPP%
call flutter build windows --release "--dart-define=BUILD_STAMP=%BUILD_STAMP%" --dart-define=CUSTOMER_BUILD=true
set "BUILD_RC=%ERRORLEVEL%"
if not "%BUILD_RC%"=="0" goto fail
if not exist "%REL%\HT_MK1_GUI.exe" (
  echo ERROR: the build reported success but %REL%\HT_MK1_GUI.exe is missing.
  goto fail
)

echo.
echo ============================================================
echo  [4/4] packaging
echo ============================================================
if not exist dist mkdir dist
if exist "%TEMP%\ht_client_payload.7z" del "%TEMP%\ht_client_payload.7z"
"%SEVENZIP%" a -t7z -m0=lzma2 -mx=9 -ms=on "%TEMP%\ht_client_payload.7z" ".\%REL%\*" >nul
if errorlevel 1 goto fail

> "%TEMP%\ht_client_main.txt" (
  echo ;!@Install@!UTF-8!
  echo Title="Integrated Harness Tester MKI"
  echo RunProgram="HT_MK1_GUI.exe --serial auto"
  echo GUIMode="2"
  echo ;!@InstallEnd@!
)
> "%TEMP%\ht_client_demo.txt" (
  echo ;!@Install@!UTF-8!
  echo Title="Integrated Harness Tester MKI (demo)"
  echo RunProgram="HT_MK1_GUI.exe --sim"
  echo GUIMode="2"
  echo ;!@InstallEnd@!
)
findstr /c:";!@Install@!UTF-8!" "%TEMP%\ht_client_main.txt" >nul
if errorlevel 1 (
  echo ERROR: the SFX configuration was mangled.
  goto fail
)

copy /b "%SFX%" + "%TEMP%\ht_client_main.txt" + "%TEMP%\ht_client_payload.7z" "dist\Harness_Tester.exe" >nul
copy /b "%SFX%" + "%TEMP%\ht_client_demo.txt" + "%TEMP%\ht_client_payload.7z" "dist\Harness_Tester_demo.exe" >nul
del "%TEMP%\ht_client_payload.7z" "%TEMP%\ht_client_main.txt" "%TEMP%\ht_client_demo.txt" >nul 2>&1
if not exist "dist\Harness_Tester.exe" goto fail

echo.
echo ============================================================
echo  DONE
echo ============================================================
for %%F in (dist\Harness_Tester*.exe) do echo   %%~nxF   %%~zF bytes
exit /b 0

:fail
echo.
echo BUILD FAILED
exit /b 1
