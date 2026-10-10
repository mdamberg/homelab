/*

    Snapshot model for media entities within the media folder.
    Shows historical snapshots of the media library (ie when
    something was added and when it was removed.)
    
    Grain: 1 row per media entity per add/delete event

*/

{% snapshot media_library_snapshot %}

    {{
        config(
                target_schema='snapshots',
                unique_key='media_key',
                strategy='timestamp',
                updated_at='added_at_utc',
                hard_deletes='invalidate'
        )
    }}

select
    media_key,
    source,
    media_type,
    library_name,
    title,
    genre,
    year,
    overview,
    ratings,
    inserted_at,
    added_at_utc,
    added_at_ts,
    date_added,
    studio,
    runtime,
    bitrate,
    rating_key
from {{ ref('stg_media_library_present') }}

{% endsnapshot %}