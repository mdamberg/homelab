{{ config(
    materialized= 'table',
    schema = 'marts'
) }}

-- ================================================== --
-- Grain: 1 row per alert
-- ================================================== --

with alerts as (
    select
        alert_pk,
        alert_type_key,
        alert_severity_key,
        alert_category,
        alert_type,
        severity,
        alert_source,
        title,
        message,
        triggered_at,
        triggered_at_local,
        date_triggered,
        time_triggered,
        resolved_at,
        is_active,
        inserted_at,

        -- node_error alert fields
        execution_id as workflow_run_fk,
        workflow_id,
        failed_node,

        -- no_data alert fields
        monitored_table,
        threshold_minutes

    from {{ ref('stg_n8n_alerts') }}
)

select * from alerts
