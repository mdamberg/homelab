{{ config(
    materialized='table',
    schema='intmdt'
) }}

with balances as (
    select * from {{ ref('stg_teller_balances') }}
),

accounts as (
    select * from {{ ref('intmdt_teller_accounts') }}
)

select
    b.balance_pk,
    b.teller_account_id,
    b.account_key,
    b.date_key,

    -- Account attributes
    a.account_holder,
    a.account_holder_key,
    a.account_name_friendly,
    a.account_type,
    a.account_subtype,
    a.last_four,
    a.institution_name,

    -- Balance fields
    b.ledger_balance,
    b.available_balance,

    -- Timestamps
    b.recorded_at,
    b.inserted_at
from balances b
left join accounts a 
    on b.teller_account_id = a.teller_account_id
