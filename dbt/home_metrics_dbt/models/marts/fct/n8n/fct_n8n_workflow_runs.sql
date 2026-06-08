{{ config( 
    materialized= 'table',
    schema = 'marts'
) }}

-- ================================================== --
-- Grain: 1 row per workflow run
-- ================================================== --

with n8n_runs as (
    select
        workflow_run_pk,
        max(workflow_status_key) as workflow_status_key,
        max(workflow_id) as workflow_id,
        max(workflow_name) as workflow_name,
        max(workflow_status) as workflow_status,
        max(date_started) as date_started,
        max(time_started) as time_started,
        max(date_finished) as date_finished,
        max(time_finished) as time_finished,
        max(date_inserted) as date_inserted,
        max(time_of_insertion) as time_of_insertion,
        max(mode) as mode,
        max(execution_id) as execution_id,
        max(case when alert_type is null and workflow_status = 'success' then 1 else 0 end) as is_successful_run,
        max(case when workflow_status = 'error' then 1 else 0 end) as is_failed_run,
        max(case when alert_type = 'no_data' then 1 else 0 end) as is_no_data_alert,
        max(case when alert_type = 'node_error' then 1 else 0 end) as is_node_error_alert

    from {{ ref('intmdt_n8n_runs') }}
    group by workflow_run_pk
)

select * from n8n_runs