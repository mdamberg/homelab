# Staging Table Grain Definitions

This file documents the granularity for each staging model. Staging models are 1:1 with their source tables with light transformations (renaming, type casting, filtering).

---

## Media Tracking

1. **stg_media_activity**
   - Grain: 1 row per media watch event
   - Primary key: `id`
   - Source: `raw_media_activity`

2. **stg_media_library**
   - Grain: 1 row per library snapshot (per source + media_type + library_name + recorded_at)
   - Primary key: `id`
   - Source: `raw_media_library`

---

## Network Monitoring

3. **stg_pihole_metrics**
   - Grain: 1 row per pihole metrics snapshot (per pihole_instance per recorded_at)
   - Primary key: `id`
   - Source: `raw_pihole_metrics`

---

## Workflow Monitoring (n8n)

4. **stg_n8n_workflow_runs**
   - Grain: 1 row per workflow execution
   - Primary key: `id`
   - Source: `raw_n8n_workflow_runs`

5. **stg_n8n_alerts**
   - Grain: 1 row per alert triggered
   - Primary key: `id`
   - Source: `raw_n8n_alerts`
