with date_spine as (
	select
		month_start_date,
		month_end_date
	from {{ ref('dim_date') }}
	where is_bom_flag = 1
	and month_start_date <= current_date
),
transaction_months as (
	select
		ds.month_start_date,
		ds.month_end_date,
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
    from date_spine ds 
    left join {{ ref('fct_simplefin_transactions') }}   ft
    	on ft.transaction_date <= ds.month_end_date 
    	and ft.transaction_date >= ds.month_start_date
    where transaction_skey is not null
)
select * from transaction_months
