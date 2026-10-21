---
name: docker-service
description: Add a new Docker service to the homelab (compose file, .env secrets, networks, start/stop scripts, homelab-docs entry) or audit an existing compose file for missing restart policy, timezone, healthcheck, or pinned images. Use when the user wants to add, move, or fix a container or compose service in docker/docker-projects/.
---

# Docker Service

Adds or audits a service under `docker/docker-projects/<service>/`. `docker/CLAUDE.md` has the high-level workflow; this skill is the detailed checklist.

## Ask first (skip what is already answered)

Image and version, persistent data, ports, secrets, dependencies on other containers, whether it should join the `home-metrics` network, whether it should start with the system.

## Compose file

```yaml
services:
  <name>:
    image: <image>:<tag>
    container_name: <name>
    restart: unless-stopped
    environment:
      - TZ=America/Chicago
    volumes:
      - ./config:/config
    ports:
      - "<host>:<container>"
```

- Explicit `container_name`, `restart: unless-stopped`, and `TZ=America/Chicago` on every service.
- **Pin the image tag** for databases and anything stateful or critical. `:latest` is acceptable only for low-risk apps that Watchtower manages.
- Add a `healthcheck` to databases and to any service another service `depends_on`. Use `condition: service_healthy` in the dependent (see `lightdash/docker-compose.yml`).
- Relative paths for service config (`./config`); absolute `C:/media/...` for shared media. Forward slashes on Windows.
- 2-space YAML, a comment header per group of services.
- Services that must reach Postgres/dbt join the external network: `docker network create home-metrics` once, then `networks: home-metrics: external: true`. VPN-routed services go through Gluetun.

## Volumes and backup

Duplicati backs up the whole `docker/docker-projects/` folder, so where data lives decides whether it is backed up.

| Mount type | Looks like | Backed up by Duplicati? |
|---|---|---|
| Bind mount (default) | `./data:/data` | Yes, automatically |
| Named volume | `mydata:/data` + top-level `volumes:` | No. Lives inside the WSL2 VM |

- Default to bind mounts under the service folder (see `jelu`, `flash_todo`). Add a `.gitkeep` and gitignore the live data (`data/*` + `!data/.gitkeep`); never commit databases or binaries.
- Use a named volume only when the image strongly expects one or for heavy database writes. Then also mount it read-only into `backups/docker-compose.yml`, or its data is unprotected. Compose prefixes the real volume name with the project folder name, so confirm it with `docker volume ls`:

```yaml
# backups/docker-compose.yml
    volumes:
      - "mydata:/source/mydata:ro"
volumes:
  mydata:
    external: true
    name: <project>_mydata
```

## Secrets

Put values in a `.env` beside the compose file and reference them as `${VAR}`. Confirm `.env` is gitignored before creating it; never commit it or echo its values.

## Start and stop scripts

Both `docker/docker-projects/start-all-services.ps1` and `stop-all-services.ps1` hold a `$InfraServices` hashtable mapping a service key to its folder. Add the key to **both**, and add it to the `Valid values` list in each script's header comment.

## Verify

```
cd docker/docker-projects/<service>
docker compose config        # validates the file and env substitution
docker compose up -d
docker compose ps            # Up / healthy
docker compose logs --tail 50
```

If Docker is not available in the current session, run only `docker compose config` where possible and say what was not verified.

## Docs (required by CLAUDE.md)

1. Create `docker/homelab-docs/<area>/services/<name>.md` (or add to the stack's README) using the existing service-doc shape: **Overview** (what it does, why it exists), **Ports**, **How It Works**, **Service Interactions** (receives from / sends to).
2. Add it to `docker/homelab-docs/SUMMARY.md`.
3. Add a row to the Services Reference table in `docker/CLAUDE.md` if it is a user-facing service.
4. If it should be monitored, note the Uptime Kuma monitor to create.

## Audit mode

When asked to review an existing compose file, report these before changing anything: missing `restart`, missing `TZ`, `:latest` on a database or critical service, missing `healthcheck` where something depends on it, hardcoded secrets, service missing from the start/stop scripts, no homelab-docs entry. Fix only what the user approves.

## Checklist

- [ ] Compose follows the rules above
- [ ] Secrets in `.env`, gitignored
- [ ] Added to start and stop scripts (+ header lists)
- [ ] `docker compose config` clean; `up -d` and `ps` checked when possible
- [ ] homelab-docs, SUMMARY.md, and CLAUDE.md updated
