/*

    A model which shows only the media entities that
    currently exist in the media library. This then 
    feeds the snapshot media library model which allows
    missing (deleted) media to drop off from being 
    tracked.

    Grain: 1 row per currently existing media entity

*/

with media_persistence as (
    select
        {{ dbt_utils.generate_surrogate_key( ['source', 'title']) }} as media_key,
        
        source,
        media_type,
        library_name,
        title,
        genre,
        year,
        overview,
        ratings,
        recorded_at,
        inserted_at,
        metadata ->> 'bitrate' as bitrate,
        
        (to_timestamp((metadata ->> 'added_at')::bigint) at time zone 'UTC') as added_at_utc,
        {{ to_local_time("to_timestamp((metadata ->> 'added_at')::bigint)") }} as added_at_ts,
        to_timestamp((metadata ->> 'added_at')::bigint)::date as date_added,
        
        metadata ->> 'studio' as studio,
        metadata ->> 'runtime' as runtime,
        metadata ->> 'has_file' as has_file,
        metadata ->> 'file_size' as file_size,
        metadata ->> 'play_count' as play_count,
        metadata ->> 'rating_key' as rating_key,
        metadata ->> 'last_played' as last_played,
        metadata ->> 'episode_file_count' as episode_file_count,
        metadata ->> 'monitored' as monitored,
        metadata ->> 'size_on_disk' as size_on_disk,
        metadata ->> 'certification' as certification_rating
    from {{ source('home_metrics_raw', 'raw_media_library') }}
),
most_recent_recorded as (
    select
        source,
        max(recorded_at) as recorded_at
    from media_persistence
    group by source
) 
select 
    mp.media_key,
    mp.source,
    mp.library_name,
    mp.title,
    mp.media_type,
    mp.genre,
    mp.year,
    mp.overview,
    mp.ratings,
    mp.recorded_at,
    mp.inserted_at,
    mp.bitrate,
    mp.added_at_ts,
    mp.added_at_utc,
    mp.date_added,
    mp.studio,
    mp.runtime,
    mp.has_file,
    mp.file_size,
    mp.play_count,
    mp.rating_key,
    mp.last_played,
    mp.episode_file_count,
    mp.monitored
from media_persistence mp
join most_recent_recorded mr
    on mp.source = mr.source
    and mp.recorded_at = mr.recorded_at
where mp.source = 'plex'
    or mp.has_file = 'true'
    or mp.episode_file_count::int > 0