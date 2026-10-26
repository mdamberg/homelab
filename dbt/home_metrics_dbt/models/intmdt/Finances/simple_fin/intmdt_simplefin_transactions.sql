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
        st.transaction_skey,
        st.date_key,
        st.account_id,
        st.transaction_id,
        st.transaction_date, 
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
    where payee not in ('Interest Payment', 'Wells Fargo Rewards', 'Online Transfer')   -- excludes CC payments already reflected in expenses
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
        case
            when lower(an.payee) = lower(tm.payee) then 'payee'
            when tm.description_pattern is not null then 'description'
        end as match_type,
        -- exact payee match wins; otherwise longer description_pattern = more specific match
        row_number() over(partition by an.transaction_skey
            order by
                case when lower(an.payee) = lower(tm.payee) then 1 else 2 end,
                length(tm.description_pattern) desc
        ) as match_rank
    from account_names an
    left join category_map tm
        on lower(an.payee) = lower(tm.payee)
        or an.transaction_description ilike '%' || tm.description_pattern || '%'
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