---
name: dbt-sql-standards
description: Write, review, or fix dbt .sql models in dbt/home_metrics_dbt so they follow the project's layer, naming, key, and SQL style conventions. Use when creating or editing any model under home_metrics_dbt/models, adding a new data source or staging/intmdt/mart model, or when asked to standardize, lint, or clean up existing dbt SQL. Pair with dbt-yaml-standards for the matching .yml file.
---

# dbt SQL Standards

Conventions for `dbt/home_metrics_dbt`. Data flows `raw` (written by n8n) -> `staging` -> `intmdt` -> `marts`. Match the neighbors in the same domain folder before inventing anything.

## Layers

| Layer | Folder | Prefix | Materialized | `schema=` |
|---|---|---|---|---|
| staging | `models/staging/<domain>/` | `stg_` | view | `staging` |
| intermediate | `models/intmdt/<domain>/` | `intmdt_` | table | `intmdt` |
| dimension | `models/marts/dim/<domain>/` | `dim_` | table | `marts` |
| fact | `models/marts/fct/` | `fct_` | table | `marts` |
| monthly rollup | `models/marts/monthly/<domain>/` | `monthly_` | table | `marts` |

- One model per file; file name = model name. Every `.sql` has a same-named `.yml` beside it (see `dbt-yaml-standards`).
- Raw tables are only read through `{{ source('home_metrics_raw', 'raw_x') }}`, and only in staging. Everything else uses `{{ ref() }}`.

## File header

Every model starts with a `config` block, with `materialized` and `schema` matching the table above:

```sql
{{ config(
    materialized='table',
    schema='marts'
) }}
```

## Structure by layer

- **staging**: one select from the source. Rename, cast, derive keys and flags, normalize values. No joins and no aggregation. De-duplicating raw rows with a `row_number()` CTE filtered to `rn = 1` is fine (see `stg_hardware_sensors_metrics_long`).
- **intmdt**: where joins and business logic live. Import CTEs (`select * from {{ ref() }}`), then one CTE per step, then an `enriched`/final CTE with an explicit column list.
- **dim / fct / monthly**: an import or select CTE with an explicit column list, minimal logic. Aggregation goes in `monthly_`, and only there.
- The last line of every model is `select * from <final_cte>`.

## Style rules

- Lowercase keywords, 4-space indent, commas at end of line.
- **No subqueries.** Use CTEs. Window functions are fine.
- `select *` is allowed only inside import CTEs. A final CTE lists its columns explicitly.
- Group columns under short section comments (`-- Primary and Surrogate Keys`, `-- Dimensional Keys`, `-- Flags`, `-- Timestamps`). Comment only non-obvious logic (why, not what).
- Descriptive table aliases in joins, not single letters when a name reads better.
- Raw timestamps are UTC. Convert with `{{ to_local_time('col') }}` (macro in `macros/convert_timezone.sql`), cast to `timestamp` if needed.
- Booleans and flags: `is_<thing>` or `is_<thing>_flag`, matching the domain's existing choice.

## Keys

Full rules in `home_metrics_dbt/dbt_resources/key_design_cheatsheet.md`. Summary:

| Suffix | Meaning | Unique |
|---|---|---|
| `_pk` | raw table id, passed through | yes |
| `_skey` | `dbt_utils.generate_surrogate_key` over columns that make a row unique | yes |
| `_key` | hash of dimension attributes, shared by many rows (joins and grouping) | no |

- Surrogate key inputs must be real column names, not aliases defined later in the same select.
- `date_key` is an integer `YYYYMMDD`.

## Workflow: new model

1. Read two neighbors in the same domain and copy their shape.
2. Write the model to the layer rules above.
3. Create the `.yml` (use `dbt-yaml-standards`).
4. Add the model to the layer's `*_table_grain.md` (`stg_`, `intmdt_`, `marts_`) with its grain, primary key, and source.
5. Verify: `cd dbt/home_metrics_dbt && dbt run --select <model>` then `dbt test --select <model>`. If dbt or the database is not reachable (for example in a cloud session), say so and verify by reading the compiled logic instead of claiming it ran.

## Workflow: review or fix existing models

1. List deviations first, file by file, before editing anything.
2. Fix style and structure deviations. **Do not change output columns, grain, or business logic** without calling it out and getting a yes. A rename or a dropped column breaks Lightdash charts and downstream models, so grep `ref('<model>')` and the Lightdash dashboards before changing any column name.
3. If a staging model needs a join, do not add it. Propose moving the join into a new `intmdt_` model and let the user decide.
4. Re-run the model and its downstream (`dbt run --select <model>+`) when dbt is available.

## Checklist

- [ ] Correct folder, prefix, `config` block
- [ ] Source only in staging; everything else uses `ref`
- [ ] No subqueries; no joins in staging
- [ ] Final CTE has explicit columns; file ends with `select * from <final_cte>`
- [ ] Keys follow `_pk` / `_skey` / `_key`
- [ ] Timestamps through `to_local_time`
- [ ] `.yml` and grain doc updated
