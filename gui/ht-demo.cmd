@echo off
rem Simulator + GUI together, for a demo or for GUI work without hardware.
rem
rem Opens the simulator in its own window, waits for it to bind, then starts
rem the GUI in this one. Close this window to stop the GUI; close the other to
rem stop the simulator.

cd /d "%~dp0"
start "HT_MK1 simulator" cmd /k python -m htproto.simulator --scenario pass --port 46000

rem Give the simulator a moment to bind before the GUI tries to connect. The
rem GUI survives connecting early - it just shows "link lost" until you press
rem connect - but starting clean is nicer.
timeout /t 2 /nobreak >nul

python -m htweb --port 46000
