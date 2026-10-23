@echo off
rem Builds and runs the host-side firmware logic tests with MSVC (Visual Studio 2022 Community).
rem Run from the repository root:  tests\fw_host\run_tests.cmd
setlocal
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
if not exist tests\fw_host\out mkdir tests\fw_host\out
cl /nologo /W4 /TC /std:c11 /I Core\Inc tests\fw_host\test_run_logic.c Core\Src\app\run_logic.c /Fe:tests\fw_host\out\test_run_logic.exe /Fo:tests\fw_host\out\ || exit /b 1
tests\fw_host\out\test_run_logic.exe
exit /b %errorlevel%
