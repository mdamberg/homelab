# dbt runner image: dbt-postgres + supercronic (cron for containers)
FROM python:3.11-slim

# curl is needed for Healthchecks.io pings in run-dbt.sh
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Install dbt with the Postgres adapter
RUN pip install --no-cache-dir "dbt-postgres~=1.8.0"

# Install supercronic (a cron implementation designed for containers)
ARG SUPERCRONIC_VERSION=v0.2.33
ARG SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64
ADD ${SUPERCRONIC_URL} /usr/local/bin/supercronic
RUN chmod +x /usr/local/bin/supercronic

COPY run-dbt.sh /usr/local/bin/run-dbt.sh
RUN chmod +x /usr/local/bin/run-dbt.sh

# dbt project gets mounted here at runtime
WORKDIR /usr/app/dbt
