@echo off
rem Start the HT_MK1 operator GUI.
rem
rem Works from any directory, and by double-clicking, because it changes to its
rem own folder first: the htproto / htweb packages live next to this file and
rem "python -m" only finds them from there. Running the module by hand from
rem gui\tests fails with ModuleNotFoundError for exactly that reason.
rem
rem Any arguments are passed straight through, e.g.
rem     ht-gui.cmd --port 46000 --http-port 8770

cd /d "%~dp0"
python -m htweb %*
if errorlevel 1 (
  echo.
  echo GUI exited with an error. If this says "No module named htweb", the
  echo working directory is wrong - run this script rather than the module.
  pause
)
