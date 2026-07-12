# setup-env.ps1
# Deploys variables from the master .env to each service folder.
# Run this once after a fresh clone or any time .env files go missing.
#
# Usage:
#   1. Copy .env.example -> .env in this folder (docker/)
#   2. Fill in real values in .env
#   3. Run: .\setup-env.ps1

$masterEnvPath = Join-Path $PSScriptRoot ".env"

if (-not (Test-Path $masterEnvPath)) {
    Write-Host "ERROR: Master .env not found at $masterEnvPath" -ForegroundColor Red
    Write-Host "Copy .env.example to .env and fill in your values, then re-run." -ForegroundColor Yellow
    exit 1
}

# Parse master .env into a hashtable
$master = @{}
Get-Content $masterEnvPath | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $master[$matches[1].Trim()] = $matches[2].Trim()
    }
}

function Write-EnvFile {
    param(
        [string]$ServicePath,
        [string[]]$Keys
    )
    $lines = @()
    foreach ($key in $Keys) {
        if ($master.ContainsKey($key)) {
            $lines += "$key=$($master[$key])"
        } else {
            Write-Host "  WARNING: $key not found in master .env" -ForegroundColor Yellow
            $lines += "$key="
        }
    }
    $outPath = Join-Path $ServicePath ".env"
    $lines | Set-Content $outPath
    Write-Host "  Written: $outPath" -ForegroundColor Green
}

$projectsRoot = Join-Path $PSScriptRoot "docker-projects"

Write-Host "`nDeploying .env files..." -ForegroundColor Cyan

Write-Host "`n[media_stack]"
Write-EnvFile "$projectsRoot\media_stack" @(
    "PUID", "PGID", "TZ",
    "OPENVPN_USER", "OPENVPN_PASSWORD",
    "HOMARR_SECRET_KEY"
)

Write-Host "`n[backups]"
Write-EnvFile "$projectsRoot\backups" @(
    "TZ",
    "DUPLICATI_WEBPASS", "HEALTHCHECKS_URL", "SETTINGS_ENCRYPTION_KEY"
)

Write-Host "`n[lightdash]"
Write-EnvFile "$projectsRoot\lightdash" @(
    "TZ",
    "LIGHTDASH_PG_USER", "LIGHTDASH_PG_PASSWORD", "LIGHTDASH_SECRET",
    "MINIO_ROOT_USER", "MINIO_ROOT_PASSWORD",
    "S3_ACCESS_KEY", "S3_SECRET_KEY"
)

Write-Host "`n[linkding]"
Write-EnvFile "$projectsRoot\linkding" @(
    "TZ",
    "LD_SUPERUSER_NAME", "LD_SUPERUSER_PASSWORD"
)

Write-Host "`n[n8n]"
Write-EnvFile "$projectsRoot\n8n" @(
    "TELLER_APPLICATION_ID", "TELLER_CERTS_HOST_PATH", "TELLER_TOKENS"
)

Write-Host "`n[mcp_server]"
Write-EnvFile "$projectsRoot\mcp_server" @(
    "N8N_API_KEY", "N8N_API_URL"
)

Write-Host "`n[home_assist]"
Write-EnvFile "$projectsRoot\home_assist" @("TZ")

Write-Host "`n[weather_api_project]"
Write-EnvFile "$projectsRoot\weather_api_project" @("WEATHER_API_KEY")

Write-Host "`nDone. All .env files deployed." -ForegroundColor Cyan
Write-Host "Store your master docker/.env somewhere safe (Bitwarden, etc.)" -ForegroundColor Yellow
