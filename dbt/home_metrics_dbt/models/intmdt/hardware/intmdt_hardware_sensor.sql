

-- 1 row per recorded at time x sensor type x hardware type
with sensor_rollup as (
	select
		recorded_at,	
		inserted_at,
		sensor_type,
		hardware_name,
		hardware_type,
		unit,
		round(avg(value_max), 2) as avg_max_value,
		round(avg(value_min), 2) as avg_min_value,
		round(avg(value),2) as avg_value
	from {{ ref('stg_hardware_sensor') }}
	group by 1, 2, 3, 4, 5, 6
)
select
	{{ dbt_utils.generate_surrogate_key(['recorded_at', 'sensor_type', 'hardware_name'])  }} as hardware_skey,
    *
from sensor_rollup
