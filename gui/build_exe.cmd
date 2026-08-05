@echo off
rem Build HT_MK1_GUI.exe — a standalone Windows executable.
rem
rem The RESULT needs no Python on the target machine. Building it does:
rem PyInstaller is a build-time dependency only.
rem
rem     pip install pyinstaller
rem     build_exe.cmd
rem
rem Output: dist\HT_MK1_GUI.exe
rem
rem index.html and live.js are data files, not code, so they must be added
rem explicitly - PyInstaller's import analysis cannot see them. htproto.simulator
rem likewise, because nothing imports it until --sim is passed at runtime.

cd /d "%~dp0"

rem A running copy holds dist\HT_MK1_GUI.exe open and the build dies with
rem "PermissionError: Access is denied" on the final link step. Close it first.
taskkill /IM HT_MK1_GUI.exe /F >nul 2>&1

python -m PyInstaller --noconfirm --clean ^
  --onefile ^
  --name HT_MK1_GUI ^
  --add-data "htweb\index.html;htweb" ^
  --add-data "htweb\live.js;htweb" ^
  --hidden-import htproto.simulator ^
  --collect-submodules htproto ^
  ht_gui_exe.py

if errorlevel 1 (
  echo.
  echo BUILD FAILED. If PyInstaller is missing:  pip install pyinstaller
  pause
  exit /b 1
)

echo.
echo Built dist\HT_MK1_GUI.exe
echo   HT_MK1_GUI.exe              connect to a real instrument on port 46000
echo   HT_MK1_GUI.exe --sim        demo mode, built-in simulator, no hardware
echo.
