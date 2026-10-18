# Handoff: Homelab reverse proxy

**Status:** Pilot live over HTTPS as of 2026-10-17 (steps 1–4 of "Suggested order" done). See "Progress" below.

## Progress

**Decisions (Matt, 2026-10-16):** DuckDNS wildcard (option A), Caddy, pilot = Homarr / Uptime Kuma / Linkding.

**Pi-hole resolved:** the host gets `10.0.0.1` (router) as its DNS server, so LAN clients are not
using Pi-hole. Treat it as unused; names are tailnet-first via public DNS.

**DuckDNS facts:** wildcard already resolves (`test123.damattberghome.duckdns.org` returns the
same A record). It pointed at a stale IP `216.26.121.177` (actual public IP was already different)
and nothing used it. No updater exists (no container, no scheduled task, nothing in the repo).
**2026-10-17:** Matt set it to `100.82.35.70`; confirmed via 1.1.1.1 and the router.

**Built:** `docker/docker-projects/reverse_proxy/` with a Dockerfile (`caddy:2.11.7-alpine` +
`caddy-dns/duckdns@v0.5.0`), compose (80/443, upstreams via `host.docker.internal:<port>`),
and an HTTP-only Caddyfile: `homarr.`, `kuma.`, `links.` → 7575 / 3001 / 8282. Verified with
`curl --resolve` against 127.0.0.1 and 100.82.35.70. `data/` and `config/` are gitignored.
Added as `proxy` in `start-all-services.ps1`.

**HTTPS (2026-10-17):** token at `C:\Users\mattd\.secrets\duckdns\token` (36 bytes, ACL `mattd`
only; never read). Mounted as compose secret `duckdns_token` → `/run/secrets/duckdns_token`,
read by `acme_dns duckdns {file./run/secrets/duckdns_token}`. Caddyfile is one
`*.damattberghome.duckdns.org` block with `@host` matchers; unknown subdomains `abort`.
Wildcard cert issued by Let's Encrypt via DNS-01 in ~8s; Caddy renews it automatically.
Verified: all three return 200/302 over HTTPS with a valid chain, HTTP → 308 to HTTPS,
Linkding login POST passes CSRF (401 on bad creds, not 403).

**Known blip:** the first Homarr request after an idle night hung 30s → 502, then fine. Possibly a
stale upstream keepalive through Docker Desktop's port proxy (unconfirmed). Watch for recurrence.

**All services migrated (2026-10-17):** 24 routes, names listed in the `docker/CLAUDE.md`
Services Reference. Plex stays direct. Skipped as non-UI/internal: Postgres, FlareSolverr,
Gluetun control port 8000, weather_api.
- Home Assistant: added `http: use_x_forwarded_for / trusted_proxies: [172.25.0.1]`. That IP is
  the `home_assist_default` gateway, read from HA's own rejection log, not guessed. Caveat: direct
  hits on :8123 also arrive from that gateway, so a client could spoof X-Forwarded-For on the
  direct port (only affects HA's IP-based features). WebSocket handshake via proxy → 101.
- Portainer: `https://` upstream with `tls_insecure_skip_verify` (self-signed on 9443).
- Pi-hole: `/` is 403 even directly; Caddy redirects `/` → `/admin/`.
- Tautulli, LazyLibrarian, phpIPAM build `http://` absolute redirects (ignore X-Forwarded-Proto);
  Caddy's 308 to HTTPS covers it at the cost of one extra hop.
- Pre-existing, unrelated to the proxy: HA REST sensors calling `host.docker.internal:8080`
  (qBittorrent API) get 403 Forbidden.

**Upstreams moved to container names (2026-10-17):** in browser testing, n8n went black and
qBittorrent / Pi-hole loaded slowly. Caddy logs showed batches of asset requests hanging exactly
30s then 502 EOF. Root cause: Docker Desktop's host port proxy (`host.docker.internal` =
192.168.65.254) stalls under parallel connections. Test: 40 parallel requests via
host.docker.internal → 6 failed at 30s; direct container-to-container → 40/40 in 1s. Fix: Caddy
joins 9 stack networks as `external` and targets `<container>:<container port>`. After the fix,
40/40 parallel n8n assets through Caddy returned 200. HA's `trusted_proxies` is now the
`home_assist_default` subnet `172.25.0.0/16` (Caddy's IP there is dynamic).
- Consequences: Caddy must start after those stacks (start script forces `proxy` last), and it can
  reach every container on those networks (including Postgres on `home-metrics`).
- phpIPAM and call-sheet aren't in `start-all-services.ps1`. Their networks persist across Docker
  restarts, but `docker compose down` on either removes the network and Caddy won't start.

**Next:** app base URLs (n8n `N8N_HOST`/`WEBHOOK_URL`, Lightdash `SITE_URL`), docs in `docs/`,
TODO A1, optional lock-down of direct ports (Matt's go-ahead per service).
**Target dir:** `docker/docker-projects/reverse_proxy/` (create it)
**Origin:** `docker/homelab-docs/TODO.md` item A1 and the "Nginx Proxy Manager or Traefik"
section of `docker/homelab-docs/homelab-docker-review.md`.

## Goal

Replace "remember 20 ports" (`http://100.82.35.70:7878`, `:8989`, `:5678`...) with one
named HTTPS URL per service (e.g. `https://radarr.<domain>`), reachable on the LAN and
over Tailscale. Secondary: real TLS so apps can turn on secure cookies, and fixing base
URLs that currently point at `localhost` (see "App settings to update").

**Not a goal: exposing anything to the public internet.** The ISP uses CGNAT, so port
forwarding is impossible anyway, and remote access is Tailscale by design. Do not open
or suggest opening ports 80/443 on the router, and do not use Tailscale Funnel.

---

## Verified facts (2026-10-16)

| Item | Value |
|---|---|
| Host | Windows 11, Docker Desktop (WSL2). Hostname `desktop-qga3dvb` |
| Tailscale IP | `100.82.35.70`; MagicDNS on; tailnet name `desktop-qga3dvb.tail0396a0.ts.net` |
| Tailscale HTTPS certs | **Not enabled** (`CertDomains` empty) |
| Ports 80 / 443 on host | Free (no container publishes them) |
| Existing DDNS name | `damattberghome.duckdns.org` (from the old WireGuard setup, which is dead because of CGNAT) |
| Docker networks | Per-stack defaults (`media_stack_default`, `n8n_default`, `monitoring_default`, ...) plus external `home-metrics` |

Services and ports: see the table in `docker/CLAUDE.md` ("Services Reference").

### Contradiction to resolve with Matt before relying on DNS

`docker/CLAUDE.md` says Pi-hole is "actively serving DNS on port 53", while
`homelab-docs/TODO.md` notes say "Pi-hole: Skipped — not actively used". Which one is true
decides whether Pi-hole can host local DNS records for the proxy. Check that LAN clients
actually use it (router DHCP DNS setting) before building on it.

---

## Decisions for Matt (ask before building)

1. **Hostname / certificate strategy.** The CGNAT means Let's Encrypt HTTP-01 cannot work.
   Only DNS-01 or Tailscale-issued certs are possible. Options:
   - **A. Wildcard on the existing DuckDNS name.** `*.damattberghome.duckdns.org` resolves to
     the Tailscale IP `100.82.35.70`; wildcard cert via DuckDNS DNS-01. No split DNS needed.
     Works on any tailnet device. LAN devices without Tailscale would need a Pi-hole override
     to the LAN IP. A private IP in public DNS leaks nothing useful, but it is visible.
   - **B. A domain Matt owns, on Cloudflare,** with DNS-01 via a scoped API token. Same shape as
     A, cleaner names. Costs a domain (~$10/yr). Ask whether he already owns one.
   - **C. Tailscale only (`tailscale serve` / `tailscale cert`).** No proxy container at all, but
     one hostname per *machine*, so services become ports or paths on
     `desktop-qga3dvb.tail0396a0.ts.net`. Many apps break under sub-paths. Weakest fit for the goal.
   - Avoid `.local` names (TODO A1 suggested `plex.local`): `.local` is reserved for mDNS and
     resolves inconsistently. Self-signed certs mean warnings on every device.
2. **Proxy software.**
   - **Nginx Proxy Manager:** GUI, what TODO A1 names, easiest to operate; config lives in its
     SQLite DB (bind-mount it under `docker-projects/` so Duplicati backs it up).
   - **Caddy:** one text `Caddyfile` committed to git, automatic certs. DNS-01 needs a build with
     the DNS plugin (e.g. `caddy-dns/duckdns` or `caddy-dns/cloudflare`), so a small Dockerfile.
     Recommended if Matt wants config in the repo.
   - **Traefik:** label-driven, but its Docker provider wants the Docker socket. See the security
     notes before choosing it.
3. **Which services first.** Suggest a pilot of 2–3 low-risk UIs (e.g. Homarr, Uptime Kuma,
   Linkding), then the rest. Plex should probably stay direct (its own TLS/relay and client
   discovery). Pi-hole DNS (53) and WireGuard are not HTTP and are out of scope.
4. **Lock down direct ports afterwards?** Once a service is proxied, its host port can move to
   `127.0.0.1:<port>` or be removed so the proxy is the only way in. Do this per service, after
   the proxied URL is proven, and only with Matt's go-ahead (it changes how he reaches things).

---

## Security requirements (lessons from the SimpleFIN build: zero slip-ups)

- **Secrets never in git and never in chat.** A DNS API token (DuckDNS or Cloudflare) can
  re-point the whole domain. Keep it outside the repo the same way SimpleFIN does
  (`C:\Users\mattd\.secrets\<service>\`, ACL locked to `mattd`; delivered as a Docker
  secret or an env file outside the repo). Matt writes the token file himself. Claude never
  reads or prints it. Verify by file size and ACL only.
  - ACL gotcha: `icacls <dir> /inheritance:r /grant:r "mattd:(OI)(CI)F"` on the **folder only**.
    Adding `/T` strips the files to an empty ACL and locks everyone out.
- **Cloudflare token scope** (if option B): Zone → DNS → Edit on that one zone only.
- **No Docker socket in internet- or LAN-facing containers.** If Traefik is chosen, put a
  read-only socket proxy (e.g. `tecnativa/docker-socket-proxy` with only `CONTAINERS=1`) between
  them, or use Traefik's file provider instead. (n8n deliberately has no socket for the same reason.)
- The proxy's admin UI (NPM's port 81) must not be published on all interfaces. Bind it to
  `127.0.0.1` and reach it via Tailscale or the host.
- Services with no auth of their own (Glances, Duplicati, FlareSolverr, Dashdot) get **no**
  more exposure from the proxy than they have today. Forward-auth/SSO (Authentik, review §A)
  is a separate project.

---

## Technical notes to check, not assume

- **Reaching backends.** Containers on other compose projects are only reachable by name if the
  proxy joins their network. Options: attach the proxy to each stack's network (explicit, more
  YAML) or target `host.docker.internal:<port>` (simple, goes through Docker Desktop's port
  proxy). Verify per service. qBittorrent lives in Gluetun's network namespace (`vpn_default`),
  so its upstream is the Gluetun container.
- **Docker Desktop port-proxy wedge:** if many services start returning `ERR_EMPTY_RESPONSE`
  at once, Docker Desktop's host port proxy is wedged (apps fine internally); restart Docker
  Desktop. Don't misdiagnose it as a proxy config bug.
- **WebSockets:** Home Assistant, n8n, Uptime Kuma, Audiobookshelf and Portainer need them; make
  sure the proxy passes `Upgrade`/`Connection` headers (Caddy does by default; NPM has a toggle).
- **Home Assistant** rejects proxied requests unless `http: use_x_forwarded_for: true` and
  `trusted_proxies` (the proxy's Docker subnet) are set in `configuration.yaml`.
- **Portainer** serves HTTPS on 9443 itself; proxy to it with upstream TLS verification
  relaxed, or use its HTTP port if enabled.
- **After a reboot**, nothing runs until Matt logs in (Windows Hello PIN blocks auto-login).
  The proxy should be `restart: unless-stopped` and added to `start-all-services.ps1`.

## App settings to update once URLs exist

From `homelab-docker-review.md`:
- n8n: `N8N_HOST` is `localhost` (webhook URLs broken); set `N8N_HOST`, `N8N_PROTOCOL=https`,
  `WEBHOOK_URL`; then `N8N_SECURE_COOKIE=true`.
- Lightdash: `SITE_URL` points at `localhost` (share links broken).
- Overseerr / *arr apps: application URL settings if used in notifications.
- Uptime Kuma monitors that hit `localhost:<port>` keep working; don't rewrite them to proxied
  URLs (that would make the proxy a single point of failure for monitoring).

---

## Repo conventions (from `docker/CLAUDE.md`)

- Compose file: `docker/docker-projects/reverse_proxy/docker-compose.yml`, 2-space YAML,
  pinned image version (not `:latest`), relative bind mounts under the service folder so
  Duplicati backs them up.
- Add the service to `start-all-services.ps1` and the Services Reference table in `docker/CLAUDE.md`.
- Document in `docs/` (check `docs/SUMMARY.md` first; it may not exist, and `docs/` is sparse).
  Include the DNS/cert setup and token location, since neither is discoverable from code.
- Tick TODO A1 when done.
- Commit only when Matt asks; never push without asking. Imperative commit messages.
- Matt is moving from analytics to engineering. Explain the *why* of networking choices; he
  likes to understand the plumbing, not just receive it.

## Suggested order

1. Resolve the Pi-hole contradiction and the four decisions above.
2. Stand up the proxy with **one** pilot service over plain HTTP on the LAN/Tailscale IP.
3. Add DNS (wildcard record) and confirm name resolution from a tailnet device and a LAN device.
4. Add certificates (DNS-01 or Tailscale), with the token handled per the security section.
5. Migrate the remaining services one at a time, testing each (login, WebSockets, file upload).
6. Update app base URLs, then optionally restrict direct ports with Matt's go-ahead.
7. Docs, `start-all-services.ps1`, `docker/CLAUDE.md`, TODO A1.
