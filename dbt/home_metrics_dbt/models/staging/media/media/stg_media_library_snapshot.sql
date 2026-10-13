/*

    Model pulling off media_library_snapshot (SCD2 history of the
    media entities present in the library). The valid from and to
    columns are used downstream to build a true inventory of media
    entities (ie. whats in my library currently? whats been there
    in the past?)

    dbt_valid_from is the date the entity was added; dbt_valid_to is
    null while the entity is still present.

    Grain: 1 row per media entity per version.

*/
with media_library_snapshot as (
    select
        *
    from
        {{ ref('media_library_snapshot') }}
)
select
    dbt_scd_id,
    media_key,
    {{ dbt_utils.generate_surrogate_key(['source']) }} as media_source_key,
    {{ dbt_utils.generate_surrogate_key(['source', 'media_type']) }} as media_type_key,
    source,
    media_type,
    library_name,
    title,
    genre,
    cast(year as varchar(15)) as year,
    produced_by,
    certification_rating,
    has_file,
    runtime as run_time,
    date_added,
    added_at_utc,
    cast(added_at_ts as timestamp) as added_at_ts,
    inserted_at::date as date_inserted,
    cast({{ to_local_time('inserted_at') }} as timestamp) as inserted_at_ts,
    dbt_updated_at,
    dbt_valid_from,
    dbt_valid_to
from media_library_snapshot
