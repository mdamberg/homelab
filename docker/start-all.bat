@echo off
echo Starting all Docker services...
echo.
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\mattd\repos\homelab\docker\docker-projects\start-all-services.ps1"
echo.
echo Done!
pause
