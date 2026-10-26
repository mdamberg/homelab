/*

    Summary:
    Purpose:
      Grain:

*/


with staging_balances as (
    select
    balance_skey,
    balance_date,
    balance_datetime,
    account_id,
    account_name,
    conn_id,
    institution_name,
    currency,
    balance,
    available_balance,
    holdings
    from {{ ref('stg_simplefin_balances') }}
    -- join to account mapping table
),
