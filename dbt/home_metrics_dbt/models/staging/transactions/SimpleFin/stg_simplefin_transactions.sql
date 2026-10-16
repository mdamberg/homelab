/*

   Overview: Staging model for raw financials from WellsFargo. 
    Purpose: Pulls in raw financial data via SimpleFin from WellsFargo.
             This model does light cleaning and name changes to allow 
             for additional model creation downstream and is a 1:1 
             representation of the raw source file.
      Grain: 1 row per posted transaction (account_id + transaction_id)

*/


select
    {{ dbt_utils.generate_surrogate_key(['account_id', 'transaction_id']) }} as transaction_pk,
    to_char(posted_at, 'YYYYMMDD')::integer as date_key,
    account_id,
    transaction_id,
    institution_name,
    account_name,
    posted_at::date as posted_at_date,
    transacted_at::date as transacted_at_date,
    amount,
    trim(description) as transaction_description,
    inserted_at as inserted_at_datetime,
    payload ->> 'mcc' as merchant_category_code,
    nullif(payload ->> 'memo', '') as memo
    payload ->> 'payee' as payee,
    payload ->> 'posted' as posted,
    payload ->> 'transacted_at' as transacted_at
from {{ source('home_metrics_raw', 'raw_simplefin_transactions') }}