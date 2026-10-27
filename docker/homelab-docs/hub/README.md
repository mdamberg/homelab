# Homelab Hub

## Overview

A self-hosted dashboard at `https://hub.damattberghome.duckdns.org` (tailnet devices only). It has
tabbed pages of live widgets plus a launcher for every service. It runs alongside Homarr until it
covers everything Homarr is used for.

Code: `docker/docker-projects/hub/`. Plan and design mock-up: `docker/project-plans/docker/homelab-hub.md`
and `homelab-hub-mockup.html`.

There is no hub login. Tailscale is the perimeter, and each launcher link opens that service's own login.

## Ports

| Port | Purpose |
|------|---------|
| `8000` (container only) | FastAPI app. Not published; reached only through Caddy as `hub:8000` |

## How It Works

```
Browser ──► Caddy (hub.damattberghome.duckdns.org) ──► hub:8000
                                                       ├─ /                  static frontend
                                                       ├─ /api/config        pages.yaml + services.yaml
                                                       ├─ /api/widgets/{id}  cached widget data
                                                       └─ poller: one asyncio loop per widget
```

- The browser only reads the hub's own JSON. The hub's poller calls each upstream on that widget's
  own interval and caches the result, so open tabs add no load on the services.
- A failing upstream marks only its own widget `down`. The tile greys out, shows the error, and
  keeps its last good data. A widget with no fresh data past `stale_after` shows as `stale`.
- `static/` and `config/` are bind-mounted read-only, so edits to them show on the next browser
  refresh. Changes under `app/` (Python) need `docker compose up -d --build`.

## Configuration

| File | What it controls |
|------|------------------|
| `config/pages.yaml` | Tabs, their order, and which widgets each shows (`span` = width on a 12-column grid) |
| `config/services.yaml` | Launcher entries: name, URL, description, and the Uptime Kuma monitor name for the health dot |
| `static/themes.css` | Color schemes. Add a block pair to add a scheme; the picker finds it automatically |
| `.env` | Secrets (gitignored). Template: `.env.example` |

### Secrets

| Variable | Where to get it |
|----------|-----------------|
| `KUMA_API_KEY` | Uptime Kuma > Settings > API Keys. Used to read `/metrics` for health dots |

After editing `.env`, run `docker compose up -d` in `hub/` so the container picks it up.

## Adding a widget

1. `app/widgets/<id>/widget.py`: a `WIDGET` dict (`id`, `interval`, `timeout`, `stale_after`, in
   seconds) and `async def fetch(ctx)` returning a dict. `ctx.http` is a shared `httpx.AsyncClient`,
   `ctx.env` holds the environment. Add an empty `__init__.py` beside it.
2. `static/widgets/<id>/widget.js`: `export const meta = { title, source }` and
   `export function render(el, data, helpers)`. `helpers` has `esc`, `fmt` and `pill`.
3. Add `{ id: <id>, span: <n> }` to a page in `config/pages.yaml`.
4. `docker compose up -d --build` (new Python code).

Error messages from `fetch` are shown in the browser, so they must never contain a key or token.

## Service Interactions

**Reads from** (by container name on each stack's network):
- Uptime Kuma `uptime-kuma:3001/metrics` (monitoring_default)

Networks joined: `media_stack_default`, `monitoring_default`, `home_assist_default`, `home-metrics`.
Caddy joins `hub_default`.

**Sends to**: nothing. The hub is read-only.

## Gotchas

- Every external network must exist when the hub starts. `docker compose down` on a stack removes its
  network and the hub will not start until that stack is back. `start-all-services.ps1` starts the
  hub after the stacks and before Caddy.
- Only services with a Kuma monitor (and a matching `kuma:` name in `services.yaml`) get a health
  dot; the rest show none. A hollow ring means the monitor is configured but its status is unknown
  (for example, Kuma is unreachable). To add a dot, create the monitor in Kuma and add its exact
  name as `kuma:` on the service.
