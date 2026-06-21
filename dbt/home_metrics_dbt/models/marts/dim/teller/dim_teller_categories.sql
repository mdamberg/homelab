{{ config(
    materialized = 'table',
    schema = 'marts',
) }}

select
    distinct category_key,
    category,
    subcategory
from {{ ref('intmdt_teller_transactions') }}