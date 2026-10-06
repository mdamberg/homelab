



snapshots:
  - name: media_library_snapshot
    relation: source('home_metrics_raw', 'raw_media_library')
    config:
      schema: snapshots
      database: home_metrics
      unique_key: id
      strategy: check
      # these should be the ones that can change while an item remains the same entity
      check_cols: [media_type, library_name, genre, year, overview, ratings, metadata]
      hard_deletes: invalidate
      dbt_valid_to_current: "'9999-12-31'::date"


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