# Boot Recovery

How the homelab recovers automatically after a power outage or unexpected reboot.

## How It Works

A Windows Task Scheduler task runs `start-all-services.ps1` as the SYSTEM account at every system startup, with a 90-second delay to let the Docker backend service initialize first.

```
Power restored
  → Windows boots
  → com.docker.service starts (must be Automatic — see below)
  → 90 seconds pass
  → Task Scheduler fires: start-all-services.ps1 (runs as SYSTEM)
      → waits for Docker daemon to respond
      → creates home-metrics network if missing
      → starts all services in order
  → Containers restart under their own restart: unless-stopped policies
```

The SYSTEM account runs without a user login — no PIN/password prompt blocks this flow.

## One-Time Setup (Required)

### 1. Set Docker service to Automatic start

`start-all-services.ps1` starts Docker by calling `Start-Service -Name "com.docker.service"`. For this to succeed after a cold boot, the service must be configured to start automatically:

1. Press `Win+R`, type `services.msc`, press Enter
2. Find **Docker Desktop Service**
3. Right-click → Properties → Startup type → **Automatic** (or Automatic Delayed Start)
4. Click OK

> Without this, the script will find Docker not running and the service won't exist to start — it will fall back to launching the Docker Desktop GUI, which fails under SYSTEM.

### 2. Register the Task Scheduler task

Run once as Administrator:

```powershell
cd C:\Users\mattd\repos\homelab\docker\docker-projects
.\setup-autostart.ps1
```

This creates a task named **"Docker Infrastructure Auto-Start"** that fires 90 seconds after every boot under the SYSTEM account.

### 3. Test without rebooting

```powershell
Start-ScheduledTask -TaskName "Docker Infrastructure Auto-Start"
```

Then check `docker ps` to confirm containers came up.

## Service Startup Order

`start-all-services.ps1` starts services in this order to respect dependencies:

| # | Service | Reason |
|---|---------|--------|
| 1 | pihole | DNS first |
| 2 | homemetrics | PostgreSQL — n8n and Lightdash depend on it |
| 3 | monitoring | Uptime Kuma up early for visibility |
| 4 | n8n | Needs homemetrics postgres |
| 5 | backups | Independent |
| 6 | phpipam | Independent (internal DB healthcheck handles its own ordering) |
| 7 | mediastack | Plex, *arr, qBittorrent (gluetun healthcheck gates qBittorrent) |
| 8 | linkding | Independent |
| 9 | flash | Independent |
| 10 | work | Independent |
| 11 | weather | Independent |
| 12 | lightdash | Needs homemetrics postgres |
| 13 | homeassistant | Secondary container (main HA runs in VirtualBox) |
| 14 | watchtower | Last — don't let it update mid-boot |

## Container Restart Policies

All containers use `restart: unless-stopped`. This means:
- If a container crashes, Docker restarts it automatically
- If Docker itself restarts, all containers restart
- If you manually stop a container (`docker compose down`), it stays stopped until you start it again

Key dependency chains already enforced by healthchecks:
- `qbittorrent` waits for `gluetun` to be healthy (VPN tunnel up) before starting
- `phpipam-web` and `phpipam-cron` wait for `phpipam-db` to be healthy

## Uptime Kuma — Reduce False Alerts After Reboots

After a power outage, services take 60–120 seconds to come back. With default Uptime Kuma settings (0 retries), you'll get a flood of false-down alerts.

Set on each monitor in the UI:

| Setting | Value |
|---------|-------|
| Retries | 3 |
| Retry interval | 20s |
| Heartbeat interval | 60s |
| Request timeout | 20s |

See [Monitoring Stack README](../monitoring-stack/README.md) for details.

## Troubleshooting

**Docker doesn't start after boot**
- Check `services.msc`: is `Docker Desktop Service` set to Automatic?
- Check Task Scheduler → Task Scheduler Library → "Docker Infrastructure Auto-Start" → Last Run Result
- Run `Start-ScheduledTask -TaskName "Docker Infrastructure Auto-Start"` manually and watch for errors

**Containers are running but some services are unreachable**
- Check `docker compose logs -f <service>` in the service directory
- `gluetun` not up = qBittorrent won't start (by design — it waits for the VPN)
- `home-metrics` network missing = Lightdash and n8n fail: run `docker network create home-metrics`

**"Docker not found" error in the Task Scheduler log**
- The `docker` CLI may not be on the SYSTEM account's PATH
- Workaround: add Docker's CLI path (`C:\Program Files\Docker\Docker\resources\bin`) to the System PATH in Environment Variables
