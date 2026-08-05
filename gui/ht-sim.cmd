@echo off
rem Start the instrument simulator, for developing without hardware.
rem
rem Changes to its own folder first so it works from anywhere - see ht-gui.cmd.
rem Defaults to the clean-pass scenario on port 46000; override by passing your
rem own arguments, e.g.
rem     ht-sim.cmd --scenario opens_shorts --port 46000

cd /d "%~dp0"
if "%~1"=="" (
  python -m htproto.simulator --scenario pass --port 46000
) else (
  python -m htproto.simulator %*
)
if errorlevel 1 pause
