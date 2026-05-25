{{ config(
    materialized='view',
    schema='staging'
) }}

select
    -- skey: unique per row
    {{ dbt_utils.generate_surrogate_key(['id']) }} as transaction_pk,
    teller_transaction_id,
    teller_account_id,
    -- dimension key: unique to each account, but not unique across accounts
    {{ dbt_utils.generate_surrogate_key(['teller_account_id']) }} as account_key,
    to_char(transaction_date, 'YYYYMMDD')::integer as date_key,
    transaction_date,
    description as transaction_description,
    amount as transaction_amount,
    status as transaction_status,
    case
        when
            description ilike '%payroll%' or
            description ilike '%Fairview Health PR PAYMENT%'
            or description ilike '%ANDREW RESIDENCE DIRECT DEP%'then 'income'
                else type
                    end as transaction_type,
    category as teller_category,
    merchant_name as teller_vendor_name,
    merchant_category as teller_vendor_category,
    running_balance,
    inserted_at,
    updated_at
from {{ source('home_metrics_raw', 'raw_teller_transactions') }}
where 
    (description not ilike '%ONLINE PAYMENT THANK YOU%' and 
    description not ilike '%ONLINE TRANSFER%' and
    description not ilike '%RECURRING TRANSFER%' and 
    description not ilike '%ZELLE%' and 
    description not ilike '%WF Credit Card %' and
    description not ilike '%OVERDRAFT PROTECTION%' and
    description not ilike '%CHASE CREDIT CRD EPAY %') 
and (
    description not in ('INTEREST PAYMENT', 'WELLS FARGO REWARDS')
)