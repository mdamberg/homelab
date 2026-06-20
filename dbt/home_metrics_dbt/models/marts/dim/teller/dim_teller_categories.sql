{{ config(
    materialized = 'table',
    schema = 'marts',
    enabled = false
) }}

select
    category_key,
    category,
    subcategory,
    teller_category,
from {{ ref('intmdt_teller_transactions') }}