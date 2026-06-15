  {{ config(
      materialized = 'table',
      schema = 'marts'
  ) }}

  with vendors as (
      select 
          vendor_key,
          vendor as vendor_name,
          bool_or(is_recurring) as is_recurring_vendor
      from {{ ref('intmdt_teller_transactions') }}
      where vendor_key is not null
      group by 1, 2
  )

  select * from vendors