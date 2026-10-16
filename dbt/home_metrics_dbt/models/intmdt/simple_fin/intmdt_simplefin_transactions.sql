/*

    Summary: Transforms financial data and adds relevant fields.
    Purpose: Brings staging data and maps it to normalized 
             transaction acounts as well as maps raw transaction
             descriptions to normalized ones. 
      Grain: 1 row per transaction per account

*/

with stg_transactions as (
    select * from {{ ref('stg_simplefin_transactions') }}
),
account_names as (
    select
        st.transaction_pk,
        st.date_key,
        st.account_id,
        st.transaction_id,
        st.transaction_description,
        st.amount,
        st.institution_name,
        mf.account_owner,
        mf.account_name_clean as account_name,
        substring(st.account_name from '\((\d+)\)$') as account_last_four,
        payee,
        merchant_category_code
    from stg_transactions st
    join {{ ref('map_financial_accounts') }} mf
        on mf.account_name = st.account_name 
),
category_map as (
    select * from {{ ref('map_transactions') }}
),
transactions_mapped as (
    select 
        an.*,
        description_pattern,
        custom_category,
        custom_subcategory,
        coalesce(tm.vendor_normalized, an.payee) as vendor,
        is_recurring,
        billing_cycle,
        -- longer description_pattern = more specific match; pick rank 1 when multiple patterns match 
        row_number() over(partition by an.transaction_pk order by length(tm.description_pattern) desc) as match_rank
    from account_names an
    left join category_map tm
        on an.transaction_description ilike '%' || tm.description_pattern || '%'
),

best_match as (
    select * from transactions_mapped
    where match_rank = 1    -- take highest ranking match
),
transactions_classifications as (
    select 
        *,
        case when amount > 0 then 'Income' else 'Expense' end as transaction_type
    from best_match
)

select 
    *
from transactions_classifications