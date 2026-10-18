# Tailscale Quick Reference

Fast reference for accessing your homelab services remotely.

---

## 🚀 Quick Start

### On Your Phone/Laptop:

1. **Open Tailscale app** → Toggle ON
2. **Look for VPN indicator** (🔑 icon or "VPN" in status bar)
3. **Open browser** → Use URLs below

That's it! You're now connected to your home network from anywhere.

---

## 📱 Service Access URLs

**Your Server Tailscale IP: `100.82.35.70`**

### Main Services

| Service | URL | Description |
|---------|-----|-------------|
| **Homarr** | http://100.82.35.70:8181 | Main dashboard - START HERE |
| **Home Assistant** | http://100.82.35.70:8123 | Home automation |
| **Plex** | http://100.82.35.70:32400/web | Media server |
| **Portainer** | https://100.82.35.70:9443 | Docker management |

### Media Management

| Service | URL | Description |
|---------|-----|-------------|
| **Overseerr** | http://100.82.35.70:5055 | Request movies/shows |
| **Sonarr** | http://100.82.35.70:8989 | TV shows |
| **Radarr** | http://100.82.35.70:7878 | Movies |
| **Prowlarr** | http://100.82.35.70:9696 | Indexer manager |
| **qBittorrent** | http://100.82.35.70:8080 | Torrents |

### Utilities

| Service | URL | Description |
|---------|-----|-------------|
| **Todo App** | http://100.82.35.70:5070 | Task list |
| **Duplicati** | http://100.82.35.70:8200 | Backups |
| **Pi-hole** | http://100.82.35.70:8082/admin | DNS ad blocking |

---

## 🔧 Common Tasks

### Access Services from Phone

```
1. WiFi OFF (use cellular to test remote access)
2. Tailscale app → Toggle ON
3. Browser → http://100.82.35.70:8181
4. Browse your homelab!
```

### Access Services from Laptop

```
1. Tailscale app → Connect
2. Browser → Use URLs above
3. Works from anywhere (coffee shop, office, hotel, etc.)
```

### Check if Tailscale is Working

```
✅ Green icon in system tray (Windows/Mac)
✅ VPN or 🔑 indicator (Phone)
✅ Device shows "online" in Tailscale app
```

---

## 🏠 When You're At Home

### Option 1: Use Local IPs (Faster)

When connected to home WiFi, you can use local IPs for faster access:

```
http://10.0.0.7:8181         # Homarr
http://10.0.0.7:8123         # Home Assistant
http://10.0.0.7:32400/web    # Plex
```

### Option 2: Use Tailscale IPs (Always Works)

Or just always use Tailscale IPs - they work at home AND away:

```
http://100.82.35.70:8181     # Works everywhere!
```

---

## 📋 Troubleshooting Checklist

### Services Won't Load?

- [ ] Is Tailscale ON? (Check app icon/status)
- [ ] Using correct IP? (`100.82.35.70`, not `10.0.0.7`)
- [ ] Using correct port? (See table above)
- [ ] Is server online? (Green dot in Tailscale app device list)
- [ ] Try a different service to isolate the issue

### Tailscale Won't Connect?

- [ ] Internet connection working?
- [ ] Try restarting Tailscale app
- [ ] Try logging out and back in
- [ ] Check Tailscale status: https://status.tailscale.com/

### Slow Performance?

- [ ] Check your cellular/WiFi signal strength
- [ ] Try accessing from different network
- [ ] Large files (like video) use your home upload bandwidth
- [ ] Consider using lower quality for streaming

---

## 💡 Pro Tips

### Bookmark These URLs

**On Phone:**
- Add bookmarks to Safari/Chrome for quick access
- Or save to home screen for app-like experience

**On Laptop:**
- Bookmark bar: Homarr, Plex, Home Assistant
- Or use Homarr as your starting point (it has links to everything)

### Use Homarr as Your Hub

- Homarr (http://100.82.35.70:8181) has links to all services
- Just bookmark Homarr, access everything from there
- Cleaner than remembering all the URLs

### Battery Considerations

**Tailscale uses minimal battery when idle, but:**
- Turn it OFF when not needed
- Or use "on-demand" activation (in Tailscale settings)
- iOS/Android will manage it efficiently

---

## 🎯 Cheat Sheet

### Access Pattern

```
Away from home:
├─ Turn ON Tailscale app
├─ Open browser
├─ Go to: http://100.82.35.70:8181 (Homarr)
└─ Click on the service you want

At home:
├─ Connect to home WiFi
├─ Tailscale: optional (can use local IPs)
└─ Go to: http://10.0.0.7:8181 (faster)
```

### Device IPs Quick Reference

| Device | Local IP | Tailscale IP | When to Use |
|--------|----------|--------------|-------------|
| **Server** | 10.0.0.7 | 100.82.35.70 | - |
| **Your Phone** | 10.0.0.20 | 100.94.112.76 | - |

**Rule of thumb:**
- At home: Use `10.0.0.7` (faster)
- Away: Use `100.82.35.70` (only option)
- Not sure: Use `100.82.35.70` (always works)

---

## 📞 Emergency Access

### If Tailscale Fails

1. **At Home:**
   - Use local IPs: http://10.0.0.7:xxxx
   - Direct WiFi access always works

2. **Away from Home:**
   - Check Tailscale status: https://status.tailscale.com/
   - Try restarting app
   - Check internet connection
   - Last resort: Wait until you get home

### If Server Goes Down

- **Services down but Windows up** → `ssh mattd@100.82.35.70` and fix from the shell — see [SSH.md](./SSH.md)
- **Whole box frozen/off** → SSH can't help; power-cycle via smart plug + BIOS "Restore on AC power loss" (see [SSH.md](./SSH.md#closing-the--gaps-hardware-no-code))

---

## 🔗 Important Links

| Resource | URL |
|----------|-----|
| Tailscale Admin Console | https://login.tailscale.com/admin |
| Tailscale Status | https://status.tailscale.com/ |
| Homarr Dashboard | http://100.82.35.70:8181 |
| Portainer (Server Mgmt) | https://100.82.35.70:9443 |

---

## 📱 Mobile App Quick Actions

### iOS Shortcuts (Optional)

Create Siri shortcuts:
- "Open Homarr" → Opens http://100.82.35.70:8181
- "Connect to home" → Toggles Tailscale ON
- "Check cameras" → Opens Home Assistant

### Android Quick Tiles (Optional)

Add Tailscale quick tile:
- Settings → Tailscale → Enable Quick Tile
- Pull down notifications → Tap to connect

---

## 🎬 Common Workflows

### Check Security Cameras

```
1. Tailscale ON
2. http://100.82.35.70:8123 (Home Assistant)
3. Navigate to cameras tab
```

### Request a Movie

```
1. Tailscale ON
2. http://100.82.35.70:5055 (Overseerr)
3. Search → Request → Wait for notification
```

### Watch Media

```
1. Tailscale ON
2. http://100.82.35.70:32400/web (Plex)
3. Browse and stream
   Note: Streaming uses home upload bandwidth
```

### Check Server Health

```
1. Tailscale ON
2. https://100.82.35.70:9443 (Portainer)
3. Containers → Check status
```

### Manage Downloads

```
1. Tailscale ON
2. http://100.82.35.70:8080 (qBittorrent)
3. View active torrents
```

---

## 🆘 Support

**Something not working?**

1. Check [SETUP.md](./SETUP.md#troubleshooting) for detailed troubleshooting
2. Check [README.md](./README.md) for architecture and explanation
3. Check service-specific docs in `homelab-docs/`
4. Restart Tailscale (fixes 90% of issues)
5. Restart Docker container (fixes remaining 9%)

**Need to add a new device?**

1. Download Tailscale app
2. Sign in with same account (mattdamberg@gmail.com)
3. Device auto-appears in network
4. Done!

---

## 🎓 Remember

- **Tailscale IP: `100.82.35.70`** (Your server - memorize this!)
- **Local IP: `10.0.0.7`** (Faster when at home)
- **Homarr: `:8181`** (Main dashboard - start here)
- **Tailscale works anywhere** (cellular, WiFi, hotel, airport, etc.)
- **No router config needed** (It just works!)

---

*Last Updated: 2026-01-05*
*Quick tips: Always try Tailscale restart first. Use Homarr as your hub. Bookmark this page!*
