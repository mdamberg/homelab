/*

    Summary: Normalizes and pulls in a 1:1 fashion from the raw
             balances table.
    Purpose: Provides a balance of all acounts for each bank run
             that is completed. Note that available balance will
             be null if it is the same as the balance field. 
      Grain: 1 row per account, per bank run

*/


select
    {{ dbt_utils.generate_surrogate_key(['account_id', 'balance_date']) }} as balance_skey,
    balance_date,
    account_id,
    account_name,
    conn_id,
    institution_name,
    currency,
    balance,
    available_balance,
    payload ->> 'holdings' as holdings
from {{ source('home_metrics_raw','raw_simplefin_balances') }}
