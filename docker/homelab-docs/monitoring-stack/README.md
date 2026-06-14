# Monitoring Stack

System monitoring and uptime tracking for the homelab.

## Services

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| Uptime Kuma | 3001 | http://10.0.0.7:3001 | Uptime monitoring and alerting |
| Glances | 61208 | http://10.0.0.7:61208 | Real-time system resource monitoring |

## Uptime Kuma

A self-hosted monitoring tool that tracks whether services are up and sends alerts when they go down.

- Monitors HTTP endpoints, TCP ports, and more
- Sends alerts via configured notification channels
- Displays a status dashboard and historical uptime graphs
- Data persisted in `./uptime-kuma-data`

### Retry configuration (required to avoid false alerts after reboots)

Uptime Kuma defaults to 0 retries — one missed heartbeat triggers an alert immediately. After a power outage, services take 60-120 seconds to come back, which floods the alert channel with false positives.

Set these values on **each monitor** in the Uptime Kuma UI (Edit Monitor):

| Setting | Recommended value |
|---------|------------------|
| Retries | 3 |
| Retry interval | 20s |
| Heartbeat interval | 60s |
| Request timeout | 20s |

This means a service must miss 3 consecutive checks (60–90 seconds of real downtime) before an alert fires.

## Glances

A real-time system stats viewer running in web mode.

- Shows CPU, RAM, disk, network usage
- Reads container stats via Docker socket (`/var/run/docker.sock`)
- Runs in privileged mode to access system metrics
- Sensors plugin is disabled (`--disable-plugin sensors`) to avoid Windows compatibility issues

## Compose Location

```
docker-projects/monitoring/docker-compose.yml
```

## Management

```powershell
cd "C:\Users\mattd\OneDrive\Matts Documents\Docker\docker-projects\monitoring"

docker-compose up -d      # Start
docker-compose down       # Stop
docker-compose logs -f    # View logs
```

Or via the infrastructure scripts:

```powershell
.\start-all-services.ps1 -Services "monitoring"
.\stop-all-services.ps1 -Services "monitoring"
```

## Related Documentation

- [Compose File Reference](compose.md)
- [Troubleshooting](troubleshooting.md)
- [Standards: Monitoring](../standards/monitoring.md)
