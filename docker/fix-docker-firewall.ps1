# Run this script as Administrator to allow Docker container ports through Windows Firewall.
# Works for both LAN (192.168.1.x) and Tailscale (100.x.x.x) access.
#
# If services are reachable on LAN but not via Tailscale, also restart winnat:
#   net stop winnat && net start winnat
# Docker Desktop's WSL2 port proxy (winnat) occasionally stops forwarding on non-LAN adapters.

$ports = @(
    # Media stack
    @{Port=32400; Name="Plex"},
    @{Port=7878;  Name="Radarr"},
    @{Port=8989;  Name="Sonarr"},
    @{Port=9696;  Name="Prowlarr"},
    @{Port=8191;  Name="Flaresolverr"},
    @{Port=8080;  Name="qBittorrent"},
    @{Port=5055;  Name="Overseerr"},
    @{Port=8181;  Name="Tautulli"},
    @{Port=5299;  Name="LazyLibrarian"},
    @{Port=13378; Name="AudioBookShelf"},
    # Dashboard / management
    @{Port=7575;  Name="Homarr"},
    @{Port=3002;  Name="Dashdot"},
    @{Port=9443;  Name="Portainer"},
    # Monitoring
    @{Port=3001;  Name="Uptime Kuma"},
    @{Port=61208; Name="Glances"},
    # Automation / analytics
    @{Port=5678;  Name="n8n"},
    @{Port=8090;  Name="Lightdash"},
    # Utilities
    @{Port=5070;  Name="Flash Todo"},
    @{Port=8282;  Name="Linkding"},
    @{Port=8081;  Name="phpIPAM"},
    @{Port=8200;  Name="Duplicati"},
    # Home Assistant (VirtualBox VM, not Docker — included for consistency)
    @{Port=8123;  Name="Home Assistant"},
    # Misc / inactive
    @{Port=5000;  Name="Weather API"},
    @{Port=8082;  Name="Pi-hole HTTP"},
    @{Port=8443;  Name="Pi-hole HTTPS"}
)

Write-Host "Creating Windows Firewall rules for Docker containers..." -ForegroundColor Cyan

foreach ($item in $ports) {
    $ruleName = "Docker - $($item.Name)"

    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $item.Port `
        -Profile Any `
        -Description "Allow access to Docker container: $($item.Name)" | Out-Null

    Write-Host "  ✓ Port $($item.Port) - $($item.Name)" -ForegroundColor Green
}

Write-Host "`nFirewall rules created successfully!" -ForegroundColor Green
Write-Host "Accessible via LAN (192.168.1.7) and Tailscale (100.82.35.70)" -ForegroundColor Cyan
Write-Host ""
Write-Host "If Tailscale access still fails, restart the WSL2 port proxy:" -ForegroundColor Yellow
Write-Host "  net stop winnat" -ForegroundColor Yellow
Write-Host "  net start winnat" -ForegroundColor Yellow
