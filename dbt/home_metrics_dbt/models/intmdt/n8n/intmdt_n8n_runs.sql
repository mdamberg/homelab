{{ config(
    materialized='table',
    schema='intmdt'
) }}

/*
# ============================================================================================== #
Joins n8n staging layers for Runs and Alerts
    - Join Keys:
        - N8N Alerts:           execution_id parsed from metadata and aliased as workflow_run_fk
        - N8N Workflow Runs:    workflow_run_pk

    - GRAIN
        - 1 row per workflow run per alert (runs with no alerts produce 1 row with null alert columns)
# ============================================================================================== #
*/

with n8n_workflows as (
    select
        workflow_run_pk,
        workflow_status_key,
        workflow_id,
        workflow_name,
        workflow_status,
        mode,
        retry_of,
        execution_id,
        retry_success_id,
        date_started,
        time_started,
        date_finished,
        time_finished,
        date_inserted,
        time_of_insertion
    from {{ ref('stg_n8n_workflow_runs') }}
),

n8n_alerts as (
    select
        alert_pk,
        alert_type_key,
        alert_severity_key,
        alert_type,
        alert_category,
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
        execution_id as workflow_run_fk,
        failed_node
    from {{ ref('stg_n8n_alerts') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['nw.workflow_run_pk', 'na.alert_pk']) }} as n8n_run_skey,

-- Workflow Fields
    nw.workflow_run_pk,
    nw.workflow_status_key,
    nw.workflow_id,
    nw.workflow_name,
    nw.workflow_status,
    nw.mode,
    nw.retry_of,
    nw.execution_id,
    nw.retry_success_id,
    nw.date_started,
    nw.time_started,
    nw.date_finished,
    nw.time_finished,
    nw.date_inserted,
    nw.time_of_insertion,

-- Alert Fields
    na.alert_pk,
    na.alert_type_key,
    na.alert_severity_key,
    na.alert_type,
    na.alert_category,
    na.severity,
    na.alert_source,
    na.title,
    na.message,
    na.triggered_at,
    na.triggered_at_local,
    na.date_triggered,
    na.time_triggered,
    na.resolved_at,
    na.is_active,
    na.inserted_at,
    na.workflow_run_fk,
    na.failed_node

from n8n_workflows nw
left join n8n_alerts na
    on nw.workflow_run_pk = na.workflow_run_fk
