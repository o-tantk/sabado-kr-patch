@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0installer\setup.ps1" -Action Remove
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
