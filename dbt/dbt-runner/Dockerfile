# dbt runner image: dbt-postgres + supercronic (cron for containers)
FROM python:3.11-slim

# Install dbt with the Postgres adapter
RUN pip install --no-cache-dir "dbt-postgres~=1.8.0"

# Install supercronic (a cron implementation designed for containers)
ARG SUPERCRONIC_VERSION=v0.2.33
ARG SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64
ADD ${SUPERCRONIC_URL} /usr/local/bin/supercronic
RUN chmod +x /usr/local/bin/supercronic

# dbt project gets mounted here at runtime
WORKDIR /usr/app/dbt
