# Remote Access Troubleshooting

**Symptom:** Homelab services don't load when you're away from home, even though the
Tailscale app says **Connected**.

Work this runbook **top to bottom**. Each layer only matters if the one above it is
healthy, so don't skip ahead — a green Tailscale icon does **not** mean the whole path
works. "Connected" on your phone only proves *your phone* joined the tailnet; it says
nothing about the server or the services behind it.

> Reference values for this homelab:
> - **Server node:** `desktop-qga3dvb` · Tailscale IP `100.82.35.70` · MagicDNS
>   `desktop-qga3dvb.tail0396a0.ts.net` · LAN `10.0.0.7`
> - **Tailnet:** `tail0396a0.ts.net` · Tailscale CGNAT range `100.64.0.0/10`
> - Full service/port list: [`QUICK-REFERENCE.md`](./QUICK-REFERENCE.md)

---

## The mental model

The request has to survive **four** independent layers. It breaks at exactly one of them:

```
  Phone ──► [1] Tailscale ──► [2] Windows ──► [3] Docker ──► [4] Container
            transport          firewall        engine        port binding
         (both nodes online)  (inbound allow)  (running)    (0.0.0.0, not 127.0.0.1)
```

| Layer | Runs as | Survives a reboot on its own? | Failure looks like |
|-------|---------|-------------------------------|--------------------|
| 1 Tailscale | Windows **service** | ✅ Yes | Server node grey / "Expired" in app |
| 2 Firewall | Windows Defender | (config) | All ports time out, node is green |
| 3 Docker | Docker **Desktop** (user session) | ❌ **No** — needs login | `docker ps` errors, node green |
| 4 Binding | per-container `ports:` | (config) | One service dead, others fine |

The trap: layers 1 is a *service* (auto-recovers), but layer 3 is a *desktop app* that
only starts when your user account logs in. So a forced **Windows Update reboot** brings
Tailscale back but leaves Docker down — the node shows green while every service is dark.

---

## Layer 1 — Tailscale transport

**Check (phone):** Tailscale app → tap the server → confirm:

- [ ] Status is 🟢 **Connected** (not grey / "Offline" / "Expired")
- [ ] IPv4 still reads `100.82.35.70`
- [ ] **Key expiry** is a future date (not "expired")

**If the node is grey or expired:**
1. On the server, re-authenticate: tray icon → **Log in**.
2. Stop this recurring: [admin console](https://login.tailscale.com/admin/machines) →
   server → **Disable key expiry**. Tailscale keys expire every **180 days** by default;
   disabling expiry on a always-on server is the fix.

**If green:** transport is fine — the break is downstream. Continue.

> Quick transport proof: if **Taildrop** ("Select a file to send to this device") works,
> the phone↔server path is healthy and the problem is layers 2–4, not Tailscale.

---

## Layer 2 — Windows firewall

Windows applies firewall rules **per network profile** (Domain / Private / Public). At
home you arrive over the **LAN** (Private → allowed); away you arrive over the
**Tailscale adapter**. If Windows filed that adapter under **Public**, inbound to your
service ports is blocked *only* over Tailscale — the exact "works at home, dead away"
signature.

> ⚠️ "I turned the firewall off" isn't durable: Windows **re-enables Defender Firewall
> after major updates**, and Docker Desktop re-adds its own rules on launch.

**Check (server, PowerShell as Admin):**
```powershell
Get-NetFirewallProfile | Select-Object Name, Enabled     # is it actually off?
Get-NetConnectionProfile                                 # Tailscale adapter -> NetworkCategory?
```

**Fix — allow inbound from the tailnet only** (safer than disabling the firewall):
```powershell
New-NetFirewallRule -DisplayName "Allow Tailscale inbound" `
  -Direction Inbound -Action Allow `
  -RemoteAddress 100.64.0.0/10
```
This opens ports **only** to devices on your Tailscale network, never the public internet.

---

## Layer 3 — Docker engine  *(most common cause)*

Tailscale is a Windows **service** (auto-starts). Docker Desktop is a **desktop app** that
by default starts only when your **user logs in**. A Windows Update reboot therefore leaves
the PC on, Tailscale green, and **Docker down until someone logs in** — even with sleep
disabled.

**Check (server):** whale icon in the tray, or:
```powershell
docker ps                          # errors or empty list => engine is down
```

**Fix:**
1. Start Docker Desktop. Containers with `restart: unless-stopped` come back on their own.
2. Make it survive the next update reboot:
   - Docker Desktop → **Settings → General → Start Docker Desktop when you log in** ✅
   - Enable **Windows auto-login** so the user session (and Docker) restore unattended
     after a forced reboot.

---

## Layer 4 — Container port binding

A container reachable at home but never over Tailscale may be bound to **localhost only**.
Docker publishes to `0.0.0.0` (all interfaces, including the Tailscale IP) *unless* the
compose file pins it to `127.0.0.1`.

**Check (server):**
```powershell
netstat -ano | findstr ":8123 :32400 :7575"
```
- `0.0.0.0:PORT` or `[::]:PORT` → good, reachable over Tailscale.
- `127.0.0.1:PORT` → localhost-only, **Tailscale can never reach it**.

**Fix:** in that service's `docker-compose.yml`, change the mapping from
`127.0.0.1:7575:7575` to `7575:7575`, then recreate the container:
```powershell
cd C:\Users\mattd\repos\homelab\docker\docker-projects\<service>
docker compose up -d --force-recreate
```
> A committed compose edit does nothing until the container is **recreated** — see the
> root [`docker/CLAUDE.md`](../../CLAUDE.md) note on this.

---

## Fast triage (no desktop access)

From the phone, on cellular, try **two different ports** by IP:

```
http://100.82.35.70:32400/web     (Plex)
http://100.82.35.70:7575          (Homarr)
```

| Observation | Most likely layer |
|-------------|-------------------|
| Server node grey / expired in app | **1** — Tailscale |
| Node green, **all** ports time out, Taildrop works | **2 or 3** — firewall or Docker |
| Works on home WiFi, dead on cellular | **2** — firewall profile (Public) |
| Dead on home WiFi **too** | **3** — Docker engine down |
| One service dead, others load | **4** — that container's binding |

**The single fastest tiebreak:** do the services load on **home WiFi**?
Yes → containers are up; it's transport/firewall (1–2). No → Docker is down (3).

---

## Addressing tips

- Prefer the **MagicDNS name** over the bare IP so a future IP change doesn't break
  bookmarks: `http://desktop-qga3dvb.tail0396a0.ts.net:7575`
- `10.0.0.x` (LAN) addresses **do not** route over Tailscale — no subnet route is
  advertised. Away from home, only the server's own `100.82.35.70` / MagicDNS name works.
- To make `10.0.0.x` reachable remotely: `tailscale up --advertise-routes=10.0.0.0/24`
  on the server, then approve the route in the admin console.

---

*Related: [`README.md`](./README.md) (architecture) · [`SETUP.md`](./SETUP.md) (install) ·
[`QUICK-REFERENCE.md`](./QUICK-REFERENCE.md) (daily use)*
