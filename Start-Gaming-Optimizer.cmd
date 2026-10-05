@echo off
setlocal
title Gaming Optimizer
color 0B
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gaming-Optimizer.ps1" -Mode Menu
if errorlevel 1 pause
endlocal
