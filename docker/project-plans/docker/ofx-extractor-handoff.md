# Handoff: Wells Fargo OFX extractor

> **Superseded 2026-10-13.** OFX was dropped in favor of SimpleFIN Bridge, whose
> read-only token cannot move money. See `docs/finance/simplefin-extractor.md` and
> `docker/docker-projects/simplefin_extractor/`. Kept for history.

**Service dir:** `docker/docker-projects/ofx_extractor/`
**Status:** scaffolded, not built. `Dockerfile` is empty, `extract.py` is a
pseudocode sketch, `compose.yaml` is a draft with known errors (see below).

## Goal

A containerized job that pulls Wells Fargo transactions via OFX Direct Connect
on a schedule and lands them in Postgres. Replaces a retired Teller.io
extractor that fed the same warehouse.

This is a **job, not a service**: it runs, exits, and is invoked by n8n. It
does **not** get `restart: unless-stopped` and it does **not** get added to
`start-all-services.ps1`.

---

## Critical context — read before writing any code

### There is no API key

OFX Direct Connect authenticates with the account holder's regular Wells Fargo
username and password. There is no API key, OAuth client, developer portal, or
token to generate. Do not go looking for one.

### Authorization is a timed window, and only Matt can open it

Wells Fargo requires Direct Connect to be authorized from their website:

```
https://connect.secure.wellsfargo.com/auth/login/present?loginMode=jukePassword&serviceType=fms
```

Signing in there and confirming opens a **~10 minute window** during which the
first OFX request must succeed. One attempt has already been burned by arming
it before anything was built.

**Do not ask Matt to open this window until every offline step below passes.**
Missing it is not destructive — it can be re-armed — but each attempt costs a
manual login and MFA round trip.

### `clientuid` must be stable forever

Whatever UUID4 is used for the successful registration is bound to the account
at Wells Fargo's end. Changing it later forces re-registration. Generate it
once, commit it to `ofxget.cfg`, never regenerate it — including across
rebuilds, image changes, and a future host migration.

---

## Deviation from `docker/CLAUDE.md` — read this, it is deliberate

`CLAUDE.md` says: *"Use `${VAR}` env references, keep secrets in `.env` files."*

**This service deviates from that, intentionally.** Use Docker secrets
(`file:` provider) instead. Rationale:

The Wells Fargo Direct Connect credential is **not read-only**. Bill pay runs
over the same channel, so this password can move money, and WF's web MFA does
not protect the OFX endpoint. Env vars are visible in `docker inspect`, in
`/proc/<pid>/environ`, to every child process, and in `docker compose config`
output. Docker secrets mount to tmpfs at `/run/secrets/<name>` and appear in
none of those.

Rules for this service:

- Password read from a file path given by a `*_FILE` env var — never the value
  in an env var directly
- Nothing secret in `compose.yaml`, `ofxget.cfg`, or the image
- **Do not** use `ofxget --savepass` or the `keyring` library. In a headless
  container `keyring` falls back to `keyrings.alt`, which writes a
  weakly-obfuscated file — worse than `chmod 600` plaintext because it looks
  secure.
- Container is egress-only: no published ports, no reverse proxy, no Tailscale
  funnel. It needs `ofxdc.wellsfargo.com` and Postgres, nothing else.

**Backup caveat to raise with Matt:** Duplicati sources the whole
`docker-projects/` folder, so a `secrets/` directory there means the WF
password lands in backup sets. Either exclude `ofx_extractor/secrets/` from the
Duplicati source, or accept it knowingly. Do not silently leave it.

---

## Known defects in the existing scaffold

| File | Problem |
|---|---|
| `Dockerfile` | Empty |
| `extract.py` | Pseudocode — no imports, no `main()`, no config loading, no DB connection, no error handling |
| `secrets` | Exists as an **empty file**, must be a **directory**. Delete it and `mkdir secrets`. |
| `compose.yaml` | Mounts cfg to `/root/.config/...` but the container should run non-root — path must match the non-root user's home |
| `compose.yaml` | Declares `pg_password` secret but it is missing from the service's `secrets:` list |
| `compose.yaml` | `networks: [warehouse]` — **almost certainly wrong**, see below |
| `compose.yaml` | Filename should be `docker-compose.yml` per repo convention |
| `.gitignore` | Must cover `ofx_extractor/secrets/` before anything is committed |

### Verify the Postgres target before writing connection code

`CLAUDE.md` puts Postgres in the `dbt/` tree as `home-metrics-postgres`, and
notes Lightdash requires `docker network create home-metrics`. So the network
is likely `home-metrics`, not `warehouse`, and the DB/user names in the draft
compose are guesses.

Confirm with:

```powershell
docker inspect home-metrics-postgres --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{println}}{{end}}'
docker inspect home-metrics-postgres --format '{{range .Config.Env}}{{.}}{{println}}{{end}}'
```

Do not guess. Ask Matt if ambiguous.

---

## Build steps

### 1. `requirements.txt`

```
ofxtools==<pin>
psycopg2-binary==<pin>
```

### 2. `Dockerfile`

- Slim Python base (`python:3.12-slim`)
- Install from `requirements.txt`
- Non-root user with a real home directory (the cfg mount target depends on it)
- `TZ=America/Chicago`
- `ENTRYPOINT` runs `extract.py`
- Must work under `read_only: true` — writes only to `/tmp` (tmpfs)
- No secrets or account-specific values baked in

### 3. `ofxget.cfg`

Committed. No secrets. Mounted read-only.

```ini
[wells]
url       = https://ofxdc.wellsfargo.com/ofx/process.ofx
org       = WF
fid       = 3000
bankid    = <MATT SUPPLIES — WF routing number>
user      = <MATT SUPPLIES — WF online banking username>
clientuid = <GENERATE ONCE — python -c "import uuid; print(uuid.uuid4())">
appid     = QWIN
appver    = 2700
version   = 220
```

`appid = QWIN` identifies the client as Quicken. This is correct and expected —
WF's authorization page registers the access under the name "Quicken". Do not
"fix" it.

### 4. `extract.py`

Implement properly from this sketch:

```python
pw    = Path(os.environ["WF_PASSWORD_FILE"]).read_text().strip()
start = date.today() - timedelta(days=int(os.environ["LOOKBACK_DAYS"]))

client = OFXClient(**cfg)
resp   = client.request_statements(pw, StmtRq(dtstart=start))
stmts  = OFXTree().parse(resp).convert()

rows = [
    (
        "wf_ofx",
        f"wf:{t.fitid}",
        stmt.account.acctid,
        t.dtposted,
        t.trnamt,
        t.name,
        json.dumps(asdict(t), default=str),
    )
    for stmt in stmts.statements
    for t in stmt.transactions
]

execute_values(cur, """
    insert into raw.transactions
      (source, external_id, account_id, posted_at, amount, description, payload)
    values %s
    on conflict (source, external_id) do nothing
""", rows)
```

Requirements:

- `FITID` is WF's own stable transaction id. It is what makes the overlapping
  lookback window idempotent. Do not generate a surrogate key.
- Default `LOOKBACK_DAYS=7` to catch pending→posted transitions.
- Exit non-zero on any failure with the reason on stderr. n8n branches on exit
  code.
- **Never log the password, the full OFX response body, or account numbers.**
- Add `--acctinfo` mode: asks WF which accounts exist. This is the first call
  to make during the registration window because it needs no account numbers.
- Add `--from-file <path>` mode: parses a local `.QFX` instead of making a
  network call. This is how everything gets tested without burning a window.

### 5. `docker-compose.yml`

Fix the defects listed above. 2-space YAML indentation. Keep
`profiles: ["manual"]` — it keeps the job out of `docker compose up`.

**All paths relative** — no absolute `C:\` paths. Matt may migrate this host to
a NAS or Ubuntu Server, and the move should be a copy, not a rewrite.

### 6. Postgres DDL

```sql
create schema if not exists raw;

create table if not exists raw.transactions (
  source        text          not null,
  external_id   text          not null,
  account_id    text          not null,
  posted_at     timestamptz   not null,
  amount        numeric(14,2) not null,
  description   text,
  payload       jsonb         not null,
  loaded_at     timestamptz   not null default now(),
  primary key (source, external_id)
);
```

Create an `ofx_writer` role with insert/select on `raw.transactions` only. Do
not reuse the dbt role or a superuser.

The `source` column is load-bearing — it is what lets a different extractor be
swapped in without touching anything downstream.

### 7. dbt staging model

`stg_transactions.sql` in the `dbt/` tree. **CTEs only, no subqueries** — hard
repo convention.

```sql
with source as (
    select *
    from {{ source('raw', 'transactions') }}
),

renamed as (
    select
        source        as feed,
        external_id,
        account_id,
        posted_at,
        amount,
        description,
        case when amount < 0 then 'debit' else 'credit' end as direction
    from source
)

select * from renamed
```

Add `sources.yml` for `raw.transactions`. Add `unique` and `not_null` tests on
the `source` + `external_id` combination.

### 8. n8n workflow

```
Schedule (daily 06:00)
  └─ Execute Command: docker compose --profile manual run --rm ofx-extractor
       ├─ exit 0 → HTTP GET <uptime-kuma-push-url>
       └─ exit ≠0 → Discord webhook with stderr tail
```

Uptime Kuma: push monitor, 26-hour heartbeat. This is what catches Docker
Desktop taking the stack down — a missed run and a silent failure look
identical otherwise.

### 9. Docs

Per `CLAUDE.md`: check `docs/SUMMARY.md`, then add a page under `docs/`
covering what this service does, the Direct Connect enrollment procedure, and
the `clientuid` constraint. The enrollment steps are not discoverable from the
code and will be forgotten.

---

## Test order

Steps 1–6 need **no Wells Fargo credentials and no registration window**. Do
all of them before asking Matt for anything.

1. Image builds; container starts non-root with a read-only filesystem
2. Container reaches Postgres and can insert into `raw.transactions`
3. Matt manually downloads one `.QFX` (Accounts → Download Account Activity →
   Quicken format) into `tests/fixtures/`
4. `--from-file` parses it and inserts rows correctly
5. Re-run step 4 — confirm **zero** new rows (idempotency via `on conflict`)
6. dbt builds `stg_transactions` off the loaded rows
7. **Only now:** Matt arms the WF window; run `--acctinfo` immediately and
   confirm accounts come back
8. Full live run, then wire up n8n and Uptime Kuma

---

## Needs Matt

- WF routing number
- WF online banking username
- Password written to `secrets/wf_password.txt` (he does this, not you)
- Confirmation of the real Postgres network, database, and role
- Uptime Kuma push URL
- A sample `.QFX` for fixture testing
- Decision on the Duplicati/secrets backup question
- Opening the registration window — **last step, on explicit request**

Do not commit or push without asking.

---

## Risk note

Bank of America discontinued OFX entirely in September 2025 — Direct Connect
and Web Connect both. Wells Fargo is a sustaining member of FDX, the consortium
driving the industry off OFX, and has made no commitment to keeping it.

Build so the extractor is swappable. The `source` column and the staging model
are the seam. Migrating to SimpleFIN (~$15/yr, read-only token, JSON API)
should cost one new extractor and zero downstream changes.
