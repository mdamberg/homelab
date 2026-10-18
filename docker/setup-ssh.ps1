#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up OpenSSH Server on the homelab desktop for remote recovery over Tailscale

.DESCRIPTION
    Installs and enables the Windows OpenSSH Server, makes PowerShell the default
    SSH shell, installs your public key, disables password logins, and restricts
    port 22 to Tailscale (100.64.0.0/10) and the local LAN. Also sets Tailscale to
    run unattended so the box stays reachable when nobody is logged in.

    Port forwarding is not an option here (ISP CGNAT), so Tailscale is the only
    way in. See homelab-docs/remote-access/SSH.md.

.PARAMETER PublicKey
    Contents of your client's public key (e.g. the text of ~/.ssh/id_ed25519.pub).
    Password authentication is only disabled when a key is supplied.

.EXAMPLE
    .\setup-ssh.ps1 -PublicKey "ssh-ed25519 AAAAC3Nza... matt@laptop"
    Run as Administrator
#>

param(
    [string]$PublicKey
)

# Require Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then run this script again." -ForegroundColor Yellow
    exit 1
}

$SshDir = "C:\ProgramData\ssh"
$SshdConfig = Join-Path $SshDir "sshd_config"
$AdminKeys = Join-Path $SshDir "administrators_authorized_keys"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  OpenSSH Server Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. Install OpenSSH Server (Windows optional capability)
$cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') {
    Write-Host "Installing OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
} else {
    Write-Host "OpenSSH Server already installed" -ForegroundColor Green
}

# 2. Start sshd and set it to start at boot (runs before login, like Tailscale)
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Write-Host "sshd service: Automatic + running" -ForegroundColor Green

# 3. Default shell = PowerShell (cmd.exe otherwise)
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" }
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $pwsh -PropertyType String -Force | Out-Null
Write-Host "Default shell: $pwsh" -ForegroundColor Green

# 4. Install public key
# Admin accounts read administrators_authorized_keys, NOT ~/.ssh/authorized_keys.
# sshd ignores the file unless only Administrators + SYSTEM can access it.
if ($PublicKey) {
    $existing = if (Test-Path $AdminKeys) { Get-Content $AdminKeys } else { @() }
    if ($existing -notcontains $PublicKey.Trim()) {
        Add-Content -Path $AdminKeys -Value $PublicKey.Trim()
    }
    icacls.exe $AdminKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
    Write-Host "Public key installed to $AdminKeys" -ForegroundColor Green
} else {
    Write-Host "No -PublicKey given; leaving password auth ON" -ForegroundColor Yellow
}

# 5. Harden sshd_config (keys only, once a key exists)
$config = Get-Content $SshdConfig -Raw
$config = $config -replace '(?m)^#?\s*PubkeyAuthentication\s+\w+', 'PubkeyAuthentication yes'
if ($PublicKey) {
    $config = $config -replace '(?m)^#?\s*PasswordAuthentication\s+\w+', 'PasswordAuthentication no'
}
Copy-Item $SshdConfig "$SshdConfig.bak" -Force
Set-Content -Path $SshdConfig -Value $config -NoNewline

# Validate before restarting so a typo can't take sshd down
& "C:\Windows\System32\OpenSSH\sshd.exe" -t
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: sshd_config invalid, restoring backup" -ForegroundColor Red
    Copy-Item "$SshdConfig.bak" $SshdConfig -Force
    exit 1
}
Restart-Service sshd
Write-Host "sshd_config hardened + sshd restarted" -ForegroundColor Green

# 6. Firewall: only Tailscale + LAN may reach port 22
$rule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}
Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -RemoteAddress @("100.64.0.0/10", "LocalSubnet")
Write-Host "Firewall: port 22 limited to Tailscale (100.64.0.0/10) + LocalSubnet" -ForegroundColor Green

# 7. Tailscale unattended: stay connected while logged out / after reboot
$tailscale = "C:\Program Files\Tailscale\tailscale.exe"
if (Test-Path $tailscale) {
    & $tailscale set --unattended=true
    Write-Host "Tailscale: unattended mode on" -ForegroundColor Green
} else {
    Write-Host "Tailscale CLI not found; enable 'Run unattended' from the tray menu" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Done. Remaining manual steps:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  1. Tailscale admin console -> desktop-qga3dvb -> 'Disable key expiry'"
Write-Host "  2. Test from another device on Tailscale:  ssh $env:USERNAME@100.82.35.70"
Write-Host ""
