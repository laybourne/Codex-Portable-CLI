@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Codex and Windows Terminal Updater

set "UPDATER=%~dp0App\update.ps1"

if not exist "%UPDATER%" (
    echo [ERROR] Update script not found: %UPDATER%
    pause
    exit /b 1
)

echo ========================================================
echo       OpenAI Codex + Windows Terminal Updater
echo ========================================================
echo   - OpenAI Codex:     Official GitHub Release
echo   - Windows Terminal: Official GitHub Release
echo   - Network:          Direct GitHub connection
echo   - Safety:           Isolated download, backup and rollback
echo ========================================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%UPDATER%" %*
set "UPDATE_EXIT=%ERRORLEVEL%"

echo.
if "%UPDATE_EXIT%"=="0" (
    echo [DONE] Update check completed successfully.
) else (
    echo [ERROR] Update failed. Existing files were preserved or restored.
)
echo Press any key to exit...
pause >nul
exit /b %UPDATE_EXIT%
