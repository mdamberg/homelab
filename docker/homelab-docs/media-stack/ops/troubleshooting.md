# Troubleshooting

## qBittorrent stalled / Overseerr requests never download

**Symptom:** qBittorrent shows all torrents as Inactive/Stalled (0 active), Overseerr requests get approved but never start downloading, Radarr/Sonarr searches return no results.

**Root cause:** Gluetun (PIA VPN) tunnel is down. qBittorrent's kill switch cuts all traffic when the VPN drops.

### Step 1 — Check Gluetun logs

```powershell
docker logs gluetun --tail 100
```

Look for:
- `Tunnel is up` → VPN connected, problem is elsewhere (go to Step 4)
- `authentication failure` → PIA credentials wrong
- `TLS handshake failed` or `connection refused` → PIA server issue, try restarting
- No recent output → container may be crash-looping (`docker compose ps`)

### Step 2 — Check if VPN is actually routing traffic

```powershell
docker exec gluetun wget -qO- ifconfig.me
```

- Returns a non-home-network IP → VPN is working
- Returns `10.0.0.x` or times out → VPN is NOT routing, kill switch is active

### Step 3 — Restart Gluetun

```powershell
cd C:\Users\mattd\repos\homelab\docker\docker-projects\media_stack
docker compose restart gluetun
docker logs gluetun -f   # watch for "Tunnel is up"
```

If it keeps failing after 2-3 restarts, the PIA OpenVPN endpoint for `US California` may be down. Try changing `SERVER_REGIONS` in docker-compose.yml to `US East` or `US New York` and re-deploying.

### Step 4 — Verify Radarr/Sonarr → qBittorrent connection

1. Open Radarr: `http://10.0.0.7:7878` → Settings → Download Clients → click the test button on qBittorrent
2. qBittorrent host should be `gluetun`, port `8080`
3. If test fails with "Unable to connect", Gluetun is still down

### Step 5 — Check Prowlarr indexers

Open Prowlarr: `http://10.0.0.7:9696` → Indexers

- Green checkmarks = healthy
- Red X or last-query errors = indexer broken; click the indexer and hit **Test**
- If all indexers fail, Prowlarr itself may have lost its indexer auth tokens (re-add them)

---

## Switching PIA from OpenVPN to WireGuard (more reliable)

PIA's OpenVPN servers have had instability issues. WireGuard is faster and more reliable.

**Prerequisites:** Get your WireGuard private key from PIA:
1. Log into [privateinternetaccess.com](https://privateinternetaccess.com)
2. Go to Downloads → Manual Configuration → WireGuard
3. Generate a key pair and copy the **Private Key**

**In `docker-compose.yml`**, replace the Gluetun `environment` block:

```yaml
environment:
  - VPN_SERVICE_PROVIDER=private internet access
  - VPN_TYPE=wireguard
  - WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY}   # add to .env
  - SERVER_REGIONS=US California
  - TZ=${TZ}
  - FIREWALL_OUTBOUND_SUBNETS=192.168.0.0/16,10.0.0.0/8,172.16.0.0/12
```

Add `WIREGUARD_PRIVATE_KEY=<your_key>` to your `.env` file, then:

```powershell
docker compose up -d gluetun
docker logs gluetun -f
```

---

## Gluetun control server (status API)

After the healthcheck update, Gluetun exposes a status API on port 8000:

```powershell
# Check VPN status
curl http://10.0.0.7:8000/v1/vpn/status

# Check public IP (should not be your home IP)
curl http://10.0.0.7:8000/v1/publicip/ip
```
