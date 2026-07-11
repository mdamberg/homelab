# Project: "To Be Read" (TBR) Book List — Jelu Container

**Created:** 2026-07-11
**Type:** docker
**Intent:** new
**Status:** Planning

## Discovery Summary

The user wants a new, interactive homelab container for a personal **"to be read" book list** —
a reading queue where they can add books, move them through a status workflow, prioritize, and
tag/categorize them. The functionality should feel like the existing homelab to-do apps
(`flash_todo`, `work_todo`), including a REST API for integrations (e.g. a Scriptable widget).

The **hard requirement is durability**: the existing to-do apps lose their data when the
container goes down. Root cause identified during discovery — those apps store everything in a
flat `todos.json` file on a **bind mount** (`./data:/app/data`) with **no database integrity**,
and the live data is not tracked in git. `flash_todo/data/` currently contains only a
`todos.json.backup`; the live `todos.json` is already gone. By contrast, `linkding` uses a real
database (SQLite) and has proven durable.

Discovery decisions (from the user):
- **Content:** Books (a personal reading queue, distinct from LazyLibrarian which handles acquisition).
- **Build approach:** Evaluate off-the-shelf images first; use one if it is capable/customizable,
  otherwise build a from-scratch Flask app like the to-do apps. **Chosen: deploy Jelu**, with the
  understanding that we can revert to a from-scratch Flask build (Option A below) if it disappoints.
- **Persistence:** SQLite + durable storage + Duplicati backup coverage.
- **Features that matter:** status workflow (To-Read → Reading → Read), priority & tags/category,
  and a REST API.

## Codebase Review

### Files Reviewed
- `docker-projects/flash_todo/{app.py,docker-compose.yml}` — Flask + flat JSON on a bind mount; the
  data-loss pattern we must NOT repeat. Good reference for the desired UX/features and API shape.
- `docker-projects/work_todo/docker-compose.yml` — same pattern; its `data/` dir is gitignored.
- `docker-projects/linkding/docker-compose.yml` — the durable reference: SQLite in a **named volume**.
- `docker-projects/backups/docker-compose.yml` — Duplicati backs up the **folder**
  `C:/Users/mattd/repos/homelab/docker/docker-projects` as `/source/docker-configs:ro`.
- `homelab-docs/productivity/linkding.md` — doc template; already flags that **named volumes may
  fall outside Duplicati's file-level backup**.
- `docker-projects/start-all-services.ps1` — `$InfraServices` map; new services must be registered here.
- `docker/CLAUDE.md` — conventions (TZ env, `restart: unless-stopped`, pinned versions, services table).

### Off-the-shelf options evaluated
| App | Stack | DB | Status/Tags/API | Maintained | Verdict |
|-----|-------|----|-----------------|-----------|---------|
| **Jelu** | Kotlin + Vue | **SQLite** | ✅ / ✅ / ✅ REST API | ✅ active (rel. Jun 2026) | **Chosen** |
| MyBibliotheca | Flask | KuzuDB (graph) | ✅ / ✅ / ? | ❌ "NOT maintained" | Rejected (unmaintained, non-SQLite) |
| BookLogr | Flask | — | To-Read list built-in | Less active | Backup option |
| Bibliotheca / BookTracker | Flask + SQLite | SQLite | partial | varies | Backup option |

Jelu wins: SQLite (fits the durability + Duplicati requirement), native reading-status workflow,
tags/shelves, a documented REST API, ISBN & Goodreads import, cover art, MIT license, actively
maintained.

## Analysis Findings — The Persistence Decision (most important)

The user's stated preference was "named volume + SQLite + Duplicati." Discovery surfaced a gap:
Duplicati's backup source is the **folder** `docker-projects/`, so a **named volume is NOT backed
up** by the current Duplicati job (it lives in Docker's WSL2 VM, outside that folder). This is the
exact caveat `linkding.md` already warns about.

**Recommendation:** bind-mount Jelu's data into `docker-projects/jelu/` instead of using a named
volume. This delivers all three goals cleanly:
1. **Survives container going down** — data lives on the host, independent of the container lifecycle.
2. **Crash-safe** — SQLite (transactional) replaces the fragile flat-JSON write pattern.
3. **Backed up automatically** — it sits inside Duplicati's existing `/source/docker-configs` mount,
   so no extra backup machinery is needed. (A named volume would require an added `docker run … tar`
   export step to be covered.)

> This is the one point that deviates from the user's earlier "named volume" pick, so it will be
> confirmed with the user before implementation.

## Scope & Goals

**Goals:**
- [ ] Deploy Jelu as a homelab container following `new-container` conventions.
- [ ] Persist SQLite + covers under `docker-projects/jelu/` so data survives recreation AND is
      captured by the existing Duplicati backup.
- [ ] Register in `start-all-services.ps1` and document it.

**Success Criteria:**
- [ ] Jelu reachable at `http://<host>:5072`; can add a book, set status/priority/tags, hit the API.
- [ ] After `docker compose down && up` (and after `down` + folder intact), the book list is unchanged.
- [ ] Jelu's `database/` appears in a Duplicati backup run.

**Out of Scope:**
- The from-scratch Flask app (kept as documented fallback "Option A" if Jelu is rejected).
- Multi-user setup, Goodreads migration, remote (Tailscale) exposure hardening.

## Technical Approach

### Key Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| App | Jelu (`wabayang/jelu`) | SQLite + status/tags/API, maintained, MIT |
| Storage | Bind mounts under `docker-projects/jelu/` | Survives recreation + inside Duplicati source |
| DB integrity | SQLite (built into Jelu) | Fixes the flat-JSON corruption/loss pattern |
| Host port | `5072` → container `11111` | Groups with list apps (flash 5070, work 5071) |
| Network | `media_stack_default` (external) | Consistent with to-do apps; visible to Homarr |
| Timezone | `TZ=${TZ}` env (no `/etc/timezone` bind) | Windows Docker Desktop has no host `/etc/timezone` |
| Version pin | Pin a released tag (not `:latest`) | CLAUDE.md convention for data services |

### Proposed Files
**Create:**
- `docker-projects/jelu/docker-compose.yml` — service def (image, port 5072:11111, bind mounts, TZ).
- `docker-projects/jelu/.env.example` — `TZ=America/Chicago`.
- `docker-projects/jelu/.gitignore` — ignore `database/*`, `files/**` data + `config/*` runtime,
  keep the folders via `.gitkeep`.
- `docker-projects/jelu/{config,database,files/images,files/imports}/.gitkeep` — ensure dirs exist on clone.
- `homelab-docs/productivity/jelu.md` — access, management, backup/restore, updating (mirror `linkding.md`).

**Modify:**
- `docker-projects/start-all-services.ps1` — add `'jelu' = 'jelu'` to `$InfraServices`; add `jelu`
  to the valid-values docstring.
- `docker/CLAUDE.md` — add a Jelu row to the Services Reference table.

### docker-compose.yml (proposed)
```yaml
services:
  jelu:
    image: wabayang/jelu:<pinned-tag>
    container_name: jelu
    ports:
      - "5072:11111"          # host:container
    volumes:
      - ./config:/config
      - ./database:/database        # SQLite DB — inside Duplicati backup source
      - ./files/images:/files/images
      - ./files/imports:/files/imports
    environment:
      - TZ=${TZ}
    restart: unless-stopped
    networks:
      - homarr_net

networks:
  homarr_net:
    external: true
    name: media_stack_default
```

## Task Breakdown

### Phase 1: Container files
1. [ ] Create `docker-projects/jelu/` with compose, `.env.example`, `.gitignore`, `.gitkeep`s.
2. [ ] Pin a current Jelu release tag.

### Phase 2: Integration
3. [ ] Register `jelu` in `start-all-services.ps1`.
4. [ ] Add Jelu to the `CLAUDE.md` services table.

### Phase 3: Docs
5. [ ] Write `homelab-docs/productivity/jelu.md` (mirror linkding: access/manage/backup/update).
6. [ ] Note that Jelu's `database/` is covered by the existing Duplicati source (no compose change).

## Verification Steps

> Deployment runs on the user's Windows Docker Desktop host (not this environment). Verification is
> performed by the user after pulling the branch:
1. `cd docker-projects/jelu && docker compose up -d && docker compose ps` → container healthy.
2. Browse `http://<host>:5072`, complete first-run setup, add a book, set status/priority/tags.
3. `curl http://<host>:5072/<api-path>` → returns the book (API works).
4. `docker compose down && docker compose up -d` → book list persists.
5. Trigger a Duplicati run → confirm `docker-projects/jelu/database` is in the backup set.

## Fallback (Option A)

If Jelu is unsatisfactory, revert and build a from-scratch **Flask + SQLite** app modeled on
`flash_todo` (fields: title, author, status, priority, tags, notes; `/` UI + `/api/books` CRUD),
using the same bind-under-`docker-projects` persistence so durability/backup behavior is identical.
