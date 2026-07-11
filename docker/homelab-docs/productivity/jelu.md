# Jelu — "To Be Read" Book Tracker

Self-hosted reading list / book tracker. Add books, move them through a
**To Read → Currently Reading → Read** workflow, tag/shelve them, and track your library.
This is the homelab's personal reading queue (distinct from LazyLibrarian, which handles
book *acquisition*).

## Access

| Item | Value |
|------|-------|
| Local URL | http://10.0.0.7:5072 |
| Remote URL (Tailscale) | http://100.82.35.70:5072 |
| Port | 5072 (mapped from container port 11111) |
| Container | `jelu` |
| Image | `wabayang/jelu:0.84.2` |

> First launch: open the URL and complete the initial setup to create your admin user.

## Features

- Reading-status workflow (to-read / currently reading / read / dropped)
- Tags & custom shelves
- Priority-style organization via tags/shelves
- REST API for integrations (e.g. a Scriptable widget), same idea as the to-do apps
- ISBN / title / author metadata lookup and Goodreads CSV import
- Cover art and reading statistics

## Compose Location

```
docker-projects/jelu/docker-compose.yml
```

## Data & Persistence

Jelu stores everything in **SQLite**, kept in **bind-mounted folders under the compose directory**:

| Container path | Host folder | Holds |
|----------------|-------------|-------|
| `/database` | `docker-projects/jelu/database` | SQLite database (your books) |
| `/config` | `docker-projects/jelu/config` | App config |
| `/files/images` | `docker-projects/jelu/files/images` | Book cover images |
| `/files/imports` | `docker-projects/jelu/files/imports` | Import files |

Because these are plain folders inside `docker-projects/`, the data:
1. **Persists** across container restarts / recreation — no restore needed, the data is simply still there.
2. Is **crash-safe** — SQLite is transactional (unlike the flat-JSON to-do apps).
3. Is **automatically backed up** by Duplicati, which already backs up the whole `docker-projects/` folder.

The actual `database/`, `config/`, and `files/` contents are gitignored (only `.gitkeep`
placeholders are tracked) — the real safety net is Duplicati, not git.

## Management

```powershell
cd C:\Users\mattd\repos\homelab\docker\docker-projects\jelu

docker compose up -d      # Start
docker compose down       # Stop
docker compose logs -f    # Logs
docker compose ps         # Health
```

## Backup & Restore

No special steps needed — Jelu's data lives in `docker-projects/jelu/` and is captured by the
existing Duplicati backup of `docker-projects/`.

To restore after data loss: stop Jelu, restore `docker-projects/jelu/` (especially `database/`)
from Duplicati, then `docker compose up -d`.

## Updating

```powershell
cd C:\Users\mattd\repos\homelab\docker\docker-projects\jelu
# bump the pinned tag in docker-compose.yml, then:
docker compose pull
docker compose up -d
```
