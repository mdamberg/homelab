#!/bin/sh
# Wrapper around dbt runs. Pings Healthchecks.io on start, success, and failure.
# Usage: run-dbt.sh regular | refresh
#
# Freshness (HC_DBT_FRESHNESS) pings a separate check from the mode's
# run/test result (HC_DBT_REGULAR / HC_DBT_REFRESH). They used to share one
# ping: `dbt source freshness`'s exit code fed the same EXIT variable as
# `dbt run && dbt test`, and a successful run/test never reset it — so one
# stale source (e.g. raw_power_consumption/raw_hardware_sensors/
# raw_system_health, since removed) silently failed the healthcheck every
# time even though dbt itself was fine. Splitting them means a stale source
# still alerts, but doesn't get conflated with an actually broken build.

MODE=${1:-regular}

if [ "$MODE" = "regular" ]; then
    HC_URL="$HC_DBT_REGULAR"
else
    HC_URL="$HC_DBT_REFRESH"
fi

ping_hc() {
    # Best-effort — never let a HC outage kill the dbt job
    if [ -n "$1" ]; then
        curl -fsS --retry 3 --max-time 10 "$1" >/dev/null 2>&1 || true
    fi
}

# Pull the error summary out of a dbt log: everything from dbt's closing
# "Completed with N errors" / "Encountered an error" block, plus stale-source
# lines from freshness (which has no closing summary). Timestamps, blank lines
# and "compiled code at" paths are dropped to keep it short.
summarize_dbt_errors() {
    SUMMARY=$(
        { sed -nE '/Completed with|Encountered an error/,$p' "$1"; grep -E 'ERROR STALE' "$1"; } |
        grep -v 'compiled code at' | sed -E 's/^[0-9:]{8}  //; /^ *$/d'
    )
    [ -n "$SUMMARY" ] || SUMMARY=$(tail -n 25 "$1")
    printf '%s\n' "$SUMMARY"
}

# Failure ping with the error summary first, then the tail of the full dbt
# output. The Discord alert only shows the first 1000 chars of the body;
# the full body (up to 100 kB) is in the check's event log on Healthchecks.
ping_hc_fail() {
    if [ -n "$1" ]; then
        {
            summarize_dbt_errors "$2"
            printf '\n--- dbt output (tail) ---\n'
            tail -c 80000 "$2"
        } | curl -fsS --retry 3 --max-time 10 \
            --data-binary @- "$1/fail" >/dev/null 2>&1 || true
    fi
}

FRESHNESS_LOG=$(mktemp)
BUILD_LOG=$(mktemp)
trap 'rm -f "$FRESHNESS_LOG" "$BUILD_LOG"' EXIT

ping_hc "${HC_URL}/start"

# Freshness runs every invocation but never blocks transforms, and pings its
# own check — a stale source should raise its own alert, separate from
# whether dbt run/test actually succeeded.
FRESHNESS_EXIT=0
dbt --no-use-colors source freshness >"$FRESHNESS_LOG" 2>&1 || FRESHNESS_EXIT=$?
cat "$FRESHNESS_LOG"

if [ "$FRESHNESS_EXIT" -eq 0 ]; then
    ping_hc "$HC_DBT_FRESHNESS"
else
    ping_hc_fail "$HC_DBT_FRESHNESS" "$FRESHNESS_LOG"
fi

EXIT=0

# Regular runs use `dbt build` so snapshots run in DAG order with the models
# they read from (media_library_snapshot depends on stg_media_library_present)
# and SCD2 history is captured on every run. The nightly refresh rebuilds
# staging, then snapshots, then tests. Any failure is folded into EXIT so it
# still alerts. Output is captured to a file (not piped through tee) because
# POSIX sh has no pipefail and the pipe would hide dbt's exit code.
if [ "$MODE" = "regular" ]; then
    dbt --no-use-colors build >"$BUILD_LOG" 2>&1 || EXIT=$?
else
    {
        dbt --no-use-colors run --full-refresh --select path:models/staging &&
        dbt --no-use-colors snapshot &&
        dbt --no-use-colors test
    } >"$BUILD_LOG" 2>&1 || EXIT=$?
fi
cat "$BUILD_LOG"

if [ "$EXIT" -eq 0 ]; then
    ping_hc "$HC_URL"
else
    ping_hc_fail "$HC_URL" "$BUILD_LOG"
fi

exit $EXIT
