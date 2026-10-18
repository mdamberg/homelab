# SSH Access (Remote Recovery)

Shell access to `desktop-qga3dvb` from anywhere, for fixing things when a service breaks and you're away.

```
Phone / laptop ──Tailscale (WireGuard)──► desktop-qga3dvb (100.82.35.70)
   ssh client                               Windows OpenSSH Server :22
                                             └─ PowerShell session
```

**Why it rides on Tailscale:** the ISP uses CGNAT, so port 22 can't be forwarded from the internet (see [README.md](./README.md)). That's a feature here too: sshd is never exposed publicly. The firewall rule only accepts Tailscale (`100.64.0.0/10`) and LAN traffic.

**Why not Tailscale SSH?** Tailscale's built-in SSH server only runs on Linux/macOS. On Windows the server side has to be OpenSSH; Tailscale just carries the traffic.

---

## What SSH Can and Can't Recover

SSH needs Windows booted, `sshd` running, and Tailscale connected. Both run as Windows services, so they work **before anyone logs in**. They do nothing if the box is frozen or off.

| Failure | SSH fixes it? | Recovery path |
|---|---|---|
| Container crashed / unhealthy | ✅ | `docker restart <name>` |
| Compose stack needs restart | ✅ | `docker compose up -d` in the stack folder |
| Docker Desktop hung | ⚠️ Partially | `Restart-Computer -Force`. Docker Desktop is a GUI app tied to a user session, so restarting it over SSH is unreliable; a reboot + autostart is cleaner |
| Windows rebooted (updates) | ✅ | Services come back before login. Docker Desktop needs auto-login (below) |
| Windows frozen / BSOD hang | ❌ | Smart plug power cycle (below) |
| Power outage | ❌ | BIOS "Restore on AC power loss" (below) |
| Home internet down | ❌ | Nothing remote works; wait it out |

### Closing the ❌ gaps (hardware, no code)

1. **BIOS → "Restore on AC Power Loss" = Power On.** The PC boots on its own when power returns.
2. **Smart plug with its own cloud app** (Kasa / Tapo / etc.) on the PC. Off → wait 10s → On = remote hard reboot. Pair with #1. Do **not** rely on Home Assistant to toggle it: HA runs on this same box, so it's down when you need the plug.
3. **Windows auto-login** (`netplwiz`, or Sysinternals Autologon) so Docker Desktop + `setup-autostart.ps1` bring the stack up after an unattended reboot.

---

## Setup

### 1. Make a key on the client (laptop)

```bash
ssh-keygen -t ed25519 -C "matt@laptop"
cat ~/.ssh/id_ed25519.pub     # copy this line
```

On iPhone, use an SSH app (Termius, Blink) and generate an ed25519 key in-app; export its public key.

### 2. Run the setup script on the server (Admin PowerShell)

```powershell
cd C:\Users\mattd\repos\homelab\docker
.\setup-ssh.ps1 -PublicKey "ssh-ed25519 AAAA... matt@laptop"
```

Run it again with another `-PublicKey` to add each extra device. It's idempotent.

What it does:

| Step | Why |
|---|---|
| Installs OpenSSH Server capability | Ships with Windows, just not enabled |
| `sshd` → Automatic + started | Survives reboots, runs before login |
| Default shell → PowerShell | Otherwise you land in `cmd.exe` |
| Writes key to `C:\ProgramData\ssh\administrators_authorized_keys` | Admin accounts ignore `~\.ssh\authorized_keys` on Windows. `sshd` also silently ignores the file unless only Administrators + SYSTEM have access, so the script locks the ACL |
| `PasswordAuthentication no` (only if a key was given) | Keys only. A leaked Windows/Microsoft-account password can't be used over SSH |
| Validates config with `sshd -t` before restart | A bad config would take sshd down — exactly what you can't fix remotely |
| Firewall: port 22 from `100.64.0.0/10` + LocalSubnet only | Defense in depth |
| `tailscale set --unattended=true` | Without it, Tailscale on Windows disconnects when you log out |

### 3. Disable Tailscale key expiry for the server

[Admin console](https://login.tailscale.com/admin/machines) → `desktop-qga3dvb` → **⋯ → Disable key expiry**.
Node keys expire every 180 days by default; when it does, the server silently drops off your tailnet and needs a local re-login — exactly when you're away.

### 4. Test (from cellular / a different network, Tailscale on)

```bash
ssh mattd@100.82.35.70
# or with MagicDNS:
ssh mattd@desktop-qga3dvb
```

Optional `~/.ssh/config` on the laptop:

```
Host homelab
    HostName desktop-qga3dvb
    User mattd
    IdentityFile ~/.ssh/id_ed25519
```

Then just `ssh homelab`.

---

## Remote Fix Cheat Sheet

```powershell
# What's running / what's broken
docker ps -a --format "table {{.Names}}\t{{.Status}}"
docker logs --tail 100 <container>

# Restart one service / a whole stack
docker restart <container>
cd C:\Users\mattd\repos\homelab\docker\docker-projects\media_stack; docker compose up -d

# Bring everything up
C:\Users\mattd\repos\homelab\docker\docker-projects\start-all-services.ps1

# Host health
Get-Service sshd, Tailscale, com.docker.service
Get-PSDrive C                                  # disk space
Get-Process | Sort-Object CPU -Desc | Select -First 10

# Nuclear option (you'll lose the session; reconnect in ~2–3 min)
Restart-Computer -Force
```

---

## Troubleshooting

| Symptom | Check |
|---|---|
| `Connection timed out` | Is the server online in `tailscale status` / admin console? Is your client's Tailscale on? |
| `Connection refused` | `Get-Service sshd` on the server; firewall rule `Get-NetFirewallRule -Name OpenSSH-Server-In-TCP` |
| `Permission denied (publickey)` | Key not in `administrators_authorized_keys`, or ACL wrong — rerun the script. Server log: `Get-WinEvent -LogName OpenSSH/Operational -MaxEvents 20` |
| Server offline after ~6 months | Key expiry wasn't disabled (Setup step 3) |
