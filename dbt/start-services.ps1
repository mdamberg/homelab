# Home Metrics Infrastructure - Start Services
# Starts PostgreSQL and Metabase for analytics pipeline

Write-Host "Starting Home Metrics Infrastructure..." -ForegroundColor Cyan

# Ensure we're in the right directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

# Create network if it doesn't exist (required for Lightdash connectivity)
docker network create home-metrics 2>$null

# Start services
docker compose up -d

# Show status
Write-Host "`nService Status:" -ForegroundColor Green
docker compose ps

Write-Host "`nHome Metrics Infrastructure started." -ForegroundColor Cyan
Write-Host "  - PostgreSQL: localhost:5432" -ForegroundColor Gray
Write-Host "  - Metabase:   http://localhost:3000" -ForegroundColor Gray
