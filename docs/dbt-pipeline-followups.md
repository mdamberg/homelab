# dbt Pipeline — Follow-ups (when home)

Context: dbt scheduled runs were silently failing since ~June 4. Root cause was two overlapping issues. Fixed one; the rest are below. Created 2026-06-15.

## Done this session (pushed to main, commits c1388f6..c2d40f0)
- [x] Fixed dbt Fusion breakage — pinned `dbt-postgres==1.10.0` + `dbt-core>=1.10,<1.11` in `dbt/dbt-runner/Dockerfile` (was silently pulling dbt-core 2.0.0a1 Fusion, which drops Postgres support). Container rebuilt + verified: `dbt run` passes 34/35.
- [x] Removed `teller_vendor_category` end-to-end (was Teller counterparty type, not a category).
- [x] Disabled WIP `dim_teller_categories` stub (`enabled=false`) so it stops failing the run.
- [x] Pinned 3 MCP server requirements to exact versions (same time-bomb pattern).

## P1 — Discord per-failure alerting
Healthchecks is one-shot (alerts only on green→red transition, not every failed run). To get an alert on EVERY failed run, post to Discord directly from the dbt job.
- [ ] Get a Discord webhook URL for the **DBT Notifications** channel. Mobile app can't create webhooks; options: desktop browser (discord.com/app → channel → Edit Channel → Integrations → Webhooks → New Webhook → Copy URL), OR reuse the existing webhook Healthchecks created (open it in the channel's webhook list → Copy URL).
- [ ] Put it in `dbt/.env` as `DISCORD_WEBHOOK_URL=...` (gitignored).
- [ ] Wire up: `run-dbt.sh` posts last ~1500 chars of dbt error to the webhook on failure; pass `DISCORD_WEBHOOK_URL` through `docker-compose.yml`; document in `.env.example`.
- [ ] Rebuild dbt-runner, trigger a failing run, confirm the Discord alert lands.

## P1 — Postgres bind-mount migration (the real cause of intermittent failures)
`fct_hardware_sensor` (~636k rows) intermittently fails with `FileFallocate(): Interrupted system call`. Disk is NOT full (199 GB free). Cause: Postgres data dir is a **Windows bind-mount** (`./postgres/data`), which is unreliable for DB writes through Docker Desktop's filesystem layer.
- [ ] `pg_dump` backup first (DB is only 482 MB).
- [ ] Switch `docker-compose.yml` postgres volume from bind-mount to a **named Docker volume** (lives natively in WSL2 ext4).
- [ ] Restore, then verify `dbt run` passes including `fct_hardware_sensor` reliably across repeated runs.
- [ ] Discuss risks before doing it (data migration, downtime).

## P2 — Verify alerting recovery loop
- [ ] Once pipeline is green, confirm the Healthchecks check flips to "up" and a recovery notification fires to Discord.

## P3 — Finish dim_teller_categories
- [ ] Build the real model: grain = one row per resolved `category` (+ `subcategory`), keyed on `category_key` = `surrogate(coalesce(custom_category, teller_category))`. Then re-enable.

## P3 — Investigate n8n raw ingestion staleness
- [ ] `raw.raw_teller_transactions` last inserted 2026-06-10 (5 days stale as of Jun 15). Separate from dbt — check the n8n Teller workflow.
