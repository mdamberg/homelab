# Project Plan: Media Hardlink Consolidation (single `/data` mount)

**Status:** Planned — not started
**Created:** 2026-09-26
**Type:** Docker infrastructure (media_stack)
**Depends on:** Plex movie-library consolidation (completed 2026-09-26)

## Problem

Radarr/Sonarr are set to use hardlinks (`copyUsingHardlinks: True`), but
[media_stack/docker-compose.yml](../../media_stack/docker-compose.yml) mounts each media
folder as a **separate** Docker bind mount:

| Container | Current media mounts |
|-----------|----------------------|
| plex | `/movies`, `/tv`, `/downloads` |
| radarr | `/movies`, `/downloads` |
| sonarr | `/tv`, `/downloads` |
| qbittorrent | `/downloads` |

Hardlinks cannot cross mount boundaries **inside a container**, even though on the host all
folders live on one NTFS volume (`C:\media`). So on import Radarr/Sonarr silently fall back to
a full **copy** — every imported title occupies disk twice (once in `/downloads` while seeding,
once in `/movies`). This is what produced the ~45 GB of duplicates cleaned up on 2026-09-26.

## Goal

- Imports use **hardlinks + atomic move** (instant, no byte duplication). A seeding torrent and
  its library copy share one inode; deleting the torrent later frees nothing extra and leaves the
  library file intact.
- `/downloads` stops accumulating: qBittorrent enforces a seed limit, then Radarr/Sonarr remove
  the completed torrent from the client.

**Success criteria:** download one test movie → it appears in `/movies` as a hardlink (same inode
as the `/downloads` file, verified with `ls -i`), total disk usage rises by the file size **once**,
the torrent seeds, and after the seed limit is hit the `/downloads` copy is auto-removed.

## Technical approach

Replace the three separate media mounts on each app with a **single common parent mount**
`C:/media:/data`, and repoint every in-app path to the `/data/...` equivalent. Inside each
container `/data/downloads`, `/data/movies`, `/data/tv` then share one mount → hardlinks work.

Config mounts stay as-is (`C:/media/config/<app>:/config`). `C:/media/config` sits under
`C:/media`, so it will also appear at `/data/config` inside the containers — harmless (the more
specific `/config` mount is what each app uses).

New media_stack mounts:

```yaml
plex:        [ C:/media/config/plex:/config,        C:/media:/data ]
radarr:      [ C:/media/config/radarr:/config,      C:/media:/data ]
sonarr:      [ C:/media/config/sonarr:/config,      C:/media:/data ]
qbittorrent: [ C:/media/config/qbittorrent:/config, C:/media:/data ]
```

qBittorrent runs `network_mode: service:gluetun` — that affects networking only, not volumes; the
mount change applies normally.

### Favorable conditions right now
- qBittorrent has **0 active torrents** (verified: no `.fastresume` files), so there are no
  seeding save-paths to migrate — do the cutover before new downloads start.
- Library is tiny (6 movies, ~2 TV shows) and entirely on the single `C:` volume, so any
  Radarr/Sonarr path update is an instant same-volume rename, not a real copy.

## Task breakdown

### 3a — Compose + recreate (media mounts)
1. Edit `media_stack/docker-compose.yml`: swap the per-folder media mounts for `C:/media:/data`
   on plex, radarr, sonarr, qbittorrent (leave every other service untouched).
2. Recreate only those four:
   ```powershell
   cd C:\Users\mattd\repos\homelab\docker\docker-projects\media_stack
   docker compose up -d --force-recreate plex radarr sonarr qbittorrent
   ```
3. Verify new mounts:
   ```powershell
   docker inspect radarr --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
   ```

### 3b — qBittorrent
- Set **Options → Downloads → Default Save Path** to `/data/downloads` (and temp/incomplete path
  if used). Category `radarr-movies` save path → `/data/downloads` (or a subfolder).
- Set a **seed limit**: Options → BitTorrent → "When ratio reaches X" / "seeding time reaches Y
  minutes" → **Remove torrent** (or Remove torrent and its files). Pick a ratio/time you're
  comfortable with.

### 3c — Radarr
- Settings → Media Management → confirm **Use Hardlinks instead of Copy** is on (it is).
- Add root folder `/data/movies`; move the existing 6 movies onto it (Movie Editor → select all →
  Root Folder → `/data/movies`). Because host files don't relocate, this is an instant rename.
  Remove the old `/movies` root folder afterward.
- Settings → Download Clients → qBittorrent → **Remove Completed** = on. Verify Remote Path
  Mappings are empty/consistent (both apps now see `/data/downloads`).

### 3d — Sonarr
- Same as 3c with root folder `/data/tv`, **Remove Completed** = on.

### 3e — Plex
- For **Movies** and **TV Shows**: ⋯ → Manage Library → Edit → Folders → add `/data/movies`
  (resp. `/data/tv`), remove the old `/movies` / `/tv` entry → Save → scan.
- Note: repointing a library folder can reset watch history for those items. Small library and no
  meaningful history here, so acceptable. Do it in one pass and confirm item counts match
  (Movies = 6, TV = current) afterward.

### 3f — Validation
1. Grab one test movie through Radarr.
2. After import, compare inodes:
   ```bash
   ls -i "/c/media/downloads/<release>/<file>"   "/c/media/movies/<Title (Year)>/<file>"
   ```
   Same inode = hardlink working. Total `du -sh /c/media` should rise by the file size only once.
3. Let the seed limit trigger (or force it) and confirm the `/downloads` copy is removed while the
   `/movies` copy stays.

## Risks & mitigations

| Risk | Mitigation |
|------|-----------|
| Plex watch history reset on folder repoint | Tiny library, negligible history; single-pass change; verify counts after |
| Radarr/Sonarr try to physically move existing files | Same NTFS volume → move is an instant rename; verify no duplication with `du` before/after |
| Overlapping `/config` under `/data` | Harmless; apps use the explicit `/config` mount |
| A new download starts mid-cutover | qBit has 0 torrents now — do 3a–3e in one sitting before grabbing anything |
| Wrong tree recreation (OneDrive split) | Confirm working_dir with `docker inspect` per docker/CLAUDE.md before/after recreate |

## Rollback

Revert the compose edit and `docker compose up -d --force-recreate plex radarr sonarr qbittorrent`.
In-app path changes (root folders, Plex library folders) revert by pointing back to `/movies`,
`/tv`, `/downloads`. Host files never move, so rollback is config-only.

## Docs to update on completion
- [docker/homelab-docs/media-stack/services/plex.md](../../../homelab-docs/media-stack/services/plex.md)
  and the Radarr/Sonarr service docs — record the `/data` layout and the hardlink requirement.
- docker/CLAUDE.md media-paths note if the canonical container paths change.
