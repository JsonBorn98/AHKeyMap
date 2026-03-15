@echo off
setlocal
chcp 65001 >nul

echo ========================================
echo  AHKeyMap Build Script
echo ========================================
echo.

set "POWERSHELL_EXE="
where pwsh >nul 2>&1 && set "POWERSHELL_EXE=pwsh"
if not defined POWERSHELL_EXE set "POWERSHELL_EXE=powershell"

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1" %*
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo [FAIL] Build failed with exit code %EXITCODE%
    echo.
    pause
    exit /b %EXITCODE%
)

echo.
echo [OK] Build succeeded: dist\AHKeyMap.exe
echo.
pause
exit /b 0
