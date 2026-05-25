{{ config(
    materialized='table',
    schema='intmdt'
) }}

with transactions_data as (
    select * from {{ ref('stg_teller_transactions') }}
),

accounts_data as (
    select * from {{ ref('stg_teller_accounts') }}
),

category_map as (
    select * from {{ ref('map_transactions') }}
),

transactions_with_accounts as (
    select
        t.*,
        a.account_pk,
        a.account_holder,
        a.account_name_friendly,
        a.last_four,
        a.account_type,
        a.account_status,
        a.account_subtype,
        a.institution_id,
        a.institution_name,
        a.enrollment_id
    from transactions_data t
    left join accounts_data a
        on t.teller_account_id = a.teller_account_id
),

-- map accounts to custom categories created in seed file (map_transactions.csv)
mapped as (
    select
        t.*,
        m.custom_category,
        m.custom_subcategory,
        m.vendor_normalized,
        m.is_recurring,

        -- assign a rank to each transaction pk based on length and sort desc (longer description patterns are more specific); 
        -- this is done because one transaction can match multiple description patterns
        -- The window fx ranks the multiple matches per transaction, and orders the longest matchnig patterns first
        -- A longer patternsn is mosre specific and will produce a better match 
        row_number() over (partition by t.transaction_pk order by length(m.description_pattern) desc) as match_rank
    from transactions_with_accounts t
    left join category_map m
        on t.transaction_description ilike '%' || m.description_pattern || '%'
        -- joins the tx description on any mapping row where the tx description pattern exists
        -- then uses the window fx to pick the longest match
),

best_match as (
    select * from mapped
    where match_rank = 1 or match_rank is null
),

enriched as (
    select
        -- Primary and Surrogate Keys
        transaction_pk,
        {{ dbt_utils.generate_surrogate_key(['transaction_pk']) }} as transaction_skey,

        -- Account Keys
        account_pk,
        account_key,

        -- Dimensional Keys (for Grouping)
        {{ dbt_utils.generate_surrogate_key(['account_holder']) }} as account_holder_key,
        {{ dbt_utils.generate_surrogate_key(['transaction_type']) }} as transaction_type_key,
        {{ dbt_utils.generate_surrogate_key(['coalesce(custom_category, teller_category)']) }} as category_key,
        {{ dbt_utils.generate_surrogate_key(['coalesce(vendor_normalized, teller_vendor_name, transaction_description)']) }} as vendor_key,

        -- Date Key
        date_key,

        -- Account Attributes
        account_holder,
        account_name_friendly,
        last_four,
        account_type,
        account_subtype,
        account_status,
        institution_id,
        institution_name,
        enrollment_id,

        -- Transaction Identifiers
        teller_transaction_id,
        teller_account_id,

        -- Transaction Attributes
        transaction_date,
        transaction_description,
        transaction_amount,
        case
            when account_type = 'credit' then transaction_amount * -1
            else transaction_amount
        end as transaction_amount_normalized,

        transaction_status,
        transaction_type,

        -- Category fields (mapped with fallback to original)
        coalesce(custom_category, teller_category) as category,
        custom_subcategory as subcategory,
        teller_category,

        -- Vendor fields (mapped with fallback)
        coalesce(vendor_normalized, teller_vendor_name, transaction_description) as vendor,
        teller_vendor_name,
        teller_vendor_category,

        -- Flags
        coalesce(is_recurring, false) as is_recurring,
        case when custom_category is not null then true else false end as is_mapped,

        running_balance,

        -- Timestamps
        inserted_at as transaction_inserted_at,
        updated_at as transaction_updated_at
    from best_match
)

select 
    *,
    case
        when transaction_amount_normalized < 0 then 'expense'    -- expense
        when transaction_amount_normalized > 0 then 'income'   -- income
        else 'zero'
            end as transaction_flow
from enriched
