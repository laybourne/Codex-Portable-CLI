@echo off
setlocal EnableExtensions
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0App\stop_all_proxies.ps1"
exit /b %ERRORLEVEL%
