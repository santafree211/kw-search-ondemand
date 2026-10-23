@echo off
setlocal
cd /d "%~dp0"

echo ==========================================================
echo === KW-SEARCH DAILY AUTONOMOUS PIPELINE LAUNCHER ===
echo ==========================================================
echo Starting daily search, SERP evaluation, sheet update, and audit...
echo Workspace: %CD%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "tools\run_daily_package.ps1" %*

set EXIT_CODE=%ERRORLEVEL%
echo.
echo ==========================================================
echo Process exited with code: %EXIT_CODE%
echo ==========================================================

if "%1"=="--no-pause" goto end
if "%2"=="--no-pause" goto end
pause

:end
exit /b %EXIT_CODE%
