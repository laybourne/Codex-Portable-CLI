@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 936 >nul 2>&1
cd /d "%~dp0"
call "%~dp0setup-configs.cmd" >nul

rem 关键路径校验
if not exist "%~dp0singbox" (
  echo [错误] 未找到目录：%~dp0singbox
  echo 请确认解压完整，不要只解压单个脚本。
  echo.
  pause
  exit /b 1
)

title singbox 一键启动 (OpenAI Codex)

echo 是否执行IP更新？IP更新从服务端更新IP，以解决断网！
echo 默认 7 秒内不选，1~2 选项更新对应 ip 节点。
echo.

choice /C 123 /T 7 /D 3 /M "1:更新ip1  2:更新ip2  3:不更新"
if errorlevel 3 goto startfq
if errorlevel 2 goto ip2
if errorlevel 1 goto ip1

:ip2
start /wait "" "%~dp0singbox\ip_Update\ip_2.bat"
goto startfq
:ip1
start /wait "" "%~dp0singbox\ip_Update\ip_1.bat"
goto startfq

:startfq
if exist "%~dp0App\bin\codex.exe" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0App\codex_proxy.ps1" -Core 4
  exit /b 0
) else (
  echo [提示] 未检测到 App\bin\codex.exe，仅启动代理核心...
  start "" /D "%~dp0singbox" "%~dp0singbox\sing-box.exe" run -c "%~dp0singbox\config.json"
  pause
  exit /b 0
)