{{ config(
    materialized = 'table',
    schema = 'marts'
) }}

with accounts as (
    select 
        account_pk,
        account_key,
        account_name_friendly,
        teller_account_id,
        account_holder,
        account_holder_key,
        account_type,
        account_subtype,
        last_four,
        account_status,
        institution_name,
        institution_id,
        enrollment_id
from {{ ref('intmdt_teller_transactions') }} 
)

select * from accounts