"""Load posted bank transactions and account balances from SimpleFIN Bridge into Postgres.

Schedule: once a day at 6:00 PM (America/Chicago), after the Bridge's ~4:45 PM
bank refresh, run by the Windows Task Scheduler task "SimpleFIN extractor" via
run.ps1, only while user mattd is logged in. The schedule lives in Task Scheduler, not here; change it there.

Modes:
  (default)             load the last LOOKBACK_DAYS of posted transactions
  --since YYYY-MM-DD    backfill from a date, walking 45-day windows
  --dry-run             fetch and report per-account coverage; load nothing

Exits non-zero on any failure with the reason on stderr. Never prints the
Access URL, response bodies, or account identifiers.
"""
# The triple-quoted string above is the module "docstring". Python stores it in
# __doc__, and main() reuses it as the --help text.

# ---------------------------------------------------------------------------
# Imports
# ---------------------------------------------------------------------------
# Standard library modules (ship with Python, nothing to install).
import argparse                     # parses command-line flags like --since
import base64                       # encodes the username:password for HTTP Basic auth
import datetime as dt               # "as dt" is an alias, so we write dt.datetime instead of datetime.datetime
import json                         # converts between JSON text and Python dicts/lists
import os                           # reads environment variables (os.environ)
import re                           # regular expressions (pattern matching on text)
import sys                          # stderr output and exit codes
from decimal import Decimal         # exact decimal math; floats can't represent money exactly (0.1 + 0.2 != 0.3)
from pathlib import Path            # object-oriented file paths; Path(...).read_text() reads a file
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

# Third-party package, installed from requirements.txt in the Dockerfile.
import psycopg2                     # the Postgres driver
from psycopg2.extras import execute_values

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# ALL_CAPS names are a Python convention meaning "set once, never changed".
# Bridge limits: 24 requests per day (exceeding it disables the token), and it
# warns past 45 days per request even though the docs say 90.
WINDOW = dt.timedelta(days=45)      # a timedelta is a length of time you can add to a datetime
MAX_REQUESTS_PER_RUN = 20
USER_AGENT = "homelab-simplefin-extractor/1.0"


# A custom exception type. Subclassing Exception and adding nothing ("pass")
# just gives it a name, so the handler in main() can tell "a problem we
# expected and described" apart from anything else that crashes.
class ExtractError(Exception):
    pass


# ---------------------------------------------------------------------------
# Secrets and connection details
# ---------------------------------------------------------------------------
def read_secret(env_var):
    # The environment variable holds a *file path*, not the secret itself
    # (e.g. PGPASSWORD_FILE=/run/secrets/pg_password). That keeps the secret
    # out of `docker inspect` and process listings.
    path = os.environ.get(env_var)          # .get() returns None instead of crashing if it's missing
    if not path:                            # None and "" are both "falsy", so this catches either
        raise ExtractError(f"{env_var} is not set")   # f"..." is an f-string: {expr} is filled in
    value = Path(path).read_text().strip()  # .strip() removes surrounding whitespace/newlines
    if not value:
        raise ExtractError(f"secret file for {env_var} is empty")
    return value


def load_access():
    """Split the Access URL into a credential-free base URL and a Basic auth header."""
    # The Access URL looks like https://USER:PASS@host/simplefin. We pull the
    # user/pass out and send them as a header instead, so the credentials never
    # appear in a URL that could end up in an error message.
    try:
        url = urlsplit(read_secret("SIMPLEFIN_ACCESS_URL_FILE"))   # breaks a URL into named parts
        # Tuple unpacking: assigns four values in one line, left to right.
        username, password, host, port = url.username, url.password, url.hostname, url.port
    except ValueError:
        # "from None" hides the original error, whose message could contain
        # part of the URL. We raise our own vague message instead.
        raise ExtractError("Access URL is malformed") from None
    if url.scheme != "https" or not (username and password and host):
        raise ExtractError("Access URL is malformed")
    # Conditional expression: <value if true> if <condition> else <value if false>
    netloc = f"{host}:{port}" if port else host
    # Rebuild the URL without the user/pass. The two "" are the empty query and fragment.
    base = urlunsplit(("https", netloc, url.path.rstrip("/"), "", ""))
    # HTTP Basic auth = base64("user:pass"). .encode() turns text into bytes
    # (b64encode works on bytes) and .decode() turns the result back into text.
    creds = base64.b64encode(f"{unquote(username)}:{unquote(password)}".encode()).decode()
    return base, f"Basic {creds}"            # returning two values actually returns one tuple


# ---------------------------------------------------------------------------
# Talking to SimpleFIN
# ---------------------------------------------------------------------------
def windows(start, end):
    # Splits one long date range into 45-day chunks, one request each.
    # Example: 100 days -> [(day 0, day 45), (day 45, day 90), (day 90, day 100)]
    spans = []
    while start < end:
        spans.append((start, min(start + WINDOW, end)))   # min() keeps the last chunk from overshooting
        start += WINDOW
    # Refuse up front, before any request is made, so a big backfill can never
    # burn through the daily quota and get the token disabled.
    if len(spans) > MAX_REQUESTS_PER_RUN:
        raise ExtractError(f"range needs {len(spans)} requests; limit is {MAX_REQUESTS_PER_RUN} per run")
    return spans


def fetch(base, auth, start, end):
    # urlencode turns a dict into "start-date=...&end-date=...&version=2".
    # SimpleFIN wants dates as Unix timestamps (seconds since 1970-01-01).
    query = urlencode({
        "start-date": int(start.timestamp()),
        "end-date": int(end.timestamp()),
        "version": 2,
    })
    # Cloudflare in front of the Bridge blocks urllib's default User-Agent (error 1010)
    headers = {"Authorization": auth, "User-Agent": USER_AGENT}
    request = Request(f"{base}/accounts?{query}", headers=headers)
    try:
        # "with" is a context manager: the response is closed automatically when
        # the block ends, even if an error happens inside it.
        with urlopen(request, timeout=120) as response:
            return json.load(response)       # parse the JSON body into Python dicts/lists
    # A try can have several "except" blocks. Python runs the first one whose
    # type matches the error. "as exc" gives the error object a name.
    except HTTPError as exc:                 # the server answered, but with an error status
        body = exc.read(100).decode(errors="replace")   # first 100 bytes only, enough to spot Cloudflare
        if exc.code == 403 and body.startswith("error code:"):
            raise ExtractError(f"blocked by Cloudflare before reaching SimpleFIN ({body.strip()})") from None
        if exc.code == 403:
            raise ExtractError("SimpleFIN refused access (403): token revoked or invalid") from None
        if exc.code == 402:
            raise ExtractError("SimpleFIN subscription needs payment (402)") from None
        raise ExtractError(f"SimpleFIN returned HTTP {exc.code}") from None
    except URLError as exc:                  # never got an answer (DNS, network down, timeout)
        raise ExtractError(f"could not reach SimpleFIN: {exc.reason}") from None
    except json.JSONDecodeError:             # answered, but the body wasn't JSON
        raise ExtractError("SimpleFIN response was not valid JSON") from None


def errors_of(account_set):
    # SimpleFIN v2 reports problems in "errlist" (a list of dicts); older servers
    # used "errors" (a list of strings). Handle both and return plain strings.
    errlist = account_set.get("errlist")
    if errlist is None:
        # List comprehension: builds a new list in one expression.
        # Reads as: "for each msg in the errors list, make this dict".
        errlist = [{"code": "gen.", "msg": msg} for msg in account_set.get("errors", [])]
    # The second argument to .get() is a default used when the key is missing.
    return [f"{e.get('code', 'gen.')} {e.get('msg', '')}".strip() for e in errlist]


# ---------------------------------------------------------------------------
# Shaping the data
# ---------------------------------------------------------------------------
def epoch(value):
    # Unix timestamp -> timezone-aware datetime in UTC. Returns None for 0 or missing.
    return dt.datetime.fromtimestamp(value, dt.timezone.utc) if value else None


def institution_of(account_set, account):
    # Dict comprehension: {key: value for item in list}. Builds a lookup from
    # connection id to institution name, e.g. {"CONN-1": "Wells Fargo"}.
    institutions = {c["conn_id"]: c.get("name") for c in account_set.get("connections", [])}
    # "or" returns the first truthy value, so this falls back to the older
    # "org" field when the connection lookup finds nothing.
    return institutions.get(account.get("conn_id")) or account.get("org", {}).get("name")


def to_rows(account_set):
    # Turns SimpleFIN's nested JSON (accounts -> transactions) into flat tuples,
    # one per transaction, in the same column order as the INSERT in load_rows().
    rows = []
    for account in account_set.get("accounts", []):
        institution = institution_of(account_set, account)
        for txn in account.get("transactions", []):
            # Pending ids may change once posted; the lookback window picks them up then
            if txn.get("pending") or not txn.get("posted"):
                continue                         # skip to the next transaction
            # Note the double parentheses: append() takes one argument, a tuple.
            rows.append((
                account["id"],                   # ["key"] crashes if missing, which is right for required fields
                txn["id"],
                institution,
                account.get("name"),             # .get() for optional fields: None if missing
                epoch(txn["posted"]),
                epoch(txn.get("transacted_at")),
                Decimal(txn["amount"]),          # SimpleFIN sends amounts as strings like "-12.34"
                txn.get("description"),
                json.dumps(txn),                 # the whole raw transaction, kept as JSON text in the payload column
            ))
    return rows


def to_balance_rows(account_set):
    # One tuple per account, in the same column order as the balances INSERT in
    # load_rows(). SimpleFIN only reports the balance as of balance-date, so each
    # run captures a snapshot; history builds up one run at a time.
    rows = []
    for account in account_set.get("accounts", []):
        available = account.get("available-balance")
        # Everything except the transaction list, so "extra" and any fields
        # added to the spec later are kept in the payload column.
        payload = {k: v for k, v in account.items() if k != "transactions"}
        rows.append((
            account["id"],
            account.get("conn_id"),
            institution_of(account_set, account),
            account.get("name"),
            account.get("currency"),
            Decimal(account["balance"]),
            # Omitted by SimpleFIN when it equals balance; left NULL here
            Decimal(available) if available is not None else None,
            epoch(account["balance-date"]),
            json.dumps(payload),
        ))
    return rows


# ---------------------------------------------------------------------------
# Writing to Postgres
# ---------------------------------------------------------------------------
def load_rows(rows, balance_rows):
    # Returns (transactions inserted, balance snapshots inserted).
    if not rows and not balance_rows:            # an empty list is falsy
        return 0, 0
    conn = psycopg2.connect(
        host=os.environ["PGHOST"],               # os.environ["X"] crashes if X is missing; these must be set
        dbname=os.environ["PGDATABASE"],
        user=os.environ["PGUSER"],
        password=read_secret("PGPASSWORD_FILE"),
        connect_timeout=10,
    )
    # try/finally: the finally block always runs, so the connection is closed
    # whether the insert succeeds or fails.
    try:
        # Two context managers in one "with":
        #   conn   -> commits the transaction if the block succeeds, rolls back if it fails
        #   cursor -> the object that actually runs SQL
        with conn, conn.cursor() as cur:
            # execute_values expands "values %s" into one multi-row INSERT. It
            # also handles quoting, so values are never pasted into the SQL as
            # text (that's what prevents SQL injection).
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
            # "on conflict ... do nothing" skips rows already loaded, which is
            # what makes re-runs safe. "returning 1" emits one row per row
            # actually inserted, and fetch=True hands those back, so
            # len(inserted) counts only the new rows.
            # Same pattern for balances. The key is (account_id, balance_date),
            # so a day when the bank hasn't refreshed inserts nothing.
            balances_inserted = execute_values(
                cur,
                """
                insert into raw.raw_simplefin_balances
                  (account_id, conn_id, institution_name, account_name, currency,
                   balance, available_balance, balance_date, payload)
                values %s
                on conflict (account_id, balance_date) do nothing
                returning 1
                """,
                balance_rows,
                fetch=True,
            )
            # Both inserts share one transaction, so a failure loads neither.
        return len(inserted), len(balances_inserted)
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Reporting and monitoring
# ---------------------------------------------------------------------------
def report(rows):
    """Per-account coverage without account ids; digits in names are masked."""
    coverage = {}                                # account_id -> (label, first date, last date, count)
    # Unpacking in a for loop. "_" is a convention for "a value I don't need",
    # and "*_" soaks up all the remaining columns.
    for account_id, _, institution, name, posted, *_ in rows:
        # re.sub(pattern, replacement, text): replace every digit with "#",
        # so account numbers in names like "CHECKING ...1234" are never printed.
        label = f"{institution or '?'} / {re.sub(r'[0-9]', '#', name or '?')}"
        # Fetch this account's running totals, or start fresh if it's the first time we see it.
        _, first, last, count = coverage.get(account_id, (label, posted, posted, 0))
        coverage[account_id] = (label, min(first, posted), max(last, posted), count + 1)
    for label, first, last, count in sorted(coverage.values()):
        # {first:%Y-%m-%d} formats a datetime inside an f-string, e.g. 2026-04-17.
        print(f"{label}: {count} posted transactions, {first:%Y-%m-%d} to {last:%Y-%m-%d}")


def ping_kuma(message):
    # Tells Uptime Kuma "the job ran OK". If Kuma doesn't hear this within its
    # heartbeat window, it alerts on Discord.
    # Kuma shows the push URL with its own ?status=... query; replace it with ours
    url = os.environ.get("KUMA_PUSH_URL", "").split("?")[0]   # [0] = everything before the first "?"
    if not url:
        return                                   # monitoring not configured; skip quietly
    try:
        urlopen(f"{url}?{urlencode({'status': 'up', 'msg': message})}", timeout=10).close()
    except (URLError, ValueError) as exc:        # a tuple catches either error type
        # A failed ping is only a warning: the data already loaded fine, and a
        # missing heartbeat makes Kuma alert anyway.
        print(f"warning: Uptime Kuma push failed: {type(exc).__name__}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main():
    # Command-line flags. argparse also builds --help for free.
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    # type= is a function argparse calls on the raw text. Here it turns
    # "2026-04-01" into a date object and rejects anything malformed.
    parser.add_argument("--since", type=dt.date.fromisoformat, metavar="YYYY-MM-DD")
    # store_true: the flag is a switch, False unless --dry-run is passed.
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()                   # "--dry-run" becomes args.dry_run (dash -> underscore)

    try:
        # 1. Work out the date range to fetch.
        now = dt.datetime.now(dt.timezone.utc)
        if args.since:
            start = dt.datetime.combine(args.since, dt.time(), dt.timezone.utc)   # date + midnight -> datetime
        else:
            # Env vars are always text, so int() converts "14" to 14.
            start = now - dt.timedelta(days=int(os.environ.get("LOOKBACK_DAYS", "14")))

        # 2. Fetch every window and collect rows and errors.
        base, auth = load_access()
        rows, errors = [], []
        balances = {}
        for window_start, window_end in windows(start, now):
            account_set = fetch(base, auth, window_start, window_end)
            rows.extend(to_rows(account_set))    # extend adds each item; append would add the whole list as one item
            errors.extend(errors_of(account_set))
            # Every window returns the same current balances; keying on
            # (account_id, balance_date) keeps one copy of each.
            for row in to_balance_rows(account_set):
                balances[(row[0], row[7])] = row
        balance_rows = list(balances.values())

        # 3. Load (or just report on a dry run).
        if args.dry_run:
            report(rows)
            inserted, balances_inserted = 0, 0
        else:
            inserted, balances_inserted = load_rows(rows, balance_rows)
        print(f"fetched={len(rows)} inserted={inserted} "
              f"balances_fetched={len(balance_rows)} balances_inserted={balances_inserted}")

        # 4. Fail loudly on SimpleFIN errors, otherwise tell Kuma we succeeded.
        if errors:
            # Rows that did arrive are kept; the non-zero exit makes the gap visible
            # set() removes duplicates (the same error can come back for every window).
            raise ExtractError("SimpleFIN reported errors: " + "; ".join(sorted(set(errors))))
        if not args.dry_run:
            ping_kuma(f"inserted={inserted} balances_inserted={balances_inserted}")
    except Exception as exc:  # exit code is the contract with the scheduler
        # Catches anything that went wrong above, prints one clean line to
        # stderr, and exits with code 1. run.ps1 passes that code to Task
        # Scheduler, and Kuma never gets its heartbeat, so you get alerted.
        print(f"error: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)


# __name__ is "__main__" only when this file is run directly
# (python extract.py), not when another file imports it. That lets the
# tests import these functions without kicking off a real run.
if __name__ == "__main__":
    main()
