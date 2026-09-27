# Deleting media (so it stays deleted)

One-click, foolproof deletion of a movie or show that also clears every path by which it
would come back.

## Why deleted media used to come back

Not import lists (Radarr and Sonarr both have none) and not Overseerr watchlist auto-request
(off). The cause is **monitored orphans**: deleting only the *file* (via Plex, the filesystem,
or qBittorrent) leaves the Radarr/Sonarr record present and `monitored: true`, so it re-grabs on
the next RSS/search cycle. A lingering Overseerr request reinforces it.

A delete is only permanent if it also removes the **record** and adds an **import-list exclusion**.

## The one-click way — "Nuke Media" n8n workflow

n8n workflow **Nuke Media - one-click delete** (id `ns3lhCF64xLaEe0b`).

1. Open (phone, browser, or a Homarr tile):
   `http://<host>:5678/webhook/nuke-media?type=movie&q=<title>`
   (`type=tv` for shows; `q` accepts a title or a TMDB/TVDB id.)
2. A confirmation page shows the match, size, and what will happen.
3. Click **Confirm delete**. The confirm link carries a token (`type-<arrId>`) so you can only
   confirm the exact item that was resolved.

On confirm it:
- deletes the file + record from Radarr/Sonarr **with an import-list exclusion**,
- removes the matching Overseerr request/media record (deleting the media record clears its request),
- triggers a Plex library refresh.

Each step is best-effort, so one unavailable service does not block the rest.

## The exact API calls (for a manual delete if n8n is down)

Movie (Radarr, key in `radarr/config.xml`):
```
DELETE http://localhost:7878/api/v3/movie/{id}?deleteFiles=true&addImportExclusion=true
```
Show (Sonarr, key in `sonarr/config.xml`):
```
DELETE http://localhost:8989/api/v3/series/{id}?deleteFiles=true&addImportListExclusion=true
```
**The exclusion parameter differs:** Radarr uses `addImportExclusion`, Sonarr uses
`addImportListExclusion`. The workflow sends both names; each app uses its own and ignores the
other. Get `{id}` from `GET /api/v3/movie` or `/api/v3/series` (filter by title/tmdbId/tvdbId).

Then clear Overseerr (key in `overseerr/settings.json`):
```
GET    http://localhost:5055/api/v1/movie|tv/{tmdbId}   -> mediaInfo.id
DELETE http://localhost:5055/api/v1/media/{mediaId}
```
And refresh Plex (token in Plex `Preferences.xml`, sections: movies=1, tv=2):
```
GET http://localhost:32400/library/sections/{sectionId}/refresh?X-Plex-Token=<token>
```

## Notes

- API keys/token live in the workflow's **Parse and Config** node (not n8n credentials). Fine for
  single-user; move them to n8n Credentials to harden.
- Not yet wired: **Plex watchlist removal** and **qBittorrent torrent removal**.
- Verify a delete stuck: the title is absent from `GET /api/v3/movie|series` and present in
  Radarr `GET /api/v3/exclusions` (Sonarr `GET /api/v3/importlistexclusion`).
