{{ config( 
        materialized='view',
        schema='staging'
    )   }}


SELECT
    id,
    hostname,
    sensor_type,
    sensor_name,
    sensor_id,
    value,
    value_min,
    value_max,
    unit,
    trim(hardware_name) as hardware_name,
    trim(hardware_type) as hardware_type,
    recorded_at,
    inserted_at
from {{ source('home_metrics_raw', 'raw_hardware_sensors')}}