@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "MODE=default"
if "%~1"=="" goto menu

if /I "%~1"=="full" (
    set "MODE=full"
    shift
) else if /I "%~1"=="skiptests" (
    set "MODE=skiptests"
    shift
) else if /I "%~1"=="help" (
    goto :usage
) else if /I "%~1"=="/?" (
    goto :usage
)

if not "%~1"=="" (
    echo [FAIL] Unsupported argument: %~1
    echo.
    echo Root-level build.bat only accepts build modes.
    echo For advanced build options, run scripts\build.ps1 directly.
    echo.
    goto :usage_error
)

goto run

:menu
cls
echo ========================================
echo  AHKeyMap Build Script
echo ========================================
echo.
echo Select a build mode:
echo   [1] Safe build    ^(run unit,integration tests, then build^)
echo   [2] Full build    ^(run all tests, then build^)
echo   [3] Quick build   ^(skip tests, build only^)
echo   [Q] Quit
echo.
choice /C 123Q /N /M "Enter your choice: "
set "MENU_CHOICE=%ERRORLEVEL%"

if "%MENU_CHOICE%"=="1" set "MODE=default"
if "%MENU_CHOICE%"=="2" set "MODE=full"
if "%MENU_CHOICE%"=="3" set "MODE=skiptests"
if "%MENU_CHOICE%"=="4" exit /b 0

:run
echo ========================================
echo  AHKeyMap Build Script
echo ========================================
echo.

set "POWERSHELL_EXE="
where pwsh >nul 2>&1 && set "POWERSHELL_EXE=pwsh"
if not defined POWERSHELL_EXE set "POWERSHELL_EXE=powershell"

set "TEST_SUITE=unit,integration"
if /I "%MODE%"=="full" set "TEST_SUITE=all"

if /I "%MODE%"=="skiptests" (
    echo [STEP] Skipping automated tests.
) else (
    echo [STEP] Running automated tests: %TEST_SUITE%
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test.ps1" -Suite %TEST_SUITE%
    set "EXITCODE=!ERRORLEVEL!"

    if not "!EXITCODE!"=="0" (
        echo.
        echo [FAIL] Tests failed with exit code !EXITCODE!
        echo.
        pause
        exit /b !EXITCODE!
    )
)

echo.
echo [STEP] Building release artifacts...
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo [FAIL] Build failed with exit code %EXITCODE%
    echo.
    pause
    exit /b %EXITCODE%
)

echo.
echo [OK] Build succeeded.
echo.
pause
exit /b 0

:usage
echo Usage:
echo   build.bat [full^|skiptests]
echo.
echo Modes:
echo   default    Run unit,integration tests, then build to dist\.
echo   full       Run all tests, then build to dist\.
echo   skiptests  Build to dist\ without running tests first.
echo.
echo Examples:
echo   build.bat
echo   build.bat full
echo   build.bat skiptests
echo.
pause
exit /b 0

:usage_error
pause
exit /b 1
