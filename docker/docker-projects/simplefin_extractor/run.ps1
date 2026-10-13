# Daily SimpleFIN load, invoked by Task Scheduler. Output holds only counts and
# error codes; it is kept outside the repo and overwritten each run.
$logDir = Join-Path $env:LOCALAPPDATA 'simplefin-extractor'
New-Item -ItemType Directory -Force $logDir | Out-Null

Set-Location $PSScriptRoot
# cmd does the redirect: PowerShell 5.1 wraps every stderr line in a NativeCommandError
$log = Join-Path $logDir 'last-run.log'
cmd /c "docker compose --progress quiet --profile manual run --rm -T simplefin-extractor > `"$log`" 2>&1"
exit $LASTEXITCODE
