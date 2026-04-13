# Home Metrics Infrastructure

Analytics database layer for the homelab. Provides PostgreSQL for data storage and Metabase for visualization.

## Related Repos

| Repo | Purpose | Connection |
|------|---------|------------|
| **This repo** | Postgres + Metabase | Database and visualization |
| docker-projects | Main homelab services | n8n writes data here, dbt transforms it |

## Services

| Container | Port | Purpose |
|-----------|------|---------|
| home-metrics-postgres | 5432 | PostgreSQL 16 database |
| home-metrics-metabase | 3000 | Metabase visualization UI |

## Common Commands

```powershell
# Start services
docker compose up -d

# Stop services
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
n8n (docker-projects)
    ↓ writes raw data
PostgreSQL (this repo)
    ↓ transformed by
dbt models (docker-projects/home_metrics_dbt)
    ↓ visualized in
Metabase (this repo) or Lightdash (docker-projects)
```

## File Structure

```
home-metrics-infrastructure/
├── docker-compose.yml    # Postgres + Metabase services
├── .env                  # Database credentials (do not commit)
├── .env.example          # Template for .env
├── postgres/
│   ├── data/             # Database files (gitignored)
│   └── init/             # SQL scripts run on first start
├── metabase/
│   └── data/             # Metabase config
└── README.md             # Setup documentation
```

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
- The `home-metrics` network must exist for Lightdash (in docker-projects) to connect
- Database files in `postgres/data/` should be gitignored
