@echo off
rem ---------------------------------------------------------------------------
rem Package the release build as portable single-file executables.
rem
rem Flutter Windows cannot emit a one-file exe the way PyInstaller could: the
rem app lives in flutter_windows.dll (~20 MB) and data\app.so, and the .exe is
rem a 90 KB launcher. So the whole Release tree is wrapped in a self-extracting
rem archive that unpacks to a temp folder and runs the app.
rem
rem Produces, in dist\:
rem   HT_MK1_GUI.exe        connects to the instrument on the ST-LINK VCP
rem   HT_MK1_GUI_demo.exe   built-in simulator, no hardware
rem
rem Two exes rather than one because the SFX runs a fixed command line - the
rem same reason the Python build shipped ht-gui.cmd and ht-demo.cmd.
rem ---------------------------------------------------------------------------
rem NOTE: plain setlocal, deliberately. With `enabledelayedexpansion` cmd eats
rem the `!` in `;!@Install@!UTF-8!`, the SFX config is written mangled, and the
rem resulting exe extracts but silently never launches the app.
setlocal
cd /d "%~dp0"

set "SEVENZIP=C:\Program Files\7-Zip\7z.exe"
set "SFX=tools\7zsd_LZMA2_x64.sfx"
set "REL=build\windows\x64\runner\Release"

where flutter >nul 2>&1 || (echo Flutter SDK not on PATH. & exit /b 1)
if not exist "%SEVENZIP%" (
  echo 7-Zip not found at "%SEVENZIP%".
  echo   winget install 7zip.7zip
  exit /b 1
)
if not exist "%SFX%" (
  echo Missing %SFX%.
  echo It is the 7-Zip SFX-Modified module, which supports RunProgram. The
  echo stock 7-Zip ships only extract-only modules. See tools\README.md.
  exit /b 1
)

echo === building release ===
call flutter build windows --release
if errorlevel 1 exit /b 1
if not exist "%REL%\HT_MK1_GUI.exe" (
  echo Expected %REL%\HT_MK1_GUI.exe - did BINARY_NAME change?
  exit /b 1
)

if exist dist rmdir /s /q dist
mkdir dist

echo.
echo === compressing payload ===
rem Archive the CONTENTS of Release, so the SFX extracts them flat into its
rem temp dir and RunProgram can name the exe directly.
"%SEVENZIP%" a -t7z -m0=lzma2 -mx=9 -ms=on "%TEMP%\ht_mk1_payload.7z" ".\%REL%\*" >nul
if errorlevel 1 exit /b 1

echo === writing SFX configs ===
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

rem Fail loudly if the config lost its markers - a mangled config still
rem assembles into an exe that extracts and then quietly does nothing.
findstr /c:";!@Install@!UTF-8!" "%TEMP%\ht_cfg_main.txt" >nul || (
  echo SFX config is malformed - the ;!@Install@! marker did not survive.
  exit /b 1
)

echo === assembling ===
copy /b "%SFX%" + "%TEMP%\ht_cfg_main.txt" + "%TEMP%\ht_mk1_payload.7z" "dist\HT_MK1_GUI.exe" >nul
copy /b "%SFX%" + "%TEMP%\ht_cfg_demo.txt" + "%TEMP%\ht_mk1_payload.7z" "dist\HT_MK1_GUI_demo.exe" >nul

del "%TEMP%\ht_mk1_payload.7z" "%TEMP%\ht_cfg_main.txt" "%TEMP%\ht_cfg_demo.txt" >nul 2>&1

echo.
for %%F in (dist\*.exe) do echo   %%~nxF  %%~zF bytes
echo.
echo Done. Both are portable: copy anywhere and double-click. They unpack to a
echo temp folder on each launch, so first paint takes a second or two longer
echo than the folder build in %REL%.
echo.
endlocal
