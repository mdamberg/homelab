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

ping_hc "${HC_URL}/start"

# Freshness runs every invocation but never blocks transforms, and pings its
# own check — a stale source should raise its own alert, separate from
# whether dbt run/test actually succeeded.
FRESHNESS_EXIT=0
dbt source freshness || FRESHNESS_EXIT=$?

if [ "$FRESHNESS_EXIT" -eq 0 ]; then
    ping_hc "$HC_DBT_FRESHNESS"
else
    ping_hc "${HC_DBT_FRESHNESS}/fail"
fi

EXIT=0

if [ "$MODE" = "regular" ]; then
    { dbt run && dbt test; } || EXIT=$?
else
    { dbt run --full-refresh --select path:models/staging && dbt test; } || EXIT=$?
fi

if [ "$EXIT" -eq 0 ]; then
    ping_hc "$HC_URL"
else
    ping_hc "${HC_URL}/fail"
fi

exit $EXIT
