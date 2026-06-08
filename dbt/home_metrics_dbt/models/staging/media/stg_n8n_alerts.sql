{{ config(
    materialized='view',
    schema='staging'
) }}

with n8n_alerts as (
    select
        id,
        -- rename and categorize alert_type here so surrogate keys hash the correct values
        case when alert_type = 'workflow_failure' then 'node_error' else alert_type end as alert_type,
        case
            when alert_type = 'workflow_failure' then 'execution'
            when alert_type = 'no_data' then 'data_quality'
            else 'unknown'
        end as alert_category,
        severity,
        source,
        title,
        message,
        triggered_at,
        resolved_at,
        inserted_at,
        metadata
    from {{ source('home_metrics_raw', 'raw_n8n_alerts') }}
    where source != 'Example Workflow'
)

select
    -- Primary key
    id as alert_pk,

    -- Dimension keys
    {{ dbt_utils.generate_surrogate_key(['source', 'alert_type']) }} as alert_type_key,
    {{ dbt_utils.generate_surrogate_key(['source', 'alert_type', 'severity']) }} as alert_severity_key,

    alert_type,
    alert_category,
    severity,
    source as alert_source,
    title,
    message,
    triggered_at,
    {{ to_local_time('triggered_at') }} as triggered_at_local,
    cast({{ to_local_time('triggered_at') }} as date) as date_triggered,
    cast({{ to_local_time('triggered_at') }} as time) as time_triggered,
    resolved_at,
    case when resolved_at is null then true else false end as is_active,
    inserted_at,

    -- node_error alert fields
    (metadata->>'execution_id')::bigint as execution_id,
    metadata->>'workflow_id' as workflow_id,
    metadata->>'last_node_executed' as failed_node,

    -- no_data alert fields
    metadata->>'table' as monitored_table,
    (metadata->>'threshold_minutes')::integer as threshold_minutes,

    metadata
from n8n_alerts
