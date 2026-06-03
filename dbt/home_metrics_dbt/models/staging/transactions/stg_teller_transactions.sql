{{ config(
    materialized='view',
    schema='staging'
) }}

select
    {{ dbt_utils.generate_surrogate_key(['id']) }} as transaction_pk,
    teller_transaction_id,
    teller_account_id,
    {{ dbt_utils.generate_surrogate_key(['teller_account_id']) }} as account_key,
    to_char(transaction_date, 'YYYYMMDD')::integer as date_key,
    transaction_date,
    description as transaction_description,
    amount as transaction_amount,
    status as transaction_status,
    type as transaction_type,
    category as teller_category,
    merchant_name as teller_vendor_name,
    merchant_category as teller_vendor_category,
    running_balance,
    inserted_at,
    updated_at
from {{ source('home_metrics_raw', 'raw_teller_transactions') }}