@echo off
setlocal
set "NAS_PREP_PWSH=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
if not exist "%NAS_PREP_PWSH%" exit /b 2
if "%~1"=="" goto status
if /I "%~1"=="Status" goto status
if /I "%~1"=="Start" goto start
if /I "%~1"=="Stop" goto stop
if /I "%~1"=="Test" goto test
exit /b 2
:start
"%NAS_PREP_PWSH%" -NoProfile -File "%~dp0Manage-NasCloud.ps1" -Action Start
exit /b %errorlevel%
:stop
"%NAS_PREP_PWSH%" -NoProfile -File "%~dp0Manage-NasCloud.ps1" -Action Stop
exit /b %errorlevel%
:test
"%NAS_PREP_PWSH%" -NoProfile -File "%~dp0Manage-NasCloud.ps1" -Action Test
exit /b %errorlevel%
:status
"%NAS_PREP_PWSH%" -NoProfile -File "%~dp0Manage-NasCloud.ps1" -Action Status
exit /b %errorlevel%
