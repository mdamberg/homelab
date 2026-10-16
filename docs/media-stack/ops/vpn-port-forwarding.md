# VPN Port Forwarding (gluetun + qBittorrent)

qBittorrent runs inside gluetun's network (`network_mode: service:gluetun`) and all torrent traffic exits through PIA. Without a forwarded port, qBittorrent can't accept incoming peers. Popular torrents still work, but low-seed torrents stall (e.g. 0.1% after an hour).

## How it's set up

Config lives in `docker/docker-projects/media_stack/docker-compose.yml` (gluetun service).

| Setting | Value | Why |
|---|---|---|
| `SERVER_REGIONS` | `CA Toronto,CA Ontario,CA Montreal,CA Vancouver` | PIA offers **no port forwarding on US servers** |
| `PORT_FORWARD_ONLY` | `true` | Only pick servers that support it |
| `VPN_PORT_FORWARDING` | `on` | gluetun requests a port from PIA |
| `VPN_PORT_FORWARDING_UP_COMMAND` | wget → qBit `setPreferences` | Pushes the forwarded port into qBit's listen port |
| `VPN_PORT_FORWARDING_DOWN_COMMAND` | wget → qBit `setPreferences` | Resets the port (qBit bug workaround) |
| `FIREWALL_OUTBOUND_SUBNETS` | `...,10.0.0.0/24,...` | Must stay narrow (see gotchas) |

qBittorrent requires `WebUI\LocalHostAuth=false` ("Bypass authentication for clients on localhost") so gluetun's up command can call the API. Only gluetun's hook connects from 127.0.0.1. Browsers and the *arrs arrive from 172.18.x and still need to log in.

The forwarded port changes on every reconnect. The up command handles that automatically.

## Verify

```powershell
docker logs gluetun 2>&1 | Select-String 'port forwarded is'
docker exec qbittorrent sh -c "netstat -tln | grep LISTEN"
```

The port in the gluetun log should match a LISTEN line on the tun0 IP (10.x.x.x).

## Gotchas

- **`10.0.0.0/8` in `FIREWALL_OUTBOUND_SUBNETS` breaks forwarding.** gluetun routes those subnets out eth0, and PIA's port forwarding API sits at an in-tunnel 10.x.x.1 address. Symptom: `API IP address not found: trying IP 10.x.x.1 ... 19999/ping: context deadline exceeded`. Keep the LAN entry at `10.0.0.0/24`.
- **Toronto/Ontario servers may fail the TLS handshake** (seen 2026-10-16 with the 66.56.x servers). gluetun rotates to the next server, so listing several regions keeps startup working.
- **The up command logs as `ERROR`** even on success because wget writes to stderr. `URL:... [0/0] -> "-" [1]` means it worked. Confirm with the verify step.
- Recreating gluetun requires recreating qbittorrent too: `docker compose up -d --force-recreate gluetun qbittorrent`.
