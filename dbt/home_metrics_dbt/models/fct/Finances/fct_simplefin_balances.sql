/*

    Summary: Daily balance for every SimpleFIN account, built on the date spine.
    Purpose: Gives charts a continuous daily series per account. Days with no
             new bank balance carry the last known balance forward
             (is_carried_forward = true).
      Grain: 1 row per account per day, from the account's first balance date
             through today

*/

with daily_spine as (
    select
        month_start_date,
        date_day
    from {{ ref('dim_date') }}
    -- current_date is UTC in Postgres, which rolls to tomorrow at 7 PM Chicago
    where date_day <= (now() at time zone 'America/Chicago')::date
),

intmdt_balances as (
    select
        *,
        row_number() over(partition by balance_date, account_id order by account_name) as account_day_rank
    from {{ ref('intmdt_simplefin_balances') }}
),

intmdt_balances_deduped as (
    select
        *
    from intmdt_balances
    where account_day_rank = 1
),

-- One row per account; the spine is crossed with this, not with balance rows
accounts as (
    select
        account_id,
        account_name,
        account_owner,
        conn_id,
        institution_name,
        currency,
        min(balance_date) as first_balance_date
    from intmdt_balances_deduped
    group by
        account_id,
        account_name,
        account_owner,
        conn_id,
        institution_name,
        currency
),

-- Each account starts on its own first balance date so a newly linked account
-- does not get empty history before it existed
account_daily as (
    select
        ds.month_start_date,
        ds.date_day,
        acct.account_id,
        acct.account_name,
        acct.account_owner,
        acct.conn_id,
        acct.institution_name,
        acct.currency
    from daily_spine ds
    join accounts acct
        on ds.date_day >= acct.first_balance_date
),

-- balance_group increments only on days with a real balance, so each gap day
-- shares a group with the last real balance before it
account_daily_balances as (
    select
        ad.month_start_date,
        ad.date_day,
        ad.account_owner,
        ad.account_id,
        ad.account_name,
        ad.conn_id,
        ad.institution_name,
        ad.currency,
        ib.balance_skey,
        ib.balance_date,
        ib.balance_datetime,
        ib.balance,
        ib.available_balance,
        ib.holdings,
        count(ib.balance_skey) over (partition by ad.account_id order by ad.date_day) as balance_group
    from account_daily ad
    left join intmdt_balances_deduped ib
        on ad.date_day = ib.balance_date
        and ad.account_id = ib.account_id
),

-- Carries the last known balance forward. The bank only updates once a day at
-- most, and the extractor skips a balance whose bank timestamp has not changed.
-- lag() would fill only one missing day because Postgres has no IGNORE NULLS.
daily_balances as (
    select
        -- Primary and Surrogate Keys
        {{ dbt_utils.generate_surrogate_key(['date_day', 'account_id']) }} as daily_balance_skey,
        first_value(balance_skey) over balance_window as balance_skey,

        -- Dates
        month_start_date,
        date_day,
        first_value(balance_date) over balance_window as balance_date,
        first_value(balance_datetime) over balance_window as balance_datetime,

        -- Account
        account_owner,
        account_id,
        account_name,
        conn_id,
        institution_name,
        currency,

        -- Balances
        first_value(balance) over balance_window as balance,
        first_value(available_balance) over balance_window as available_balance,
        first_value(holdings) over balance_window as holdings,

        -- Flags
        balance_skey is null as is_carried_forward
    from account_daily_balances
    window balance_window as (partition by account_id, balance_group order by date_day)
)

select 
*,
row_number() over(partition by account_id order by date_day desc) as is_current_balance 
from daily_balances
