select
    workflow_run_pk,
    workflow_name,
    workflow_id,
    execution_id,
    mode,
    
    workflow_status,
    workflow_status_key,

    daily_run_num,

    date_started as run_date_start,
    time_started as run_time_start,
    date_finished as run_date_end,
    time_finished as run_time_end,

    date_inserted,
    time_of_insertion,

    is_successful_run,
    is_failed_run,
    is_no_data_alert,
    is_node_error_alert

from {{ ref('fct_n8n_workflow_runs') }}