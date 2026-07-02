# Intermediate Table Grain Definitions

This file documents the granularity for each intermediate model. Intermediate models join and transform staging models before loading into marts.

---

## Financial

1. **intmdt_transactions**
   - Grain: 1 row per transaction
   - Primary key: `transaction_pk`
   - Surrogate key: `transaction_skey`
   - Joins: `stg_teller_transactions` + `stg_teller_accounts` (on teller_account_id)
   - Purpose: Enriches transactions with account details and adds dimension keys for analytics
