/*

    Summary: 
    Purpose: 
      Grain: 

*/

select
    transaction_skey,
    transaction_date,
    transaction_id,
    description_pattern,
    account_name,
    account_owner,
    account_id,
    account_last_four,
    institution_name,
    payee,
    amount,
    transaction_type,
    merchant_category_code,
    custom_category,
    custom_subcategory,
    is_recurring,
    billing_cycle
from {{ ref('intmdt_simplefin_transactions') }}

    
