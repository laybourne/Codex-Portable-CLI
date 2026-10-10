@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 936 >nul 2>&1
cd /d "%~dp0"

rem 关键路径校验
if not exist "%~dp0Xray" (
  echo [错误] 未找到目录：%~dp0Xray
  echo 请确认解压完整，不要只解压单个脚本。
  echo.
  pause
  exit /b 1
)

title Xray 一键启动 (OpenAI Codex)

echo 是否执行IP更新？IP更新从服务端更新IP，以解决断网！
echo 默认 7 秒内不选，1~4 选项更新对应 ip 节点。
echo.

choice /C 12345 /T 7 /D 5 /M "1:更新ip1  2:更新ip2  3:更新ip3  4:更新ip4  5:不更新"
if errorlevel 5 goto startfq
if errorlevel 4 goto ip4
if errorlevel 3 goto ip3
if errorlevel 2 goto ip2
if errorlevel 1 goto ip1

:ip4
start /wait "" "%~dp0Xray\ip_Update\ip_4.bat"
goto startfq
:ip3
start /wait "" "%~dp0Xray\ip_Update\ip_3.bat"
goto startfq
:ip2
start /wait "" "%~dp0Xray\ip_Update\ip_2.bat"
goto startfq
:ip1
start /wait "" "%~dp0Xray\ip_Update\ip_1.bat"
goto startfq

:startfq
if exist "%~dp0App\bin\codex.exe" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0App\codex_proxy.ps1" -Core 2
  exit /b 0
) else (
  echo [提示] 未检测到 App\bin\codex.exe，仅启动代理核心...
  start "" /D "%~dp0Xray" "%~dp0Xray\xray.exe" -c "%~dp0Xray\config.json"
  pause
  exit /b 0
)