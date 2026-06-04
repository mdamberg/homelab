#!/bin/sh
# Wrapper around dbt runs. Pings Healthchecks.io on start, success, and failure.
# Usage: run-dbt.sh regular | refresh

MODE=${1:-regular}

if [ "$MODE" = "regular" ]; then
    HC_URL="$HC_DBT_REGULAR"
else
    HC_URL="$HC_DBT_REFRESH"
fi

ping_hc() {
    # Best-effort — never let a HC outage kill the dbt job
    if [ -n "$HC_URL" ]; then
        curl -fsS --retry 3 --max-time 10 "$1" >/dev/null 2>&1 || true
    fi
}

ping_hc "${HC_URL}/start"

EXIT=0

if [ "$MODE" = "regular" ]; then
    dbt run && dbt test || EXIT=$?
else
    dbt source freshness && dbt run --full-refresh --select path:models/staging && dbt test || EXIT=$?
fi

if [ "$EXIT" -eq 0 ]; then
    ping_hc "$HC_URL"
else
    ping_hc "${HC_URL}/fail"
fi

exit $EXIT
