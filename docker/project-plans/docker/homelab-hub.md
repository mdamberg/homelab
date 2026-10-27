# Project: Homelab Hub (central dashboard)

**Created:** 2026-10-26
**Type:** docker
**Intent:** new
**Status:** Phase 1 built 2026-10-26 (all candidate widgets are v1)

Design reference: [`homelab-hub-mockup.html`](homelab-hub-mockup.html) is the approved interactive mock-up (sample data only).
Open it in a browser. Its CSS and layout seed the real frontend.

## Discovery Summary

The reverse proxy gives every service a named HTTPS URL, but there is still no single page that
shows what the homelab is doing. Homarr exists, but Matt wants something more personal: live
metrics and charts from the services, plus data that Homarr cannot show because it lives in
Postgres/dbt (finances, power, dbt run health).

The hub is a self-hosted container with a small Python (FastAPI) backend and a static frontend.
It is **not** a Claude artifact. An artifact is hosted on claude.ai, cannot reach tailnet-only
services, would expose API keys in page source, and would need CORS on every service. The artifact
was used only to design the layout and theme (the mock-up above).

Decisions made with Matt:
- Runs alongside Homarr until it is proven; Homarr stays.
- FastAPI, Python and SQL (no Node).
- No login on the hub (tailnet is the perimeter). Links open each service's own login page.
- Multiple pages via a top tab bar. Pages and widgets are config-driven, no widget cap.
- Selectable color schemes; status and chart-series colors stay fixed.
- All candidate widgets below are in v1.

## Codebase Review

### Files Reviewed
- `docker/CLAUDE.md` - repo conventions, Services Reference table, canonical paths (never OneDrive)
- `docker/.claude/skills/docker-service/SKILL.md` - compose conventions, backups, start/stop scripts
- `docker/project-plans/docker/reverse-proxy-handoff.md` - Caddy design and the Docker Desktop port-proxy finding
- `docker/docker-projects/reverse_proxy/Caddyfile` + `docker-compose.yml` - route pattern, shared-network pattern
- `docker/docker-projects/media_stack/docker-compose.yml` - container names (plex, radarr, sonarr, tautulli, audiobookshelf, gluetun/qbittorrent)
- `docker/docker-projects/monitoring/docker-compose.yml` - uptime-kuma:3001, glances:61208
- `dbt/docker-compose.yml`, `dbt/cron/dbt-schedule`, `dbt/dbt-runner/run-dbt.sh` - how dbt actually runs
- `dbt/home_metrics_dbt/models/**` - finance models and what already exists

### Patterns Referenced
- Caddy joins each stack's network as `external` and targets `<container>:<container port>`. **Do not** use `host.docker.internal` (stalls under parallel requests in Docker Desktop).
- Bind mounts under `docker-projects/` are backed up by Duplicati automatically. Named volumes are not.
- Secrets in a gitignored `.env`; `TZ=America/Chicago`; `restart: unless-stopped`; explicit `container_name`.
- Every new service key goes in both `start-all-services.ps1` and `stop-all-services.ps1`.

## Analysis Findings

Things the repo review changed from the mock-up's assumptions:

| # | Finding | Impact |
|---|---------|--------|
| 1 | dbt is **not** scheduled by n8n. `home-metrics-dbt-runner` runs supercronic with `dbt/cron/dbt-schedule`: `dbt build` every 2 h from 06:00 to 22:00 (`regular`) and a nightly `refresh` at 00:00 (full-refresh staging, snapshot, test). | "Next scheduled runs" is computed by parsing that cron file (mount it read-only), not from n8n. The mock-up has been updated to match. |
| 2 | dbt run history is not persisted anywhere queryable. `run-dbt.sh` pings Healthchecks.io and discards the log; `target/run_results.json` is overwritten by each command. | The dbt tab needs a small change to `run-dbt.sh` to record one row per run (see Prerequisite B). |
| 3 | Finance data already has `account_owner`, `transaction_type`, `custom_category`, `is_recurring` and `billing_cycle` in `fct_simplefin_transactions` (from `map_financial_accounts`). | Owner/type/category filters and recurring bills need no new source data. |
| 4 | There is no balances fact table. Only `stg_simplefin_balances`. | Net-balance chart needs a small balances model (Prerequisite A). |
| 5 | Plex, Radarr, Sonarr, Tautulli, Audiobookshelf, gluetun are all on `media_stack_default` with stable container names. | Hub reaches them by name once it joins that network. |
| 6 | HA REST sensors calling qBittorrent's API through `host.docker.internal:8080` already get **403** (noted in the reverse-proxy handoff). | Expect the same from the hub's qBittorrent widget. Investigate qBit's host-header/CSRF/auth settings before building that widget. Use `gluetun:8080` on the container network. |
| 7 | Plex deep links need the server `machineIdentifier` and each item's `ratingKey`, both available from the Plex API. | Library browser can link every title to its Plex page. Audiobooks link to Audiobookshelf `/item/<id>`. |

## Scope & Goals

**Goals:**
- [ ] One hub URL (`hub.damattberghome.duckdns.org`) with tabbed pages and a service launcher
- [ ] Live widgets that refresh in place (no page reload) on per-widget timers
- [ ] SQL-backed widgets read from the `home-metrics` Postgres (finance, power, dbt)
- [ ] Config-driven: add a widget or page with two small files and one config line
- [ ] Color schemes switchable and editable in one CSS file
- [ ] Homarr untouched and running in parallel

**Success Criteria:**
- [ ] Hub loads over the Caddy URL on a tailnet device, desktop and phone
- [ ] A qBittorrent speed change appears on the Overview chart within ~4 s without a refresh
- [ ] Editing `themes.css` or `pages.yaml` shows on the next browser refresh without a rebuild
- [ ] No API key or DB password appears in any HTTP response or in the repo
- [ ] A dead upstream (for example Sonarr down) greys out its own widget and nothing else
- [ ] Hub works with every widget upstream down (links page still usable)

**Out of Scope:**
- Authentication on the hub itself (tailnet is the perimeter; revisit if other tailnet users are added)
- Public internet exposure (CGNAT; do not open 80/443, do not use Funnel)
- Replacing Homarr (decision deferred until the hub covers what Matt uses)
- Write actions from the hub (no restarting containers, no approving requests). Read-only in v1.
- Drag-and-drop layout editing (layout is edited in `pages.yaml`)

## Technical Approach

### Overview

```
Browser (tailnet) ──► Caddy: hub.damattberghome.duckdns.org
                         │
                         ▼
                  hub container  (FastAPI + static SPA)
                  ├─ GET /                      static frontend (bind-mounted ./static)
                  ├─ GET /api/config            pages.yaml + services.yaml as JSON
                  ├─ GET /api/widgets/{id}      cached JSON for one widget
                  ├─ GET /api/art/plex/{key}    poster proxy (token stays server-side)
                  └─ poller (asyncio)  each widget has its own interval + timeout
                        ├─ Plex / Tautulli / Radarr / Sonarr / Audiobookshelf   (media_stack_default)
                        ├─ qBittorrent via gluetun                              (media_stack_default)
                        ├─ Uptime Kuma, Glances                                 (monitoring_default)
                        ├─ Home Assistant REST                                  (home_assist_default)
                        ├─ Postgres, read-only role                             (home-metrics)
                        └─ dbt run log + cron file (read-only mounts)
```

The browser never talks to an upstream. It only reads the hub's own JSON. The poller refreshes a
cache; the frontend polls `/api/widgets/{id}` at that widget's declared rate. 50 widgets cost the
upstreams the same as 5 because the cache is shared by all viewers.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where it runs | Own container, `docker/docker-projects/hub/` | Artifact cannot reach tailnet services or hide secrets |
| Backend | FastAPI + httpx (async) + psycopg | Matches Matt's Python/SQL comfort; async polling suits many slow upstreams |
| Frontend | Static HTML/CSS/vanilla JS + inline SVG charts, no build step | Mock-up is already this; bind-mounted so edits show on refresh |
| Live updates | Frontend polling per widget; SSE only if a widget feels laggy | Simplest thing that meets the 2 s qBit goal |
| Widget model | One folder per widget: `widget.py` (fetch -> JSON) and `widget.js` (render) | Adds a widget without touching core code |
| Layout | `pages.yaml` lists widgets per page with a grid span | Edits are one-line commits |
| Links | `services.yaml` (name, group, URL, description, kuma monitor name) | One source of truth for the launcher and health dots |
| Theming | `themes.css`: one block of ~6 variables per scheme | Status and series colors are not in those blocks, so a bad scheme cannot break readability |
| SQL access | Dedicated read-only Postgres role `hub_ro`, `SELECT` on the marts/fct schemas only | Hub can never write or read raw/secrets |
| Secrets | `.env` beside the compose file (gitignored) | Repo convention |
| Network | Hub joins `media_stack_default`, `monitoring_default`, `home_assist_default`, `home-metrics` as `external`; Caddy joins the hub's network | Same pattern as Caddy; avoids Docker Desktop's host port proxy |
| Failure behavior | Each widget has `timeout` and `stale_after`; errors return `{status: "down"}` with last good data | One bad upstream must not blank the page |
| SQL style | CTEs only, no subqueries (user and repo rule) | `docker/CLAUDE.md` code style |

## Proposed Changes

### Files to Create

```
docker/docker-projects/hub/
  docker-compose.yml
  Dockerfile
  .env                       # gitignored: API keys, DB password
  .env.example               # committed: variable names only
  requirements.txt           # fastapi, uvicorn, httpx, psycopg[binary], pyyaml, croniter
  app/
    main.py                  # FastAPI app, routes, startup
    poller.py                # per-widget schedule, cache, timeouts, stale handling
    config.py                # loads pages.yaml / services.yaml, validates
    db.py                    # psycopg pool, read-only helper
    widgets/
      __init__.py            # registry: discovers widgets/<id>/widget.py
      <widget_id>/widget.py  # one folder per widget in the table below
  static/                    # bind-mounted, no rebuild for edits
    index.html
    app.js                   # router, polling loop, tooltip, chart helpers (from the mock-up)
    themes.css               # color schemes
    base.css                 # layout and components (from the mock-up)
    widgets/<widget_id>/widget.js
  config/                    # bind-mounted, no rebuild for edits
    pages.yaml
    services.yaml
  data/                      # .gitkeep; live cache snapshot if needed (gitignored contents)
docker/homelab-docs/hub/README.md   # service doc (ports, config, how to add a widget)
```

### Files to Modify

- `docker/docker-projects/reverse_proxy/Caddyfile` - add `@hub host hub.damattberghome.duckdns.org` -> `reverse_proxy hub:8000`
- `docker/docker-projects/reverse_proxy/docker-compose.yml` - join the hub network (`hub_default`); **Caddy still starts last**
- `docker/docker-projects/start-all-services.ps1` and `stop-all-services.ps1` - add `hub` to `$InfraServices` and the `Valid values` header comment; `proxy` stays last
- `docker/CLAUDE.md` - add Hub to the Services Reference table and the folder tree
- `dbt/dbt-runner/run-dbt.sh` - record one JSON line per run (Prerequisite B)
- `dbt/docker-compose.yml` - nothing to change for the cron file; the hub mounts `dbt/cron/dbt-schedule` read-only
- `dbt/home_metrics_dbt/models/...` - balances model and optional recurring-bills model (Prerequisite A)

### Compose sketch

```yaml
# ============================================
# Homelab Hub - central dashboard (FastAPI + static frontend)
# Joins the stack networks so it reaches services by container name.
# ============================================
services:
  hub:
    build: .
    image: homelab-hub:1
    container_name: hub
    restart: unless-stopped
    environment:
      - TZ=America/Chicago
    env_file: .env
    volumes:
      - ./static:/srv/static:ro
      - ./config:/srv/config:ro
      - ./data:/srv/data
      - ../../../dbt/cron/dbt-schedule:/srv/dbt/dbt-schedule:ro
      - ../../../dbt/home_metrics_dbt/logs:/srv/dbt/logs:ro   # run history written by run-dbt.sh
    networks:
      - default
      - media_stack
      - monitoring
      - home_assist
      - home_metrics
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request;urllib.request.urlopen('http://localhost:8000/healthz')"]
      interval: 30s
      timeout: 5s
      retries: 3
    # No published port: reached only through Caddy at hub:8000.

networks:
  media_stack: { external: true, name: media_stack_default }
  monitoring:  { external: true, name: monitoring_default }
  home_assist: { external: true, name: home_assist_default }
  home_metrics: { external: true, name: home-metrics }
```

Caveat inherited from the proxy work: the hub can reach every container on those networks, and the
`docker compose down` caveat applies (a removed network stops the hub starting). The hub must start
**after** the stacks, **before** Caddy.

### Config formats

`config/services.yaml`

```yaml
groups:
  - name: Media
    items:
      - { name: Plex,    url: "http://100.82.35.70:32400/web", desc: "Stays on its direct port", kuma: "Plex" }
      - { name: Radarr,  url: "https://radarr.damattberghome.duckdns.org", desc: "Movies", kuma: "Radarr" }
```

`config/pages.yaml` (grid is 12 columns; `span` is a width)

```yaml
pages:
  - id: overview
    title: Overview
    subtitle: Everything that needs a glance, on one screen
    widgets:
      - { id: service_health, span: 3 }
      - { id: network_throughput, span: 8 }
  - id: media
    title: Media
    widgets: [now_playing, download_queue, library_stats, media_storage, library_browser]
```

### Widget contract

`widgets/<id>/widget.py`

```python
WIDGET = {
    "id": "download_queue",
    "interval": 2,          # seconds between upstream polls
    "timeout": 3,           # seconds before this poll is abandoned
    "stale_after": 30,      # seconds before cached data is marked stale
}

async def fetch(ctx) -> dict:
    # ctx.http: httpx.AsyncClient, ctx.env: secrets, ctx.db: read-only query helper
    ...
    return {"items": [...], "summary": {...}}
```

`widgets/<id>/widget.js` exports `render(el, data, helpers)`. `helpers` are the mock-up's
`lineChart`, `barChart`, `stackedBars`, `stackBar`, `pill`, `tooltip`. Charts follow the mock-up
rules: one axis, series colors fixed (`--s1..--s3`), status colors reserved for state with an icon
and a label, 2 px gaps between stacked segments.

SQL widgets use CTEs only. Example shape for the finance month tiles:

```sql
with scoped as (
    select
        amount,
        transaction_type,
        custom_category
    from fct_simplefin_transactions
    where transaction_date >= date_trunc('month', current_date)
      and (%(owner)s is null or account_owner = %(owner)s)
      and (%(account)s is null or account_name = %(account)s)
),
totals as (
    select
        sum(case when amount < 0 then -amount else 0 end) as spend,
        sum(case when amount > 0 then amount else 0 end)  as income
    from scoped
)
select spend, income, income - spend as net
from totals
```

(Verify sign convention and `transaction_type` values in `fct_simplefin_transactions` before use.)

### Pages and widgets

The mock-up shows six pages. Every widget below is in v1 (picked 2026-10-26).
"Source" is the planned upstream. "Poll" is the proposed interval.

| Page | Candidate widget | Source | Poll | Status |
|------|------------------|--------|------|--------|
| Overview | Service health summary | Uptime Kuma | 30 s | v1 |
| Overview | Plex streams (count) | Tautulli `get_activity` | 10 s | v1 |
| Overview | Download rate tile and throughput chart | qBittorrent via gluetun | 2 s | v1 |
| Overview | Power today | Postgres (power marts) | 5 min | v1 |
| Overview | Host meters (CPU, RAM, disk, swap, temp) | Glances `/api/4` (verify version) | 5 s | v1 |
| Overview | Needs attention | Kuma + Sonarr/Radarr + Duplicati | 30 s | v1 |
| Overview | Now playing | Tautulli | 10 s | v1 |
| Media | Now playing | Tautulli | 10 s | v1 |
| Media | Download queue | qBittorrent `/torrents/info` | 2 s | v1 |
| Media | Movies tile (count, size, added, missing, quality split) | Radarr API | 15 min | v1 |
| Media | TV tile (series, episodes, size, missing, quality split) | Sonarr API | 15 min | v1 |
| Media | Media storage (used/free by category, growth, months left) | Glances disk + Radarr/Sonarr sizes | 1 h | v1 |
| Media | Recently added | Radarr, Sonarr, Audiobookshelf | 15 min | v1 |
| Media | Upcoming | Sonarr/Radarr calendar | 15 min | v1 |
| Media | Library browser (search, sort, poster grid, deep links) | Plex `/library/sections/{id}/all`, Audiobookshelf | 15 min | v1 |
| Home | Power use, 14 days | Postgres (power marts) | 5 min | v1 |
| Home | Right now (watts, temp, humidity, entities) | Home Assistant REST | 15 s | v1 |
| Home | Temperature, 24 h | Home Assistant history | 5 min | v1 |
| Finance | Filters (owner, account, type) | frontend state | - | v1 |
| Finance | Month spend, income, net | `fct_simplefin_transactions` | daily | v1 |
| Finance | Upcoming recurring bills, 30 days + total | `is_recurring`, `billing_cycle` | daily | v1 |
| Finance | Net balance, 90 days | balances model (Prerequisite A) | daily | v1 |
| Finance | Spending by category / income by source | `fct_simplefin_transactions` | daily | v1 |
| Finance | Transactions table, accounts table, last sync | fct, balances, extractor logs | daily | v1 |
| dbt | Last run, runs/failed/success-rate (30 d vs prior) | dbt run log (Prerequisite B) | 5 min | v1 |
| dbt | Runs per day (completed vs failed) and 7-day success rate | dbt run log | 5 min | v1 |
| dbt | Next scheduled runs | `dbt/cron/dbt-schedule` via croniter | 1 min | v1 |
| dbt | Recent runs with failure message | dbt run log | 5 min | v1 |
| Services | Grouped launcher + filter + health dots | `services.yaml` + Kuma | 30 s | v1 |

Plex deep link format (Movies/TV):

```
http://100.82.35.70:32400/web/index.html#!/server/<machineIdentifier>/details?key=%2Flibrary%2Fmetadata%2F<ratingKey>
```

`machineIdentifier` comes from Plex `/identity` once at startup. Posters are proxied through
`/api/art/plex/<ratingKey>` so the Plex token never reaches the browser. Audiobooks:
`https://audiobooks.damattberghome.duckdns.org/item/<libraryItemId>`.

### Prerequisites (data work, outside the hub container)

**A. Finance models**
- Balances fact for the 90-day balance chart and the accounts table. Only `stg_simplefin_balances` exists today. Add a daily-grain balances model (one row per account per day) following `dbt_resources/key_design_cheatsheet.md` and `fct_table_grain` conventions.
- Recurring bills: derive the upcoming list from `is_recurring` and `billing_cycle` in a CTE model (`dim_recurring_bills` or equivalent) that projects the next due date and typical amount per payee. Decide the rule for amount (last, average of last 3).
- Confirm `account_owner` values (the mock-up's "Matt / Jess / Joint" are placeholders; Jess is confirmed, verify Joint).
- Confirm sign convention and `transaction_type` values.
- Plan these with the `dbt-sql-standards` and `dbt-yaml-standards` skills (CTEs, no subqueries, key suffix rules).

**B. dbt run history**
- Edit `run-dbt.sh` to append one JSON line per run to a bind-mounted log, for example `home_metrics_dbt/logs/run_history.jsonl`:
  `{"started":"...","finished":"...","mode":"regular|refresh","exit":0,"models_ok":64,"models_total":64,"tests_ok":212,"tests_total":212,"error":"first line of summarize_dbt_errors"}`
- `run-dbt.sh` already computes the failure summary (`summarize_dbt_errors`) and the exit code. Model/test counts come from `target/run_results.json` right after the build.
- The logs folder is a bind mount under the repo, so Duplicati backs it up. The hub reads it read-only.
- Optional later: load the same rows into a Postgres table so the hub can query them with SQL.
- Healthchecks.io pings and the Discord alerts are unchanged.

**C. Postgres role**

```sql
create role hub_ro login password '<from .env>';
grant connect on database <db> to hub_ro;
grant usage on schema <marts_schema> to hub_ro;
grant select on all tables in schema <marts_schema> to hub_ro;
alter default privileges in schema <marts_schema> grant select on tables to hub_ro;
```

Use the actual schema names from `dbt_project.yml`. Do not grant access to raw/source schemas.

**D. Service credentials (all go in `hub/.env`, never committed)**
Plex token, Tautulli API key, Radarr and Sonarr API keys, Audiobookshelf API token, Home Assistant long-lived token, qBittorrent credentials, Uptime Kuma (status page slug or API key for metrics), `hub_ro` password. Create read-only keys where the service supports it.

## Task Breakdown

### Phase 0: Design (done)
1. [x] Interactive mock-up with tabs, live-tick widgets, color schemes, finance filters, dbt tab, library browser
2. [x] This plan
3. [x] Matt picks the v1 widget list (all candidates)

### Phase 1: Skeleton + launcher
1. [x] Create `docker-projects/hub/` (Dockerfile, compose, `.env.example`, `.gitignore` entries, `data/.gitkeep`)
2. [x] FastAPI app: `/healthz`, `/api/config`, static mount; `base.css` and `themes.css` from the mock-up
3. [ ] `services.yaml` with all 25 services; Services page; Kuma health dots (built; dots need `KUMA_API_KEY` in `hub/.env`)
4. [x] Join networks; add Caddy route and Caddy network; add `hub` to start/stop scripts
5. [x] Update `docker/CLAUDE.md` Services Reference; add `homelab-docs/hub/README.md`
6. [ ] Verify through `https://hub.damattberghome.duckdns.org` on desktop and phone

### Phase 2: Core engine + system and media widgets
1. [ ] Poller, cache, timeouts, stale handling, `/api/widgets/{id}`
2. [ ] Frontend polling loop and shared chart helpers (port from the mock-up)
3. [ ] Overview widgets (Kuma, Glances, qBittorrent, Tautulli)
4. [ ] Media widgets (Radarr/Sonarr stats, storage, queue, upcoming, recently added)
5. [ ] qBittorrent widget logs in with credentials from `.env` (403 is the unauthenticated response, see Risk 2)

### Phase 3: SQL-backed pages
1. [ ] Prerequisite C (`hub_ro`) and `db.py`
2. [ ] Prerequisite A (finance models) and the Finance page with filters
3. [ ] Home page (power marts, Home Assistant)
4. [ ] Prerequisite B (run history) and the dbt page

### Phase 4: Library browser + polish
1. [ ] Plex library browser with deep links and poster proxy; Audiobookshelf links
2. [ ] Phone layout pass, keyboard shortcuts, search across services
3. [ ] Extra color schemes, per-page accent option, `pages.yaml` validation errors shown in the UI
4. [ ] Decide whether to retire Homarr (Matt's call)

## Verification Steps

1. `docker compose up -d --build` in `hub/`; `docker ps` shows `hub` healthy.
2. `curl -s http://hub:8000/healthz` from another container on the network returns OK.
3. `curl -sk https://hub.damattberghome.duckdns.org/` returns the page (200) from a tailnet device; Caddy logs show no 502.
4. Confirm no secret leaks: `curl -s https://hub.../api/config` and a sample of `/api/widgets/*` contain no tokens, keys or passwords. Search the repo with `git grep` for the `.env` values.
5. Stop one upstream (for example `docker stop sonarr`); only its widgets show "down" with last-known data; the rest keep updating. Start it again; it recovers without restarting the hub.
6. Start a download in qBittorrent; the Overview throughput chart reflects it within ~4 s with no page refresh.
7. Edit `themes.css` and `pages.yaml`; refresh the browser; changes appear without a rebuild.
8. Finance: filter by owner and account; month totals match a manual SQL check against `fct_simplefin_transactions`.
9. dbt: trigger `run-dbt.sh regular` manually; a new line appears in `run_history.jsonl` and in "Recent runs" within one poll. Force a failing test and confirm the failure message shows.
10. Plex link: click three titles; each opens the correct Plex page. Check a poster loads through `/api/art/plex/...` with no token in the URL.
11. Reboot the host (or restart Docker Desktop); `start-all-services.ps1` brings the hub up before Caddy and the hub URL works.
12. Confirm Duplicati's source covers `hub/` (bind mounts only) and that Homarr is unchanged.

## Risks and Open Questions

| # | Item | Mitigation |
|---|------|------------|
| 2 | qBittorrent API returns 403 | Checked 2026-10-26: 403 is only the unauthenticated response (`ServerDomains=*`, CSRF ignores server-side calls). Widget logs in via `/api/v2/auth/login` and reuses the SID cookie |
| 3 | Uptime Kuma has no stable REST API for status | Use a public status page JSON or the `/metrics` endpoint with an API key; verify against the `:1` image in use |
| 4 | Glances API version path (`/api/3` vs `/api/4`) | Check `glances:61208/api/4/status` before writing the widget |
| 5 | Finance and dbt tabs depend on dbt work | Phase 3 ordering; ship Phases 1-2 without them |
| 6 | Hub can read every container on the joined networks | Read-only keys; `hub_ro` only; no write actions in v1 |
| 7 | Finance numbers visible to anyone on the tailnet | Acceptable for a single-user tailnet; add per-page gating if that changes |
| 8 | Network removal (`docker compose down` on a stack) breaks hub start | Same caveat as Caddy; document in the hub README |
| 9 | Plex machine ID or ratingKeys change after a Plex reinstall | Looked up at startup and refreshed every poll, never hard-coded |
