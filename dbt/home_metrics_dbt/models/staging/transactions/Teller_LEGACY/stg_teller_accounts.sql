{{ config(
    materialized='view',
    schema='staging'
) }}

select
    id as account_pk,
    teller_account_id,
    {{ dbt_utils.generate_surrogate_key(['teller_account_id']) }} as account_key,
    enrollment_id,
    institution_name,
    institution_id,
    account_name,
    account_type,
    account_subtype,
    account_status,
    currency,
    last_four,
    inserted_at,
    updated_at
from {{ source('home_metrics_raw', 'raw_teller_accounts') }}
