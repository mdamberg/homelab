/*

    Snapshot model for media entities within the media folder.
    Shows historical snapshots of the media library (ie when
    something was added and when it was removed.)
    
    Grain: 1 row per media entity per add/delete event

*/

{% snapshot media_library_snapshot %}

    {{
        config(
                target_schema='snapshots'
                unique_key: 'id'
                strategy: 'check'
                check_cols: ['media_type', 'library_name', 'genre', 'year', 'overview', 'ratings', 'metadata']
                hard_deletes: 'invalidate'
                dbt_valid_to_current: "'9999-12-31'::date"
        )
    }}

select 
    *
from {{ source('home_metrics_raw', 'raw_media_library') }}

{% end snapshot %}