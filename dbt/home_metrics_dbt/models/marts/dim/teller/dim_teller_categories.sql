{{ config(
    materialized = 'table',
    schema = 'marts',
    enabled = false
) }}


select
    select
    account_pk,
    account_key,
    account_holder,
    account_holder_key,
    account_name_friendly,
    teller_account_id,
    account_type,
    account_subtype,
    last_four,
    account_status,
    institution_name,
    institution_id,
    enrollment_id