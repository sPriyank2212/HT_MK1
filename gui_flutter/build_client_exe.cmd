@echo off
rem ===========================================================================
rem  build_client_exe.cmd - the client-styled Harness Tester, source to .exe
rem
rem  Same instrument link, protocol and safety rules as the engineering console
rem  (build_exe.cmd), with the customer's own window layout, terminology and
rem  PDF/CSV report format. Entry point: lib\main_client.dart.
rem
rem  Produces, in dist\:
rem    Harness_Tester.exe        real hardware: --serial auto
rem    Harness_Tester_demo.exe   built-in simulator: --sim (no instrument)
rem
rem  Usage:
rem    build_client_exe.cmd                run analyze + tests, then build
rem    build_client_exe.cmd --skip-tests
rem    build_client_exe.cmd --skip-analyze
rem
rem  Needs the same toolchain as build_exe.cmd (Flutter, Visual Studio C++
rem  workload, Developer Mode, 7-Zip). Run build_exe.cmd once first on a fresh
rem  checkout: it scaffolds the windows\ runner this script reuses.
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
if not exist "windows\runner\main.cpp" (
  echo ERROR: windows\ is not scaffolded. Run build_exe.cmd once first.
  exit /b 1
)
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
rem The window caption lives in the C++ runner, which both apps share. Title it
rem for the client for this build only, and put the console's title back after,
rem so the next build_exe.cmd run is unaffected.
powershell -NoProfile -Command "$p='%MAINCPP%'; $t=Get-Content $p -Raw; $t=$t -replace 'L\"HT_MK1 Console\"','L\"Integrated Harness Tester MKI\"'; Set-Content $p -Value $t -Encoding utf8"
call flutter build windows --release -t lib/main_client.dart "--dart-define=BUILD_STAMP=%BUILD_STAMP%" --dart-define=CUSTOMER_BUILD=true
set "BUILD_RC=%ERRORLEVEL%"
powershell -NoProfile -Command "$p='%MAINCPP%'; $t=Get-Content $p -Raw; $t=$t -replace 'L\"Integrated Harness Tester MKI\"','L\"HT_MK1 Console\"'; Set-Content $p -Value $t -Encoding utf8"
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
