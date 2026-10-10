@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if not exist "%~dp0Quick\config.yaml" copy /Y "%~dp0Quick\config.yaml.example" "%~dp0Quick\config.yaml" >nul
if not exist "%~dp0Xray\config.json" copy /Y "%~dp0Xray\config.json.example" "%~dp0Xray\config.json" >nul
if not exist "%~dp0clash.meta\config.yaml" copy /Y "%~dp0clash.meta\config.yaml.example" "%~dp0clash.meta\config.yaml" >nul
if not exist "%~dp0hysteria\config.json" copy /Y "%~dp0hysteria\config.json.example" "%~dp0hysteria\config.json" >nul
if not exist "%~dp0hysteria2\config.json" copy /Y "%~dp0hysteria2\config.json.example" "%~dp0hysteria2\config.json" >nul
if not exist "%~dp0juicity\config.json" copy /Y "%~dp0juicity\config.json.example" "%~dp0juicity\config.json" >nul
if not exist "%~dp0mieru\config.json" copy /Y "%~dp0mieru\config.json.example" "%~dp0mieru\config.json" >nul
if not exist "%~dp0naiveproxy\config.json" copy /Y "%~dp0naiveproxy\config.json.example" "%~dp0naiveproxy\config.json" >nul
if not exist "%~dp0shadowquic\client.yaml" copy /Y "%~dp0shadowquic\client.yaml.example" "%~dp0shadowquic\client.yaml" >nul
if not exist "%~dp0singbox\config.json" copy /Y "%~dp0singbox\config.json.example" "%~dp0singbox\config.json" >nul

echo Example configurations are ready. Edit the selected proxy config with your own node credentials.
exit /b 0
