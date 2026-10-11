@echo off
echo Starting all Docker services...
echo.
powershell.exe -ExecutionPolicy Bypass -File "%~dp0start-all-services.ps1"
echo.
pause
