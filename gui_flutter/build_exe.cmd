@echo off
rem ===========================================================================
rem  HT_MK1 Console - source to independent executable, in one script.
rem
rem    build_exe.cmd [--skip-tests] [--skip-analyze]
rem
rem  From a fresh checkout this will:
rem    1. check the toolchain and say exactly what is missing
rem    2. generate the windows\ runner (not in the repo - it is SDK-specific)
rem    3. fetch packages
rem    4. analyze and run the test suite
rem    5. build the release
rem    6. package it as portable single-file executables in dist\
rem
rem  Produces:
rem    dist\HT_MK1_GUI.exe        connects to the instrument on the ST-LINK VCP
rem    dist\HT_MK1_GUI_demo.exe   built-in simulator, no hardware
rem
rem  Both are independent: copy either to any Windows 10/11 x64 machine and
rem  double-click. No Flutter, no Python, no runtime required on the target.
rem
rem  NOTE: plain setlocal, deliberately. With `enabledelayedexpansion` cmd eats
rem  the `!` in the SFX config's `;!@Install@!UTF-8!` marker, and the resulting
rem  exe extracts but silently never launches the app.
rem ===========================================================================
setlocal
cd /d "%~dp0"

set "SKIP_TESTS="
set "SKIP_ANALYZE="
:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--skip-tests"   set "SKIP_TESTS=1"
if /i "%~1"=="--skip-analyze" set "SKIP_ANALYZE=1"
shift
goto parse
:parsed

set "REL=build\windows\x64\runner\Release"
set "SFX=tools\7zsd_LZMA2_x64.sfx"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

echo ============================================================
echo  [1/6] checking the toolchain
echo ============================================================

rem ---- Flutter SDK ----------------------------------------------------------
rem A terminal opened before the SDK was installed does not see it, even though
rem it is on the user PATH - which is far and away the most common way this
rem script appears to "fail". So go and look before giving up.
set "FLUTTER_BIN="
where flutter >nul 2>&1
if not errorlevel 1 goto flutter_ok

for %%d in (
  "%LOCALAPPDATA%\flutter\bin"
  "%USERPROFILE%\flutter\bin"
  "%USERPROFILE%\dev\flutter\bin"
  "%USERPROFILE%\Documents\flutter\bin"
  "C:\flutter\bin"
  "C:\src\flutter\bin"
  "C:\tools\flutter\bin"
) do if not defined FLUTTER_BIN if exist "%%~d\flutter.bat" set "FLUTTER_BIN=%%~d"

if not defined FLUTTER_BIN call :scan_user_path
if not defined FLUTTER_BIN goto no_flutter

set "PATH=%FLUTTER_BIN%;%PATH%"
echo   (this terminal predates the install - using %FLUTTER_BIN%)

:flutter_ok
for /f "tokens=1,2" %%a in ('flutter --version 2^>nul ^| findstr /b /c:"Flutter"') do set "FLUTTER_VER=%%b"
echo   Flutter SDK           %FLUTTER_VER%

rem ---- Developer Mode (Flutter needs symlinks to build any plugin) ----------
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2>nul | findstr /c:"0x1" >nul
if errorlevel 1 goto no_devmode
echo   Developer Mode        on

rem ---- Visual Studio C++ workload ------------------------------------------
if not exist "%VSWHERE%" goto no_msvc
set "VSPATH="
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath 2^>nul`) do set "VSPATH=%%i"
if not defined VSPATH goto no_msvc
echo   Visual Studio C++     found

rem ---- 7-Zip (to compress the payload) -------------------------------------
set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"
if not exist "%SEVENZIP%" set "SEVENZIP=%ProgramFiles(x86)%\7-Zip\7z.exe"
if exist "%SEVENZIP%" goto have_7zip
echo   7-Zip                 missing - installing via winget...
where winget >nul 2>&1
if errorlevel 1 goto no_7zip
call winget install --id 7zip.7zip -e --accept-source-agreements --accept-package-agreements
set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"
if not exist "%SEVENZIP%" goto no_7zip
:have_7zip
echo   7-Zip                 ok

rem ---- the SFX stub --------------------------------------------------------
if not exist "%SFX%" goto no_sfx
echo   SFX stub              ok

rem ---------------------------------------------------------------------------
echo.
echo ============================================================
echo  [2/6] platform scaffolding
echo ============================================================
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
rem 1280x720, and names the exe ht_mk1_gui. Fix all three.
powershell -NoProfile -Command ^
  "$p='windows/runner/main.cpp'; $t=Get-Content $p -Raw;" ^
  "$t=$t -replace 'L\"ht_mk1_gui\"','L\"HT_MK1 Console\"';" ^
  "$t=$t -replace 'Win32Window::Size size\(1280, 720\)','Win32Window::Size size(1480, 940)';" ^
  "Set-Content $p -Value $t -Encoding utf8"
powershell -NoProfile -Command ^
  "$p='windows/CMakeLists.txt'; $t=Get-Content $p -Raw;" ^
  "$t=$t -replace 'set\(BINARY_NAME \"ht_mk1_gui\"\)','set(BINARY_NAME \"HT_MK1_GUI\")';" ^
  "Set-Content $p -Value $t -Encoding utf8"
powershell -NoProfile -Command ^
  "$p='windows/runner/Runner.rc'; $t=Get-Content $p -Raw;" ^
  "$t=$t -replace '\"CompanyName\", \"com.example\"','\"CompanyName\", \"HT_MK1\"';" ^
  "$t=$t -replace '\"FileDescription\", \"ht_mk1_gui\"','\"FileDescription\", \"HT_MK1 Console - harness test system\"';" ^
  "$t=$t -replace '\"InternalName\", \"ht_mk1_gui\"','\"InternalName\", \"HT_MK1_GUI\"';" ^
  "$t=$t -replace '\"OriginalFilename\", \"ht_mk1_gui.exe\"','\"OriginalFilename\", \"HT_MK1_GUI.exe\"';" ^
  "$t=$t -replace '\"ProductName\", \"ht_mk1_gui\"','\"ProductName\", \"HT_MK1 Console\"';" ^
  "Set-Content $p -Value $t -Encoding utf8"
goto scaffold_done

:have_windows
echo   windows\ already present - reusing
:scaffold_done

rem ---------------------------------------------------------------------------
echo.
echo ============================================================
echo  [3/6] packages
echo ============================================================
call flutter pub get
if errorlevel 1 goto fail

rem ---------------------------------------------------------------------------
echo.
echo ============================================================
echo  [4/6] analyze and test
echo ============================================================
if defined SKIP_ANALYZE goto skip_analyze
call flutter analyze
if errorlevel 1 goto fail_analyze
:skip_analyze
if defined SKIP_TESTS goto skip_tests
call flutter test
if errorlevel 1 goto fail_test
:skip_tests

rem ---------------------------------------------------------------------------
echo.
echo ============================================================
echo  [5/6] release build
echo ============================================================
call flutter build windows --release
if errorlevel 1 goto fail
if not exist "%REL%\HT_MK1_GUI.exe" goto no_binary

rem ---------------------------------------------------------------------------
echo.
echo ============================================================
echo  [6/6] packaging
echo ============================================================
if exist dist rmdir /s /q dist
mkdir dist

echo   compressing payload ...
rem Archive the CONTENTS of Release, so the SFX extracts them flat into its
rem temp directory and RunProgram can name the exe directly.
if exist "%TEMP%\ht_mk1_payload.7z" del "%TEMP%\ht_mk1_payload.7z"
"%SEVENZIP%" a -t7z -m0=lzma2 -mx=9 -ms=on "%TEMP%\ht_mk1_payload.7z" ".\%REL%\*" >nul
if errorlevel 1 goto fail

echo   writing SFX configs ...
> "%TEMP%\ht_cfg_main.txt" (
  echo ;!@Install@!UTF-8!
  echo Title="HT_MK1 Console"
  echo RunProgram="HT_MK1_GUI.exe --serial auto"
  echo GUIMode="2"
  echo ;!@InstallEnd@!
)
> "%TEMP%\ht_cfg_demo.txt" (
  echo ;!@Install@!UTF-8!
  echo Title="HT_MK1 Console (demo)"
  echo RunProgram="HT_MK1_GUI.exe --sim"
  echo GUIMode="2"
  echo ;!@InstallEnd@!
)

rem A mangled config still assembles into an exe that extracts and then quietly
rem does nothing, so check the marker survived before shipping it.
findstr /c:";!@Install@!UTF-8!" "%TEMP%\ht_cfg_main.txt" >nul
if errorlevel 1 goto fail_config

echo   assembling ...
copy /b "%SFX%" + "%TEMP%\ht_cfg_main.txt" + "%TEMP%\ht_mk1_payload.7z" "dist\HT_MK1_GUI.exe" >nul
copy /b "%SFX%" + "%TEMP%\ht_cfg_demo.txt" + "%TEMP%\ht_mk1_payload.7z" "dist\HT_MK1_GUI_demo.exe" >nul
del "%TEMP%\ht_mk1_payload.7z" "%TEMP%\ht_cfg_main.txt" "%TEMP%\ht_cfg_demo.txt" >nul 2>&1

if not exist "dist\HT_MK1_GUI.exe" goto fail
echo.
echo ============================================================
echo  done
echo ============================================================
for %%F in (dist\*.exe) do echo   %%~nxF   %%~zF bytes
echo.
echo  Copy either to any Windows 10/11 x64 machine and double-click.
echo  Nothing needs installing on the target.
echo.
echo  They unpack to a temp folder on each launch, so first paint takes a
echo  second or two longer than the folder build in
echo    %REL%
echo  which is the same bits if you would rather ship a folder.
echo.
endlocal
exit /b 0

rem ---------------------------------------------------------------------------
rem  helpers
rem ---------------------------------------------------------------------------
:scan_user_path
rem Last resort: read the user PATH straight out of the registry, which is what
rem a NEW terminal would have been given. Entries holding unexpanded %VARS%
rem simply will not match, which is harmless - the candidate list above already
rem covers the usual homes.
set "UPATH="
for /f "tokens=2,*" %%a in ('reg query "HKCU\Environment" /v Path 2^>nul ^| findstr /i "REG_"') do set "UPATH=%%b"
if not defined UPATH goto :eof
for %%p in ("%UPATH:;=" "%") do if not defined FLUTTER_BIN if exist "%%~p\flutter.bat" set "FLUTTER_BIN=%%~p"
goto :eof

rem ---------------------------------------------------------------------------
rem  failure paths
rem ---------------------------------------------------------------------------
:no_flutter
echo.
echo   Flutter SDK not found - not on PATH, and not in any of the usual
echo   install locations.
echo     https://docs.flutter.dev/get-started/install/windows
echo.
echo   If it IS installed, the SDK is somewhere unusual: open a NEW terminal
echo   (one opened before the install has a stale PATH), or add its bin folder
echo   to PATH and re-run.
goto die

:no_devmode
echo.
echo   Developer Mode is off.
echo   Flutter cannot build ANY plugin without it - it symlinks plugin sources
echo   into the build tree, and unprivileged symlinks need Developer Mode.
echo   This project uses flutter_libserialport, so it is required.
echo.
echo     start ms-settings:developers      then turn Developer Mode on
echo.
echo   Or build once from an elevated terminal, which can symlink anyway.
goto die

:no_msvc
echo.
echo   Visual Studio with the "Desktop development with C++" workload not found.
echo   flutter build windows compiles a C++ runner and needs MSVC.
echo.
echo     winget install --id Microsoft.VisualStudio.2022.Community -e --override "--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended"
echo.
echo   Use Community, not BuildTools: flutter doctor looks for the
echo   NativeDesktop workload specifically.
goto die

:no_7zip
echo.
echo   7-Zip not found and could not be installed automatically.
echo     winget install 7zip.7zip
echo   It is only needed to compress the payload, not at runtime.
goto die

:no_sfx
echo.
echo   Missing %SFX%
echo   That is the 7-Zip SFX-Modified stub, which supports RunProgram. Stock
echo   7-Zip ships extract-only modules. See tools\README.md.
goto die

:no_binary
echo.
echo   Expected %REL%\HT_MK1_GUI.exe but it is not there.
echo   If windows\ was scaffolded before this script set BINARY_NAME, delete
echo   the windows\ folder and re-run.
goto die

:fail_analyze
echo.
echo   flutter analyze reported issues. Fix them, or pass --skip-analyze if you
echo   are deliberately packaging a work in progress.
goto die

:fail_test
echo.
echo   Tests failed. Fix them, or pass --skip-tests to package anyway.
echo   test\layout_test.dart in particular catches rendering overflows that
echo   analyze cannot see - do not skip it lightly.
goto die

:fail_config
echo.
echo   The SFX config lost its ;!@Install@! marker. If this script was edited,
echo   check that setlocal is NOT using enabledelayedexpansion - cmd eats `!`.
goto die

:fail
echo.
echo   Build failed - see the output above.
goto die

:die
echo.
endlocal
exit /b 1
