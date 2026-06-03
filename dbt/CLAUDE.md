# Home Metrics Infrastructure

Analytics database layer for the homelab. Provides PostgreSQL for data storage and Metabase for visualization.

## Related Sections (homelab monorepo)

| Folder | Purpose | Connection |
|--------|---------|------------|
| **dbt/** (this folder) | Postgres + Metabase | Database and visualization |
| docker/docker-projects | Main homelab services | n8n writes data here, dbt transforms it |

## Services

| Container | Port | Purpose |
|-----------|------|---------|
| home-metrics-postgres | 5432 | PostgreSQL 16 database |
| home-metrics-metabase | 3000 | Metabase visualization UI |
| home-metrics-dbt-runner | - | Scheduled dbt runs via supercronic (schedule in `cron/dbt-schedule`) |

## Common Commands

```powershell
# Start services (preferred - creates network automatically)
.\start-services.ps1

# Stop services
.\stop-services.ps1

# Or manually:
docker compose up -d
docker compose down

# Check status
docker compose ps

# View Postgres logs
docker compose logs -f postgres

# Connect to Postgres CLI
docker exec -it home-metrics-postgres psql -U <username> -d <database>
```

## Data Pipeline

```
n8n (docker/docker-projects/n8n)
    ↓ writes raw data
PostgreSQL (dbt/)
    ↓ transformed by
dbt models (dbt/home_metrics_dbt)
    ↓ visualized in
Metabase (dbt/) or Lightdash (docker/docker-projects/lightdash)
```

## File Structure

```
homelab/dbt/
├── docker-compose.yml    # Postgres + Metabase services
├── start-services.ps1    # Start script (creates network, starts containers)
├── stop-services.ps1     # Stop script
├── .env                  # Database credentials (do not commit)
├── .env.example          # Template for .env
├── postgres/
│   ├── data/             # Database files (gitignored)
│   └── init/             # SQL scripts run on first start
├── metabase/
│   └── data/             # Metabase config
└── README.md             # Setup documentation
```

## Adding New Services

When adding a new service to this repo:
1. Add service to `docker-compose.yml`
2. Update `start-services.ps1` if special startup logic needed
3. Update this CLAUDE.md with port and purpose
4. Document in README.md

## Network

Uses `home-metrics` Docker network. Other containers can connect to Postgres at:
- From same network: `postgres:5432`
- From host/other containers: `localhost:5432` or `host.docker.internal:5432`

## Code Style

- Use `${VAR}` references for all credentials
- Keep credentials in `.env`, never commit them
- SQL init scripts go in `postgres/init/` (numbered for order: 01-create.sql, 02-seed.sql)

## Gotchas

- Metabase depends on Postgres healthcheck - if Postgres isn't healthy, Metabase won't start
- The `home-metrics` network must exist for Lightdash (in docker/docker-projects/lightdash) to connect
- Database files in `postgres/data/` should be gitignored
