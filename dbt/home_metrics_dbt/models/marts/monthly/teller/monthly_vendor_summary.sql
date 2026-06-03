{{ config(
    materialized='table',
    schema='marts'
) }}

with date_spine as (
    select
        month_start_date,
        month_end_date,
        month_number
    from {{ ref('dim_date') }}
    where is_bom_flag = 1
    and month_start_date <= current_date
),

transactions as (
    select
        ds.month_start_date,
        ds.month_end_date,
        ft.account_key,
        ft.account_holder_key,
        ft.account_name_friendly,
        ft.account_holder,
        ft.vendor_key,
        ft.vendor,
        ft.teller_vendor_category,
        ft.vendor_transaction_num,
        ft.category,
        ft.subcategory,
        ft.transaction_flow,
        ft.transaction_amount_normalized
    from date_spine ds
    left join {{ ref('fct_transactions') }} ft
        on ft.transaction_date between ds.month_start_date and ds.month_end_date
        and ft.account_key is not null
        and ft.transaction_status = 'posted'
)

select
    {{ dbt_utils.generate_surrogate_key(['month_start_date', 'month_end_date', 'account_key', 'account_holder_key', 'vendor_key', 'vendor', 'category', 'subcategory']) }} as monthly_vendor_skey,
    month_start_date,
    month_end_date,
    account_key,
    account_holder_key,
    account_name_friendly,
    account_holder,
    vendor_key,
    vendor,
    max(teller_vendor_category) as teller_vendor_category,
    category,
    subcategory,

    sum(case when transaction_flow = 'expense' then transaction_amount_normalized else 0 end) as total_expenses,
    sum(case when transaction_flow = 'income' then transaction_amount_normalized else 0 end) as total_income,
    sum(transaction_amount_normalized) as net_income
from transactions
group by month_start_date, month_end_date, account_key, account_holder_key, account_name_friendly, account_holder,
    vendor_key, vendor, category, subcategory
