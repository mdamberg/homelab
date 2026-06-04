# Deploy

Steps to bring up the media stack from scratch or after a fresh clone.

---

## First-time setup

```powershell
# 1. Ensure the master .env exists with real values
#    (restore from Duplicati backup, or fill in manually)
ls C:\Users\mattd\repos\homelab\docker\.env

# 2. Deploy per-service .env files
cd C:\Users\mattd\repos\homelab\docker
.\setup-env.ps1

# 3. Start the stack
cd docker-projects\media_stack
docker compose up -d
```

---

## Normal startup

```powershell
cd C:\Users\mattd\repos\homelab\docker\docker-projects\media_stack
docker compose up -d
```

## Verify the stack is healthy

```powershell
docker compose ps
```

Expected states:
- `gluetun` — `Up (healthy)` — VPN tunnel is running
- `qbittorrent` — `Up` — starts only after Gluetun is healthy
- All other services — `Up`

Check Gluetun specifically if qBittorrent is stuck in `Created`:

```powershell
docker logs gluetun --tail 50
```

Look for `Initialization Sequence Completed` and a public IP line. If absent, see [Troubleshooting](troubleshooting.md).

---

## Stopping the stack

```powershell
docker compose down
```

Note: `docker compose down` prevents `restart: unless-stopped` from auto-restarting containers. Use `docker compose stop` if you want them to come back on next boot.

---

## Updating images

```powershell
docker compose pull
docker compose up -d
```

---

## Environment variables

All secrets are in `docker/.env` (master) and deployed to `docker-projects/media_stack/.env` by `setup-env.ps1`. See [Secrets Handling](../../standards/secrets-handling.md).

Required variables for this stack:

| Variable | Description |
|----------|-------------|
| `OPENVPN_USER` | PIA username |
| `OPENVPN_PASSWORD` | PIA password |
| `HOMARR_SECRET_KEY` | Homarr session encryption key |
| `PUID` / `PGID` | File ownership (typically `1000`) |
| `TZ` | Timezone (e.g., `America/Chicago`) |
