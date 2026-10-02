@echo off
setlocal
cd /d "%~dp0"

echo ==========================================================
echo === KW-SEARCH ON-DEMAND DESKTOP CONTROLLER ===
echo ==========================================================
echo.
echo [1/3] Detecting Python environment...

set PYTHON_CMD=

where py >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PYTHON_CMD=py -3"
    echo [INFO] Found Python Launcher: py -3
    goto :run
)

where python >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PYTHON_CMD=python"
    echo [INFO] Found Python in PATH: python
    goto :run
)

if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" (
    set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
    echo [INFO] Found Python 3.11: %PYTHON_CMD%
    goto :run
)

if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    echo [INFO] Found Python 3.12: %PYTHON_CMD%
    goto :run
)

echo [CRITICAL ERROR] Python executable could not be found!
echo Please make sure Python is installed.
echo.
goto :halt

:run
echo [2/3] Launching view_main_window.py with: %PYTHON_CMD%
echo.

%PYTHON_CMD% view_main_window.py

set EXIT_CODE=%ERRORLEVEL%
echo.
echo [3/3] Application process exited with code: %EXIT_CODE%

if %EXIT_CODE% neq 0 (
    echo.
    echo ==========================================================
    echo [ERROR DETECTED] The application exited abnormally.
    echo Check the error messages above or in logs\ directory.
    echo ==========================================================
)

:halt
echo.
echo ==========================================================
echo Press any key to close this console window...
echo ==========================================================
pause >nul