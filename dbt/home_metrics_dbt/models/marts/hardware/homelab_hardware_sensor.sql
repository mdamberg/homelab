/*
    Mart level wrapper for hardware sensors that is 
    exposed to LightDash
*/

select  
    {{ dbt_utils.generate_surrogate_key(['recorded_datetime', 'sensor_id']) }} as hardware_skey,
    *,
    case when date_trunc(month, recorded_date) = date_trunc(month, current_date) then 1 else 0 end as is_current_month,
    case when sensor_name ilike '%temp%' then 1 else 0 end as is_temp_sensor
from  {{ ref('fct_hardware_sensor') }}