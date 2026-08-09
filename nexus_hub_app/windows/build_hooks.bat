@echo off
REM Rebuild the Go c-shared DLLs used by the Flutter Windows app and stage
REM them in this directory so windows/CMakeLists.txt can install them next to
REM the runner exe.
REM
REM NOTE: GOTMPDIR is pointed inside the repo because Windows Defender's
REM real-time protection flags Go c-shared output written to the system temp
REM directory. Building inside the repo (which is usually excluded/trusted)
REM avoids the "contains a virus" error.
setlocal
cd /d "%~dp0"

echo Building network_monitor.dll ...
set GOTMPDIR=%CD%\network_monitor\tmp
if not exist "%GOTMPDIR%" mkdir "%GOTMPDIR%"
pushd network_monitor
go build -buildmode=c-shared -o ..\network_monitor.dll .
if errorlevel 1 goto :err
popd

echo Building input_hook.dll ...
set GOTMPDIR=%CD%\hooks\tmp
if not exist "%GOTMPDIR%" mkdir "%GOTMPDIR%"
pushd hooks
go build -buildmode=c-shared -o ..\input_hook.dll input_hook.go
if errorlevel 1 goto :err
popd

echo Done. DLLs staged in %CD%
exit /b 0

:err
popd
echo BUILD FAILED
exit /b 1
