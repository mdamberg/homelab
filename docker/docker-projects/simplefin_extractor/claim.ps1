# One-time claim of a SimpleFIN setup token. Run this yourself in a terminal.
# The token is read from the clipboard (then wiped) and never shown or written to disk; the Access URL
# goes straight to a file only your account can read and is never printed.
param([string]$SecretsDir = (Join-Path $env:USERPROFILE '.secrets\simplefin'))

$ErrorActionPreference = 'Stop'
$target = Join-Path $SecretsDir 'access_url.txt'
if (Test-Path $target) { throw "$target already exists; refusing to overwrite it." }

New-Item -ItemType Directory -Force $SecretsDir | Out-Null
# Drop inherited permissions and grant full control to the current user only.
# No /T: files inside inherit this ACL; /T would strip them to an empty ACL.
icacls $SecretsDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not lock permissions on $SecretsDir; not continuing." }

Read-Host 'Copy the SimpleFIN setup token to your clipboard, then press Enter' | Out-Null
$token = [string](Get-Clipboard -Raw)
# Wipe the clipboard right away so the token does not linger there
cmd /c 'echo off | clip'
$token = $token.Trim()
if ($token.Length -lt 20) {
    throw "Clipboard held only $($token.Length) character(s); copy the full token and run again."
}

try {
    $claimUri = [Uri][Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($token))
} catch {
    throw 'That is not a valid setup token (not Base64).'
}
if ($claimUri.Scheme -ne 'https' -or -not $claimUri.Host.EndsWith('.simplefin.org')) {
    throw 'Decoded token does not point at an https simplefin.org address; not claiming it.'
}

try {
    $accessUrl = [string](Invoke-RestMethod -Method Post -Uri $claimUri -ContentType 'text/plain' -Body '')
} catch {
    $response = $_.Exception.Response
    if ($null -eq $response) { throw 'Claim failed: could not reach SimpleFIN.' }
    $status = $response.StatusCode.value__
    if ($status -eq 403) {
        throw 'Claim refused (403): token already claimed or invalid. If you did not claim it, disable it in SimpleFIN Bridge now.'
    }
    throw "Claim failed (HTTP $status)."
}

$accessUrl = $accessUrl.Trim()
if ($accessUrl -notmatch '^https://[^:/@\s]+:[^@\s]+@[^\s]+$') {
    throw 'Claim response was not an Access URL; nothing was saved.'
}

[IO.File]::WriteAllText($target, $accessUrl)
Remove-Variable token, accessUrl
Write-Host "Saved Access URL to $target ($((Get-Item $target).Length) bytes). Do not open or share it."
