@echo off
chcp 65001 >nul
echo ========================================
echo  AHKeyMap Build Script
echo ========================================
echo.

:: Try to find Ahk2Exe in common locations
set "AHK2EXE="

:: Check if Ahk2Exe is in PATH
where Ahk2Exe.exe >nul 2>&1 && set "AHK2EXE=Ahk2Exe.exe" && goto :found

:: Check default AutoHotkey v2 install locations
if exist "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" (
    set "AHK2EXE=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
    goto :found
)
if exist "%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe" (
    set "AHK2EXE=%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe"
    goto :found
)

:: Check user-local install
if exist "%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" (
    set "AHK2EXE=%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
    goto :found
)

:: Check scoop install
for /d %%D in ("%UserProfile%\scoop\apps\autohotkey\*") do (
    if exist "%%D\Compiler\Ahk2Exe.exe" (
        set "AHK2EXE=%%D\Compiler\Ahk2Exe.exe"
        goto :found
    )
)

echo [ERROR] Ahk2Exe.exe not found!
echo Please install AutoHotkey v2 or add Ahk2Exe to PATH.
goto :done

:found
echo Using: %AHK2EXE%
echo.
echo Compiling AHKeyMap.ahk ...
"%AHK2EXE%" /in "%~dp0AHKeyMap.ahk" /out "%~dp0AHKeyMap.exe" /icon "%~dp0icon.ico"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [OK] Build succeeded: AHKeyMap.exe
) else (
    echo.
    echo [FAIL] Build failed with error code %ERRORLEVEL%
)

:done
echo.
pause
