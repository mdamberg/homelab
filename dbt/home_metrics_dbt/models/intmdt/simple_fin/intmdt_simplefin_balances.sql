/*

    Summary: Enriches balances data with normalized account names.
    Purpose: Provides a snapshot of account balances for
             each bank run using friendly names. 
      Grain: 1 row per account per bank run

*/


with account_names_normalized as (
    select
        balance_skey,
        balance_date,
        balance_datetime,
        account_id,
        fa.account_name_clean as account_name,
        conn_id,
        institution_name,
        currency,
        balance,
        available_balance,
        holdings
    from {{ ref('stg_simplefin_balances') }} sb
    join {{ ref('map_financial_accounts') }} fa
        on sb.account_name = fa.account_name
)
select * from account_names_normalized
