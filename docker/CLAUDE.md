# Docker Homelab Project

Windows-based homelab running Docker Desktop with media stack, monitoring, automation, and analytics services.

## Repository Structure

**Monorepo:** [mdamberg/homelab](https://github.com/mdamberg/homelab) — stored at `C:\Users\mattd\repos\homelab\`

```
homelab/
├── docker/                        # This folder — Docker services and scripts
│   ├── docker-projects/           # All Docker services (compose files, configs)
│   │   ├── media_stack/           # Plex, *arr apps, qBittorrent, Portainer
│   │   ├── monitoring/            # Uptime Kuma, Glances
│   │   ├── n8n/                   # Workflow automation
│   │   ├── lightdash/             # Analytics dashboards
│   │   ├── backups/               # Duplicati
│   │   └── ...
│   ├── start-all-services.ps1
│   ├── stop-all-services.ps1
│   ├── setup-autostart.ps1
│   └── CLAUDE.md                  # This file
├── dbt/                           # Postgres + dbt models (home-metrics)
└── docs/                          # Homelab documentation (markdown)
```

### Canonical Paths — Never OneDrive

**The only paths we use are `C:\Users\mattd\repos\homelab\docker\...` and `C:\Users\mattd\repos\homelab\dbt\...`.**

The legacy tree was retired on 2026-07-15 and renamed to `C:\Users\mattd\OneDrive\Matts Documents\Docker-RETIRED-20260715\`. The old `...\Docker\` path no longer exists, so compose files there cannot resolve. The retired tree is kept only as a rollback snapshot; it will be deleted once a Duplicati restore test passes. Never `cd` into it, never run `docker compose` from it, and never write a path containing `OneDrive` into a compose file, script, or doc. Data written there is invisible to the Duplicati backup, which only sources the repo path.

**A committed config change does nothing until the container is recreated from the repo.** Containers keep the bind-mount paths they were *created* with, and `restart: unless-stopped` resurrects them from those old definitions after every Docker Desktop restart. So a container created long ago from the OneDrive tree keeps mounting OneDrive no matter what the repo says. Editing the compose file in git is not the fix — recreating the container is:

```powershell
cd C:\Users\mattd\repos\homelab\docker\docker-projects\<service>
docker compose up -d --force-recreate
```

Verify which tree a container actually runs from — trust this, not the compose file:

```powershell
docker inspect <container> --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
docker inspect <container> --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
```

This split is the known cause of the flat-JSON to-do apps' data loss: the app silently reads whichever `data/` folder its container was created against, so a container recreated from the wrong tree serves stale data and writes new data somewhere that is never backed up.

### Persistence and Backup

**Default to a bind mount under `docker-projects/`** (`./data:/app/data`). Duplicati's source is the repo's `docker-projects/` folder, so a bind mount there is persistent *and* automatically backed up with no extra machinery.

Named volumes are **not** covered by Duplicati automatically. If an image requires one, it must also be mounted read-only into `backups/docker-compose.yml` or its data is unprotected. Full decision table and examples: `.claude/skills/new-container/SKILL.md` (Phase 5).

### Container Distribution

| Folder | Count | Contains |
|--------|-------|----------|
| docker/docker-projects | 35 | All homelab services (media, monitoring, automation, utilities) |
| dbt | 2 | Analytics DB layer (home-metrics-postgres, home-metrics-metabase) |

**Note:** Two visualization tools exist — Lightdash (docker) and Metabase (dbt). Both connect to Postgres for analytics.

### What Goes Where

| Change Type | Location | Example |
|-------------|----------|---------|
| New Docker service | `docker/docker-projects/<service>/` | Adding Jellyfin |
| Service config changes | `docker/docker-projects/<service>/` | Updating compose file |
| Documentation | `docs/` | How-to guides, READMEs |
| dbt models | `dbt/` | SQL transformations |
| Project plans | `docker/docker-projects/project-plans/<type>/` | Planning docs |
| Utility scripts | `docker/` | PowerShell helpers |

## Common Commands

```powershell
# Start/stop a service
cd C:\Users\mattd\repos\homelab\docker\docker-projects\<service>
docker compose up -d
docker compose down

# Check service health
docker compose ps
docker compose logs -f <container>

# Start/stop all services
C:\Users\mattd\repos\homelab\docker\docker-projects\start-all-services.ps1
C:\Users\mattd\repos\homelab\docker\docker-projects\stop-all-services.ps1
```

**Important:** When adding new containers, always add them to `start-all-services.ps1` where applicable.

## Key Architecture Notes

- **Home Assistant**: Runs in **Docker** (`docker-projects/home_assist`) on port 8123. A VirtualBox VM named `HomeAssistant` is still registered but is **powered off**, and 10.0.0.46 does not respond — the container is the live instance. Verify before acting on any claim about which one is real:
  ```powershell
  & 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' list runningvms   # empty = VM is off
  docker inspect homeassistant --format '{{.State.Status}}'
  ```
- **VPN**: qBittorrent routes through Gluetun container (PIA VPN)
- **Media paths**: `C:\media\` for downloads, movies, tv, config
  - The C:\Media\downloads path is most used
- **Remote access**: Tailscale (WireGuard blocked by CGNAT)

## Services Reference

| Service | Port | Notes |
|---------|------|-------|
| Plex | 32400 | Media server |
| Radarr | 7878 | Movies |
| Sonarr | 8989 | TV Shows |
| Prowlarr | 9696 | Indexer manager |
| qBittorrent | 8080 | Via Gluetun VPN |
| Overseerr | 5055 | Media requests |
| Tautulli | 8181 | Plex stats |
| LazyLibrarian | 5299 | Books |
| Audiobookshelf | 13378 | Audiobooks/podcasts |
| Home Assistant | 8123 | Docker (`home_assist`); the VirtualBox VM is powered off |
| n8n | 5678 | Workflow automation |
| Uptime Kuma | 3001 | Monitoring |
| Glances | 61208 | System stats |
| Lightdash | 8090 | Analytics dashboards |
| Portainer | 9443 | Docker management |
| Homarr | 7575 | Dashboard |
| Dashdot | 3002 | System monitor |
| Flash Todo | 5070 | To-do app |
| Jelu | 5072 | "To be read" book tracker (SQLite) |
| Linkding | 8282 | Bookmarks |
| Duplicati | 8200 | Backups |
| Pi-hole | 8082 | Admin UI; actively serving DNS on port 53 |

## Code Style

- 2-space indentation for YAML
- Use `${VAR}` env references, keep secrets in `.env` files
- Pin image versions for critical services (avoid `:latest` for databases)
- Group services with comment headers in compose files
- Avoid subqueries at all costs for sql work.
- When writing code, avoid in line comments that do not relate to the code, such as "if you prefer this, than change to that" 
- In-line comments that explain complex code are always appreciated and desired. 
- Organization is very important, when adding code/files/folders it is imperative that we do so in the spot that makes the most logical sense

## Workflows

### Adding a new service
1. Create `docker/docker-projects/<service>/docker-compose.yml`
2. Add `.env` for sensitive values
3. Test with `docker compose up -d && docker compose ps`
4. Add to `docker/docker-projects/start-all-services.ps1`
5. Document in `docs/`

### Project planning
For non-trivial work, use `/project-planning` to enter structured planning mode:
1. **Existing work detection** - check for related plans, workflows, code
2. **Discovery interview** - understand problem and success criteria
3. **Scope & Goals** - define boundaries and measurable outcomes
4. **Technical approach** - determine how, with rationale
5. **Risk assessment** - identify pitfalls and mitigations
6. **Task breakdown** - structure into phases and tasks
7. **User approval** - explicit agreement before implementation
8. **Auto-handoff** - invoke appropriate builder skill (dbt-query, n8n-workflow, docker-service)

Plans are saved to `docker/docker-projects/project-plans/<type>/` for documentation. For n8n projects, the skill queries the MCP server to understand existing workflows before planning.

### Deleting media properly
Delete through Radarr/Sonarr UI, not filesystem. See `docs/media-stack/ops/deleting-media.md`

### Git commits
- Imperative mood: "Add feature" not "Added feature"
- Never commit `.env` files or secrets
- Check `docs/TODO.md` for pending security items
- Always check with user before pushing

## Common Gotchas

- Docker Desktop on Windows runs in WSL2 VM - containers can't directly access LAN devices
- If Docker hangs on "starting": `wsl --shutdown` then restart Docker Desktop
- Lightdash requires: `docker network create home-metrics`
- n8n workflows reference Home Assistant at `10.0.0.46` (the old VirtualBox VM). **That VM is powered off, so those workflows are broken** — they need repointing at the Docker container before they will run again.

## Documentation

Always check `docs/SUMMARY.md` for existing docs before creating new ones. Key references:
- `docs/TODO.md` - Prioritized security/config fixes
- `docs/homelab-docker-review.md` - Full infrastructure audit
- `homelab-docs/home-assistant/README.md` - Home Assistant setup

When creating new containers or infrastructure, always update docs with either a new entry if what's getting added is new or update existing docs.
