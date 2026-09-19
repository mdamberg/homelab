with sensor_data as (
	select
		recorded_at::date as recorded_date,
		recorded_at as recorded_datetime,
		hardware_type,
		hardware_name,
		sensor_name,
		sensor_id ,
		value as sensor_value,
		value_min as sensor_value_min,
		value_max as sensor_value_max,
        unit,
		inserted_at::date as inserted_date,
		inserted_at as inserted_at_dateime
	from {{ ref('stg_hardware_sensor') }} 
	where sensor_type not in ('fan', 'voltage')
)
select 
    * 
from sensor_data 
order by recorded_date, hardware_type, sensor_name