/*
    Mart level wrapper for hardware sensors that is
    exposed to LightDash
*/

{{
    config(
        materialized='incremental',
        unique_key='hardware_skey',
        incremental_strategy='merge'
    )
}}

select
    {{ dbt_utils.generate_surrogate_key(['recorded_datetime', 'sensor_id']) }} as hardware_skey,
    *,
    case when sensor_name ilike '%temp%' then 1 else 0 end as is_temp_sensor
from {{ ref('fct_hardware_sensor') }}

{% if is_incremental() %}
    -- only pull rows at/after the latest timestamp already loaded;
    -- >= re-merges the boundary rows so none are missed (merge dedups on hardware_skey)
    where recorded_datetime >= coalesce((select max(recorded_datetime) from {{ this }}), '1900-01-01')
{% endif %}
