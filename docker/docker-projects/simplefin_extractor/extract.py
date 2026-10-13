"""Load posted bank transactions from SimpleFIN Bridge into Postgres.

Modes:
  (default)             load the last LOOKBACK_DAYS of posted transactions
  --since YYYY-MM-DD    backfill from a date, walking 45-day windows
  --dry-run             fetch and report per-account coverage; load nothing

Exits non-zero on any failure with the reason on stderr. Never prints the
Access URL, response bodies, or account identifiers.
"""
import argparse
import base64
import datetime as dt
import json
import os
import re
import sys
from decimal import Decimal
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

import psycopg2
from psycopg2.extras import execute_values

# Bridge limits: 24 requests per day (exceeding it disables the token), and it
# warns past 45 days per request even though the docs say 90.
WINDOW = dt.timedelta(days=45)
MAX_REQUESTS_PER_RUN = 20
USER_AGENT = "homelab-simplefin-extractor/1.0"


class ExtractError(Exception):
    pass


def read_secret(env_var):
    path = os.environ.get(env_var)
    if not path:
        raise ExtractError(f"{env_var} is not set")
    value = Path(path).read_text().strip()
    if not value:
        raise ExtractError(f"secret file for {env_var} is empty")
    return value


def load_access():
    """Split the Access URL into a credential-free base URL and a Basic auth header."""
    try:
        url = urlsplit(read_secret("SIMPLEFIN_ACCESS_URL_FILE"))
        username, password, host, port = url.username, url.password, url.hostname, url.port
    except ValueError:
        raise ExtractError("Access URL is malformed") from None
    if url.scheme != "https" or not (username and password and host):
        raise ExtractError("Access URL is malformed")
    netloc = f"{host}:{port}" if port else host
    base = urlunsplit(("https", netloc, url.path.rstrip("/"), "", ""))
    creds = base64.b64encode(f"{unquote(username)}:{unquote(password)}".encode()).decode()
    return base, f"Basic {creds}"


def windows(start, end):
    spans = []
    while start < end:
        spans.append((start, min(start + WINDOW, end)))
        start += WINDOW
    if len(spans) > MAX_REQUESTS_PER_RUN:
        raise ExtractError(f"range needs {len(spans)} requests; limit is {MAX_REQUESTS_PER_RUN} per run")
    return spans


def fetch(base, auth, start, end):
    query = urlencode({
        "start-date": int(start.timestamp()),
        "end-date": int(end.timestamp()),
        "version": 2,
    })
    # Cloudflare in front of the Bridge blocks urllib's default User-Agent (error 1010)
    headers = {"Authorization": auth, "User-Agent": USER_AGENT}
    request = Request(f"{base}/accounts?{query}", headers=headers)
    try:
        with urlopen(request, timeout=120) as response:
            return json.load(response)
    except HTTPError as exc:
        body = exc.read(100).decode(errors="replace")
        if exc.code == 403 and body.startswith("error code:"):
            raise ExtractError(f"blocked by Cloudflare before reaching SimpleFIN ({body.strip()})") from None
        if exc.code == 403:
            raise ExtractError("SimpleFIN refused access (403): token revoked or invalid") from None
        if exc.code == 402:
            raise ExtractError("SimpleFIN subscription needs payment (402)") from None
        raise ExtractError(f"SimpleFIN returned HTTP {exc.code}") from None
    except URLError as exc:
        raise ExtractError(f"could not reach SimpleFIN: {exc.reason}") from None
    except json.JSONDecodeError:
        raise ExtractError("SimpleFIN response was not valid JSON") from None


def errors_of(account_set):
    errlist = account_set.get("errlist")
    if errlist is None:
        errlist = [{"code": "gen.", "msg": msg} for msg in account_set.get("errors", [])]
    return [f"{e.get('code', 'gen.')} {e.get('msg', '')}".strip() for e in errlist]


def epoch(value):
    return dt.datetime.fromtimestamp(value, dt.timezone.utc) if value else None


def to_rows(account_set):
    institutions = {c["conn_id"]: c.get("name") for c in account_set.get("connections", [])}
    rows = []
    for account in account_set.get("accounts", []):
        institution = institutions.get(account.get("conn_id")) or account.get("org", {}).get("name")
        for txn in account.get("transactions", []):
            # Pending ids may change once posted; the lookback window picks them up then
            if txn.get("pending") or not txn.get("posted"):
                continue
            rows.append((
                account["id"],
                txn["id"],
                institution,
                account.get("name"),
                epoch(txn["posted"]),
                epoch(txn.get("transacted_at")),
                Decimal(txn["amount"]),
                txn.get("description"),
                json.dumps(txn),
            ))
    return rows


def load_rows(rows):
    if not rows:
        return 0
    conn = psycopg2.connect(
        host=os.environ["PGHOST"],
        dbname=os.environ["PGDATABASE"],
        user=os.environ["PGUSER"],
        password=read_secret("PGPASSWORD_FILE"),
        connect_timeout=10,
    )
    try:
        with conn, conn.cursor() as cur:
            inserted = execute_values(
                cur,
                """
                insert into raw.raw_simplefin_transactions
                  (account_id, transaction_id, institution_name, account_name,
                   posted_at, transacted_at, amount, description, payload)
                values %s
                on conflict (account_id, transaction_id) do nothing
                returning 1
                """,
                rows,
                fetch=True,
            )
        return len(inserted)
    finally:
        conn.close()


def report(rows):
    """Per-account coverage without account ids; digits in names are masked."""
    coverage = {}
    for account_id, _, institution, name, posted, *_ in rows:
        label = f"{institution or '?'} / {re.sub(r'[0-9]', '#', name or '?')}"
        _, first, last, count = coverage.get(account_id, (label, posted, posted, 0))
        coverage[account_id] = (label, min(first, posted), max(last, posted), count + 1)
    for label, first, last, count in sorted(coverage.values()):
        print(f"{label}: {count} posted transactions, {first:%Y-%m-%d} to {last:%Y-%m-%d}")


def ping_kuma(message):
    # Kuma shows the push URL with its own ?status=... query; replace it with ours
    url = os.environ.get("KUMA_PUSH_URL", "").split("?")[0]
    if not url:
        return
    try:
        urlopen(f"{url}?{urlencode({'status': 'up', 'msg': message})}", timeout=10).close()
    except (URLError, ValueError) as exc:
        print(f"warning: Uptime Kuma push failed: {type(exc).__name__}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--since", type=dt.date.fromisoformat, metavar="YYYY-MM-DD")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    try:
        now = dt.datetime.now(dt.timezone.utc)
        if args.since:
            start = dt.datetime.combine(args.since, dt.time(), dt.timezone.utc)
        else:
            start = now - dt.timedelta(days=int(os.environ.get("LOOKBACK_DAYS", "14")))

        base, auth = load_access()
        rows, errors = [], []
        for window_start, window_end in windows(start, now):
            account_set = fetch(base, auth, window_start, window_end)
            rows.extend(to_rows(account_set))
            errors.extend(errors_of(account_set))

        if args.dry_run:
            report(rows)
            inserted = 0
        else:
            inserted = load_rows(rows)
        print(f"fetched={len(rows)} inserted={inserted}")

        if errors:
            # Rows that did arrive are kept; the non-zero exit makes the gap visible
            raise ExtractError("SimpleFIN reported errors: " + "; ".join(sorted(set(errors))))
        if not args.dry_run:
            ping_kuma(f"inserted={inserted}")
    except Exception as exc:  # exit code is the contract with the scheduler
        print(f"error: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
