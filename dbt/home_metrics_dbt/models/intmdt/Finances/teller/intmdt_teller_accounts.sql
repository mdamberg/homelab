{{ config(
    materialized='table',
    schema='intmdt'
) }}

with source as (
    select * from {{ ref('stg_teller_accounts') }}
    where account_status = 'open'
),

mapped as (
    select
        *,
        case
            when last_four in ('7868', '8119', '5766') then 'Matt'
            when last_four in ('0999', '0325', '4113', '2410') then 'Jessica'
            else 'Unknown'
        end as account_holder,
        case
            when last_four = '7868' then 'Matt Checking'
            when last_four = '0999' then 'Jessica Savings'
            when last_four = '8119' then 'Matt Savings'
            when last_four = '5766' then 'Matt WF Credit Card'
            when last_four = '0325' then 'Jessica Checking'
            when last_four = '4113' then 'Jessica CapitalOne Credit Card'
            when last_four = '2410' then 'Jessica WF Credit Card'
            else 'Unknown Account'
        end as account_name_friendly
    from source
)

select
    account_pk,
    teller_account_id,
    account_key,
    account_holder,
    {{ dbt_utils.generate_surrogate_key(['account_holder']) }} as account_holder_key,
    account_name_friendly,
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
from mapped
