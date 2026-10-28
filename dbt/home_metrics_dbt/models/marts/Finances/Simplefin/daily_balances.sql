/*

    Summary: Daily balances for all of Matt and Jess' accounts. 
    Purpose: Provides a daily, trendable and trackable view
             of account balances day by day. Balances that 
             have not changed from the previous day will carry
             forward and show the same balance as the previous
             day.
      Grain: 1 row per account per day. 

*/

select 
    daily_balance_skey,
    balance_skey,
    month_start_date,
    date_day,
    balance_date,
    balance_datetime,
    account_owner,
    account_id,
    account_name,
    conn_id,
    institution_name,
    currency,
    balance,
    available_balance,
    is_current_balance,
    holdings,
    is_carried_forward
from {{ ref('fct_simplefin_balances') }}