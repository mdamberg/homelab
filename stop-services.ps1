# Home Metrics Infrastructure - Stop Services
# Stops PostgreSQL and Metabase

Write-Host "Stopping Home Metrics Infrastructure..." -ForegroundColor Yellow

# Ensure we're in the right directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

# Stop services
docker compose down

Write-Host "Home Metrics Infrastructure stopped." -ForegroundColor Cyan
