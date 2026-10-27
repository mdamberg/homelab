---
name: n8n-workflow
description: Build or modify n8n workflows for the homelab data pipeline (collect from an API, write to a raw_* Postgres table, alert on failure) following the repo's existing workflow pattern. Use when adding or changing a workflow in docker/docker-projects/n8n, adding a new raw table fed by n8n, or wiring error alerting.
---

# n8n Workflow

Workflows live as exported JSON in `docker/docker-projects/n8n/` (snake_case file names) and run in the n8n container on port 5678. Their job is to land data in `raw_*` Postgres tables that dbt reads.

## Standard shape

Collection workflows follow this node pattern (see `system_health_metrics.json`, `hardware_sensors.json`):

1. `Schedule Trigger` named for its cadence ("Run Every 15 Minutes") plus a `Manual Trigger` for testing
2. `HTTP Request` to the source API
3. `Code` node named "Transform ..." that reshapes the response into rows matching the raw table's columns
4. `If` node "Has ... Data?" so empty responses do not insert
5. `Postgres` insert (upsert with `on conflict` when the source has stable ids, as in `teller_financial_sync.json`)
6. A `Sticky Note` titled "Setup Instructions" listing required credentials and the target table

Rules:
- Timestamps are written as UTC. dbt converts to local time with `to_local_time`.
- `metadata` (jsonb) holds source-specific extras; do not add columns for one-off fields.
- Credentials are referenced by name only. Never put keys, tokens, or webhook URLs in exported JSON.
- Use container names or the documented host IPs for services. Home Assistant runs in Docker (`home_assist`); older workflows still point at 10.0.0.46, the powered-off VirtualBox VM, and are broken until repointed. Do not copy that address into new workflows.

## Error handling

`error_catcher.json` is the shared error workflow: an Error Trigger formats the failure, inserts it into `raw_n8n_alerts`, and posts to Discord. Each collection workflow must point its **Settings -> Error Workflow** at it. The exported JSON in this repo does not record that setting, so confirm it in the n8n UI (or through the n8n-manager MCP tools if attached) instead of assuming.

`workflow_run_tracker.json` logs every execution to `raw_n8n_workflow_runs`; new workflows are covered automatically.

## New raw table checklist

A workflow that writes a new table is not done until all of these exist:

- [ ] DDL in `docker/docker-projects/n8n/migrations/NNN_<name>.sql` (next number in sequence)
- [ ] Entry in the domain's `dbt/home_metrics_dbt/models/staging/<domain>/sources.yml` with column descriptions and `freshness` sized to the schedule
- [ ] A row in the Active Workflows table and a column-mapping section in `docker/docker-projects/n8n/README.md`
- [ ] Exported JSON saved in `docker/docker-projects/n8n/`
- [ ] A staging model via `dbt-sql-standards` / `dbt-yaml-standards` when the data should reach dashboards

## Working with the n8n API

If the `n8n-manager` MCP tools are attached (`list_workflows`, `get_workflow`, `list_executions`, `create_workflow`, `trigger_workflow`, ...), use them to inspect existing workflows and executions before editing. If they are not attached, work from the exported JSON and say that live state was not checked.

Prefer small, targeted JSON edits to existing exports over regenerating whole workflows, so diffs stay reviewable.

## Verify

- Trigger the Manual Trigger once and confirm rows arrive: `select count(*), max(recorded_at) from raw_<table>;`
- Force a failure once to confirm the error workflow logs and alerts.
- If you cannot reach n8n or Postgres from this session, list these as steps for the user rather than reporting the workflow as tested.
