@echo off
cd /d "C:\Users\mattd\repos\homelab\docker\docker-projects\flash_todo"
echo Rebuilding flash_todo...
docker compose down
docker compose up -d --build
echo.
echo Done! flash_todo rebuilt and running.
pause
