/*

    Model pulling raw data on metrics related to the m
    media stack and its contents.

    Grain: 1 row per ....?


    This is busted and needs to be fixed: the n8n run is re-writing in the same
    rows over and over resulting in dupe rows. I think there should be 2-4 rows 
    (1 for each library_name).

*/



with raw_media_library_metrics as (

    select
        id,
        source,
        media_type,
        library_name,
        item_count,
        coalesce(total_size_bytes,0) as total_size_bytes,
        recorded_at::date as date_recorded,
        recorded_at as recorded_at_ts,
        inserted_at::date as date_inserted,
        inserted_at as inserted_at_ts,
        metadata
    from
        {{ source('home_metrics_raw', 'raw_media_library_metrics') }}

),

dedupe as (
    select
        *,
        row_number() over(partition by source, media_type, library_name, date_recorded order by date_inserted desc) as rn
    from raw_media_library_metrics
)

select
-- media source identifier
    {{ dbt_utils.generate_surrogate_key(['source']) }} as media_source_key,
-- Library identifier
    {{ dbt_utils.generate_surrogate_key(['source' ,'library_name']) }} as library_key,
-- Snapshot identifier
    {{ dbt_utils.generate_surrogate_key(['source', 'library_name', 'date_recorded']) }} as library_snapshot_key,
    source,
    media_type,
    library_name,
    item_count,
    cast(metadata ->> 'is_active' as numeric) as is_active,
    total_size_bytes,
    date_recorded,
    cast({{ to_local_time('recorded_at_ts') }} as timestamp) as recorded_at_ts,
    date_inserted,
    cast({{ to_local_time('inserted_at_ts') }} as timestamp) as inserted_at_ts,
    metadata
from dedupe
where rn = 1