---
name: dbt-yaml-standards
description: Create, review, or backfill dbt .yml documentation (model and column descriptions, tests, Lightdash dimension types, source freshness) in dbt/home_metrics_dbt. Use when adding a .yml for a new model, when a model's yml is missing or has blank descriptions or tests, or when asked to standardize or audit dbt documentation. Pair with dbt-sql-standards.
---

# dbt YAML Standards

Each model has one `.yml` beside its `.sql` with the same base name. Sources are defined per domain in `models/staging/<domain>/sources.yml` (hardware uses `sources.yaml`).

## Model file shape

```yaml
version: 2

models:
  - name: fct_example
    description: "One row per <grain>. <What it is used for.>"
    columns:
      - name: example_skey
        description: "Surrogate key for the row"
        tests:
          - unique
          - not_null
        config:
          meta:
            dimension:
              type: string
```

Rules:

- `version: 2` is the first line.
- The model `description` states the grain ("One row per ...") and purpose. It must match the grain recorded in the layer's `*_table_grain.md`.
- Every column listed in the `.sql` final select has an entry, in the same order, with a non-empty description. Never leave `description: ""`.
- `config.meta.dimension.type` on every column is one of `string`, `number`, `date`, `timestamp`, `boolean`. Lightdash reads it. Pick it from the SQL cast or logic.
- Descriptions are short and say what the value means, plus units or allowed values when relevant: "Transaction amount (negative for debits)".

## Tests

| Column kind | Required tests |
|---|---|
| `_pk`, `_skey` | `unique`, `not_null` |
| `_key` (dimension key) | `not_null` only. Never `unique`: it is shared across rows. |
| other columns | none by default; add `not_null` when the model's logic guarantees it |

Recommended where it fits, introduced as models are touched (the project does not use them yet):
- `accepted_values` for small fixed sets (status, flow, type columns).
- `relationships` from a fact's `_key` to the dim's key, only when the dim key is truly unique in the dim.

## sources.yml

Each raw table lists its columns with descriptions, `loaded_at_field`, and `freshness` (`warn_after` / `error_after`) sized to how often n8n loads it. A new raw table from n8n is not done until it is here.

## Writing descriptions

Derive meaning from the SQL (the cast, case logic, or macro) and from the matching description in `sources.yml`. Do not invent business meaning. If a column's purpose is unclear, write what the SQL does and list it as a question for the user instead of guessing.

## Workflow: new model

1. Read the finished `.sql` and list its output columns.
2. Write the `.yml` to the shape above.
3. Update the layer's `*_table_grain.md`.
4. `dbt parse` (or `dbt test --select <model>` when the database is reachable) to confirm it loads.

## Workflow: audit and backfill

Scan `models/` and report, per model:

- no `.yml` at all
- missing `version: 2`
- missing or empty model description
- columns in the `.sql` not in the `.yml`, or in the `.yml` but not the `.sql`
- blank column descriptions
- `_pk` / `_skey` columns without `unique` and `not_null`; `unique` wrongly placed on a `_key`

Then fix in batches by layer, smallest layer first, showing the diff summary. Do not touch `.sql` files during a YAML backfill; if the SQL looks wrong, report it separately.

## Checklist

- [ ] `version: 2`, model description with grain
- [ ] All output columns present, none blank
- [ ] Lightdash `dimension.type` on each column
- [ ] Key tests follow the table above
- [ ] Grain doc and `sources.yml` updated where relevant
