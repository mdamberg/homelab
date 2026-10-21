# SimpleFIN extractor

Containerized job (`docker/docker-projects/simplefin_extractor/`) that pulls posted
bank transactions and account balances from [SimpleFIN Bridge](https://bridge.simplefin.org)
and lands them in `raw.raw_simplefin_transactions` and `raw.raw_simplefin_balances`. Replaces the retired Teller extractor. It is a job,
not a service: Task Scheduler runs it daily and it exits. It is not in
`start-all-services.ps1` and has no restart policy.

Bank credentials never touch this machine. They are entered once on the SimpleFIN
Bridge site; the homelab holds only a read-only Access URL that cannot move money and
can be disabled from the Bridge at any time.

## Secrets

| File | Holds |
|---|---|
| `C:\Users\mattd\.secrets\simplefin\access_url.txt` | SimpleFIN Access URL (Basic auth credentials embedded) |
| `C:\Users\mattd\.secrets\simplefin\pg_password.txt` | Postgres password for `bank_writer` |

- The folder is **outside the repo** (cannot be committed, even with `git add -f`) and
  outside the Duplicati source. Its ACL grants access to the `mattd` account only.
- `.env` (gitignored, no secrets) sets `SIMPLEFIN_SECRETS_DIR`; see `.env.example`.
- The container receives both as Docker secrets, never environment variables.
- Never open these files in a shared screen, paste them into chat, or print them.

## Connecting a bank (one time)

1. In SimpleFIN Bridge: Financial Institutions → New Connection → connect the bank.
2. Create a setup token in the Bridge.
3. In a PowerShell terminal, run `docker\docker-projects\simplefin_extractor\claim.ps1`
   and paste the token at the hidden prompt. It locks the secrets folder's ACL, claims
   the token, and writes the Access URL to `access_url.txt` without printing it.
4. A setup token works once. If a claim returns 403 and you did not claim it, the token
   may have been intercepted: disable it in the Bridge immediately.

## Run

```powershell
cd C:\Users\mattd\repos\homelab\docker\docker-projects\simplefin_extractor
docker compose --profile manual run --rm simplefin-extractor                                  # daily load
docker compose --profile manual run --rm simplefin-extractor --dry-run --since 2026-04-01     # report history depth, load nothing
docker compose --profile manual run --rm simplefin-extractor --since 2026-04-01               # backfill
```

Exit 0 on success (prints `fetched=N inserted=M balances_fetched=N balances_inserted=M`); non-zero with the reason on stderr.
Any `errlist` entry from SimpleFIN (e.g. the bank connection needs re-authentication)
is a non-zero exit, after loading whatever did arrive.

- **Idempotent:** primary key is `(account_id, transaction_id)` (SimpleFIN ids are only
  unique within an account); re-runs insert nothing new.
- **Balances are snapshots:** SimpleFIN only returns each account's current balance
  as of `balance-date`, with no history. Each run stores one row per account, keyed on
  `(account_id, balance_date)`, so a day when the bank has not refreshed adds nothing.
  Snapshot history starts 2026-10-20; earlier daily balances have to be derived in dbt
  from transactions. `available_balance` is NULL when SimpleFIN omits it (meaning it
  equals `balance`). No extra Bridge requests: balances come back on the same call.
- **Pending transactions are skipped** because their ids may change when they post.
  `LOOKBACK_DAYS` (14) re-reads recent days so they land once posted.
- **Bridge limits:** 24 requests per day; exceeding it disables the token. The docs
  allow 90 days per request, but the Bridge warns past 45, so the job walks 45-day
  windows and refuses ranges needing more than 20 requests.
- **History depth:** Wells Fargo via the Bridge returns about 6 months (earliest
  2026-04-17 when first connected on 2026-10-13). Older data comes from the Teller and
  legacy raw tables, spliced in dbt.
- **Cloudflare:** the Bridge sits behind Cloudflare, which blocks Python's default
  User-Agent with `error code: 1010`. The job sends its own User-Agent; a 1010 is
  reported as a Cloudflare block, not a token problem.

## Scheduling and monitoring

`run.ps1` runs the job via Task Scheduler (daily at 6:00 AM) and writes timestamped
output to one file per run, `%LOCALAPPDATA%\simplefin-extractor\run-yyyyMMdd-HHmmss.log`,
keeping the newest 30 (`-KeepLogs`). Task Scheduler history is disabled on this machine,
so these logs and the Kuma heartbeats are the only run record. If Docker is not reachable
(e.g. Docker Desktop still starting after a reboot), it retries every 5 minutes for up
to an hour before calling SimpleFIN, so retries never use Bridge quota; after that it
logs the failure and exits 1. On success the job pings an Uptime
Kuma push monitor (`KUMA_PUSH_URL` in `.env`, via `host.docker.internal:3001`). On any
non-zero exit, `run.ps1` pushes `status=down` with the last log lines as the message,
so Discord alerts within minutes with the reason. A run that never starts shows up as a
missing heartbeat after the monitor's 26h window.

The Bridge only promises daily updates, so `balances_inserted=0` is normal when the bank
has not refreshed since the last run; the run still succeeds and pings Kuma.

n8n does not run this job: invoking Docker from n8n would mean mounting the Docker
socket into it, which gives anything with n8n access control of every container and
secret on the host.

## Database

`dbt/postgres/init/02-create-raw-tables.sql` defines `raw.raw_simplefin_transactions`,
`raw.raw_simplefin_balances`, and the `bank_writer` role (select/insert on those two
tables only). Init scripts only run on an empty data directory, so new tables there
must also be created by hand on the live database. The container joins the
external `home-metrics` network and connects to `home-metrics-postgres`, database
`home_metrics`.
