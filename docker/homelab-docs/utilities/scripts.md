# Infrastructure Scripts

Scripts are located in `docker-projects/` and manage all Docker services as a group.

## start-all-services.ps1

Starts all infrastructure Docker services with error handling and status reporting.

```powershell
# Start all services
.\start-all-services.ps1

# Start specific services
.\start-all-services.ps1 -Services "pihole,homeassistant"
.\start-all-services.ps1 -Services "mediastack,monitoring"
```

**What it does:**
- Validates Docker is running before starting
- Iterates through defined services and runs `docker-compose up -d` in each directory
- Reports success/failure per service

**Registered services** (keys used with `-Services` flag):

| Key | Directory |
|-----|-----------|
| `pihole` | `pie_hole/` |
| `homeassistant` | `home_assist/` |
| `mediastack` | `media_stack/` |
| `linkding` | `linkding/` |
| `monitoring` | `monitoring/` |
| `vpn` | `vpn/` |
| `flash` | `flash_todo/` |
| `weather` | `weather_api_project/` |
| `backups` | `backups/` |

> **Note:** When adding a new service, add it to both `start-all-services.ps1` and `stop-all-services.ps1`.

---

## stop-all-services.ps1

Stops all infrastructure services gracefully.

```powershell
# Stop all services
.\stop-all-services.ps1

# Stop specific services
.\stop-all-services.ps1 -Services "mediastack"
.\stop-all-services.ps1 -Services "flash,weather"
```

---

## setup-autostart.ps1

Configures Windows Task Scheduler to automatically start all Docker services on system boot.

```powershell
# Run as Administrator
.\setup-autostart.ps1
```

**What it creates:**
- Task name: "Docker Infrastructure Auto-Start"
- Trigger: At system startup (before user login)
- Runs with SYSTEM privileges
- Automatically retries if Docker isn't ready yet

**Verify the task was created:**
```powershell
# Open Task Scheduler
taskschd.msc

# Or test it manually
Start-ScheduledTask -TaskName "Docker Infrastructure Auto-Start"
```

**Remove the task:**
```powershell
Unregister-ScheduledTask -TaskName "Docker Infrastructure Auto-Start" -Confirm:$false
```

---

## setup-env.ps1

Deploys secrets from the master `docker/.env` to each service's folder. Run this after a fresh clone, after editing the master `.env`, or any time per-service `.env` files go missing.

```powershell
cd C:\Users\mattd\repos\homelab\docker
.\setup-env.ps1
```

**Prerequisites:** `docker/.env` must exist. Copy from `docker/.env.example` and fill in values if it doesn't.

**What it does:**
- Reads `docker/.env` and parses all key=value pairs
- Writes a `.env` to each service folder containing only the variables that service needs
- Warns (but does not fail) if a variable is missing from the master file

See [Secrets Handling](../standards/secrets-handling.md) for the full workflow.

---

## Restart Policy Note

All infrastructure services use `restart: unless-stopped` in their compose files. This means:

- ✅ They restart automatically after a crash
- ✅ They restart after a system reboot (once started at least once)
- ❌ They will NOT auto-start if you manually ran `docker-compose down`

For truly automatic first-boot startup, use `setup-autostart.ps1`.

---

## Useful One-Liners

```powershell
# Check what's running
docker ps

# View logs for a specific service
docker logs -f uptime-kuma

# Restart a stuck service
cd "C:\Users\mattd\OneDrive\Matts Documents\Docker\docker-projects\<service>"
docker-compose restart

# Full rebuild of a service
docker-compose down
docker-compose up -d --build
```
