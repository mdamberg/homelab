# Daily SimpleFIN load, invoked by Task Scheduler. Output holds only counts and
# error codes; it is kept outside the repo, one file per run, newest $KeepLogs kept.
param(
    [int]$MaxWaitMinutes = 60,
    [int]$IntervalSeconds = 300,
    [int]$KeepLogs = 30
)

$logDir = Join-Path $env:LOCALAPPDATA 'simplefin-extractor'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "run-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log($message) {
    Add-Content -Path $log -Encoding ascii -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
}

# Marks the Uptime Kuma push monitor down with the tail of this run's log, so a
# failure alerts on Discord right away instead of after the heartbeat window.
# Success is pushed by extract.py itself. The log holds only counts and error
# codes, never secrets, so it is safe to send.
function Send-KumaDown($exitCode) {
    $line = Get-Content (Join-Path $PSScriptRoot '.env') -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^KUMA_PUSH_URL=' } | Select-Object -First 1
    if (-not $line) { return }
    # Kuma shows the push URL with its own ?status=... query; replace it with ours
    $url = ($line -replace '^KUMA_PUSH_URL=', '').Trim().Trim('"').Split('?')[0]
    $tail = (Get-Content $log | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '
    $msg = "exit $exitCode`: $tail"
    if ($msg.Length -gt 250) { $msg = $msg.Substring(0, 250) }
    try {
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 `
            -Uri "$url`?status=down&msg=$([uri]::EscapeDataString($msg))" | Out-Null
    } catch {
        # Never log the URL: it carries the push token
        Write-Log "warning: Uptime Kuma down push failed: $($_.Exception.GetType().Name)"
    }
}

Write-Log "run started"

# The timestamped names sort chronologically, so everything past the newest $KeepLogs goes
Get-ChildItem -Path $logDir -Filter 'run-*.log' |
    Sort-Object Name -Descending |
    Select-Object -Skip $KeepLogs |
    Remove-Item -Force

# After a reboot Docker Desktop can come up minutes after this task fires. Wait
# for the engine before touching SimpleFIN, so retries never use Bridge quota.
$deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
while ($true) {
    cmd /c "docker info >nul 2>&1"
    if ($LASTEXITCODE -eq 0) { break }
    if ((Get-Date) -ge $deadline) {
        Write-Log "Docker still not reachable after $MaxWaitMinutes minutes; giving up"
        Send-KumaDown 1
        exit 1
    }
    Write-Log "Docker not reachable; retrying in $IntervalSeconds seconds"
    Start-Sleep -Seconds $IntervalSeconds
}

Set-Location $PSScriptRoot
# cmd does the redirect: PowerShell 5.1 wraps every stderr line in a NativeCommandError
cmd /c "docker compose --progress quiet --profile manual run --rm -T simplefin-extractor >> `"$log`" 2>&1"
$exitCode = $LASTEXITCODE
Write-Log "run finished with exit code $exitCode"
if ($exitCode -ne 0) { Send-KumaDown $exitCode }
exit $exitCode
