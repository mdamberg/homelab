# Daily SimpleFIN load, invoked by Task Scheduler. Output holds only counts and
# error codes; it is kept outside the repo and overwritten each run.
param(
    [int]$MaxWaitMinutes = 60,
    [int]$IntervalSeconds = 300
)

$logDir = Join-Path $env:LOCALAPPDATA 'simplefin-extractor'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'last-run.log'

function Write-Log($message) {
    Add-Content -Path $log -Encoding ascii -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
}

Set-Content -Path $log -Encoding ascii -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') run started"

# After a reboot Docker Desktop can come up minutes after this task fires. Wait
# for the engine before touching SimpleFIN, so retries never use Bridge quota.
$deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
while ($true) {
    cmd /c "docker info >nul 2>&1"
    if ($LASTEXITCODE -eq 0) { break }
    if ((Get-Date) -ge $deadline) {
        Write-Log "Docker still not reachable after $MaxWaitMinutes minutes; giving up"
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
exit $exitCode
