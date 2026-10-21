-- ============================================================================
-- Raw tables for data collection from n8n workflows
-- These tables live in the raw schema
-- ============================================================================

-- Set search path to raw schema for all table creation
SET search_path TO raw;

-- ============================================================================
-- Home Assistant Power Consumption
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw_power_consumption (
    id BIGSERIAL PRIMARY KEY,
    entity_id VARCHAR(255) NOT NULL,
    friendly_name VARCHAR(255),
    state NUMERIC(10, 2),
    unit_of_measurement VARCHAR(50),
    device_class VARCHAR(50),
    recorded_at TIMESTAMP NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    attributes JSONB,
    CONSTRAINT valid_state CHECK (state IS NULL OR state >= 0)
);

CREATE INDEX IF NOT EXISTS idx_power_entity_time ON raw_power_consumption(entity_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_power_inserted ON raw_power_consumption(inserted_at DESC);
CREATE INDEX IF NOT EXISTS idx_power_recorded ON raw_power_consumption(recorded_at DESC);

COMMENT ON TABLE raw_power_consumption IS 'Raw power consumption readings from Home Assistant sensors';
COMMENT ON COLUMN raw_power_consumption.entity_id IS 'Home Assistant entity ID (e.g., sensor.living_room_power)';
COMMENT ON COLUMN raw_power_consumption.recorded_at IS 'Timestamp from Home Assistant when reading was taken';
COMMENT ON COLUMN raw_power_consumption.inserted_at IS 'Timestamp when n8n inserted the record';

-- ============================================================================
-- Media Library Stats (Plex/Sonarr/Radarr)
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw_media_library (
    id BIGSERIAL PRIMARY KEY,
    source VARCHAR(50) NOT NULL,
    media_type VARCHAR(50) NOT NULL,
    library_name VARCHAR(255),
    title VARCHAR(200),
    genre VARCHAR(100),
    year INTEGER,
    overview VARCHAR(500),
    ratings VARCHAR(10),
    recorded_at TIMESTAMP NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    metadata JSONB,
    CONSTRAINT uq_media_library_source_title UNIQUE (source, title)
);

CREATE INDEX IF NOT EXISTS idx_media_source_time ON raw_media_library(source, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_media_type ON raw_media_library(media_type);

COMMENT ON TABLE raw_media_library IS 'Individual media items from Plex, Sonarr, and Radarr';
COMMENT ON COLUMN raw_media_library.source IS 'Which service provided the data';
COMMENT ON COLUMN raw_media_library.metadata IS 'Additional data like genres, quality profiles, etc.';

-- ============================================================================
-- Media Library Metrics (Aggregated stats per source)
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw_media_library_metrics (
    id BIGSERIAL PRIMARY KEY,
    source VARCHAR(50) NOT NULL,
    media_type VARCHAR(50),
    library_name VARCHAR(255),
    item_count INTEGER,
    total_size_bytes BIGINT,
    recorded_at TIMESTAMP NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    metadata JSONB,
    CONSTRAINT uq_metrics_source_library_time UNIQUE (source, library_name, recorded_at)
);


CREATE INDEX IF NOT EXISTS idx_media_metrics_source_time ON raw_media_library_metrics(source, recorded_at DESC);

COMMENT ON TABLE raw_media_library_metrics IS 'Aggregated media library metrics (counts, sizes) per source';
COMMENT ON COLUMN raw_media_library_metrics.source IS 'Service that provided the data (plex, sonarr, radarr, prowlarr)';
COMMENT ON COLUMN raw_media_library_metrics.item_count IS 'Number of items in the library at this point in time';

-- ============================================================================
-- Media Activity (Watch History)
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw_media_activity (
    id BIGSERIAL PRIMARY KEY,
    source VARCHAR(50) NOT NULL DEFAULT 'plex',
    user_name VARCHAR(255),
    media_type VARCHAR(50),
    title VARCHAR(500),
    series_title VARCHAR(500),
    duration_seconds INTEGER,
    watched_at TIMESTAMP NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_activity_user_time ON raw_media_activity(user_name, watched_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_watched ON raw_media_activity(watched_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_media_type ON raw_media_activity(media_type);

COMMENT ON TABLE raw_media_activity IS 'Watch/listen history from Plex';
COMMENT ON COLUMN raw_media_activity.metadata IS 'Additional details like device, client, quality, etc.';

-- ============================================================================
-- N8N Workflow Runs
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw_n8n_workflow_runs (
    id BIGSERIAL PRIMARY KEY,
    workflow_id VARCHAR(100) NOT NULL,
    workflow_name VARCHAR(255),
    source VARCHAR(100),
    status VARCHAR(50),
    started_at TIMESTAMP NOT NULL,
    finished_at TIMESTAMP,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_workflow_runs_workflow ON raw_n8n_workflow_runs(workflow_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_runs_status ON raw_n8n_workflow_runs(status, started_at DESC);

COMMENT ON TABLE raw_n8n_workflow_runs IS 'Execution history for n8n workflows';

-- ============================================================================
-- N8N Alerts
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw_n8n_alerts (
    id BIGSERIAL PRIMARY KEY,
    alert_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) DEFAULT 'warning',
    source VARCHAR(100),
    title VARCHAR(500),
    message TEXT,
    triggered_at TIMESTAMP NOT NULL,
    resolved_at TIMESTAMP,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_alerts_type_time ON raw_n8n_alerts(alert_type, triggered_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_severity ON raw_n8n_alerts(severity, triggered_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_source ON raw_n8n_alerts(source, triggered_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_unresolved ON raw_n8n_alerts(resolved_at) WHERE resolved_at IS NULL;

COMMENT ON TABLE raw_n8n_alerts IS 'Unified alerts table for workflow failures, data staleness, and threshold breaches';

-- ============================================================================
-- Hardware Sensors (LibreHardwareMonitor)
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw_hardware_sensors (
    id BIGSERIAL PRIMARY KEY,
    hostname VARCHAR(100),
    sensor_type VARCHAR(50) NOT NULL,
    sensor_name VARCHAR(200) NOT NULL,
    sensor_id VARCHAR(200),
    value NUMERIC,
    value_min NUMERIC,
    value_max NUMERIC,
    unit VARCHAR(20),
    hardware_name VARCHAR(200),
    hardware_type VARCHAR(50),
    recorded_at TIMESTAMP NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_hardware_sensors_type ON raw_hardware_sensors(sensor_type, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_hardware_sensors_name ON raw_hardware_sensors(sensor_name, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_hardware_sensors_host ON raw_hardware_sensors(hostname, recorded_at DESC);

COMMENT ON TABLE raw_hardware_sensors IS 'Hardware sensor data from LibreHardwareMonitor (temperatures, fans, voltages, power)';

-- ============================================================================
-- Date Dimension
-- ============================================================================
CREATE TABLE IF NOT EXISTS dim_date (
    date_id INT PRIMARY KEY NOT NULL,
    date_day DATE NOT NULL,
    day_of_week VARCHAR(10) NOT NULL,
    day_of_week_num SMALLINT NOT NULL,
    month_start_date DATE NOT NULL,
    month_end_date DATE NOT NULL,
    month_name VARCHAR(15) NOT NULL,
    month_number SMALLINT NOT NULL,
    year_start_date DATE NOT NULL,
    year_num INT NOT NULL,
    is_weekend BOOLEAN NOT NULL
);

COMMENT ON TABLE dim_date IS 'Date dimension for time-based analytics';

-- ============================================================================
-- Data Freshness View (uses fully qualified schema names)
-- ============================================================================
CREATE OR REPLACE VIEW raw.v_data_freshness AS
SELECT
    'raw_power_consumption' AS table_name,
    MAX(recorded_at) AS last_recorded,
    MAX(inserted_at) AS last_inserted,
    COUNT(*) AS total_rows,
    NOW() - MAX(inserted_at) AS staleness
FROM raw.raw_power_consumption
UNION ALL
SELECT
    'raw_media_library',
    MAX(recorded_at),
    MAX(inserted_at),
    COUNT(*),
    NOW() - MAX(inserted_at)
FROM raw.raw_media_library
UNION ALL
SELECT
    'raw_media_activity',
    MAX(watched_at),
    MAX(inserted_at),
    COUNT(*),
    NOW() - MAX(inserted_at)
FROM raw.raw_media_activity
UNION ALL
SELECT
    'raw_pihole_metrics',
    MAX(recorded_at),
    MAX(inserted_at),
    COUNT(*),
    NOW() - MAX(inserted_at)
FROM raw.raw_pihole_metrics;

COMMENT ON VIEW raw.v_data_freshness IS 'Monitor data pipeline health and freshness';

-- ============================================================================
-- Grant Permissions
-- ============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA raw TO metrics_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA raw TO metrics_user;
GRANT SELECT ON raw.v_data_freshness TO metrics_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO metrics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT USAGE, SELECT ON SEQUENCES TO metrics_user;

-- Reset search path
SET search_path TO public, raw;


-- ============================================================================
-- Finances
-- ============================================================================

CREATE TABLE IF NOT EXISTS raw.raw_transactions (                                                                                                                                                             id BIGSERIAL PRIMARY KEY,
      transaction_date DATE NOT NULL,                                                                                                                                                                           original_date DATE,
      account_type VARCHAR(100),                                                                                                                                                                          
      account_name VARCHAR(255),
      account_number VARCHAR(50),
      institution_name VARCHAR(255),
      name VARCHAR(500),
      custom_name VARCHAR(500),
      amount NUMERIC(12, 2),
      description TEXT,
      category VARCHAR(255),
      note TEXT,
      ignored_from VARCHAR(255),
      tax_deductible BOOLEAN,
      transaction_tags VARCHAR(500),
      inserted_at TIMESTAMP NOT NULL DEFAULT NOW()
  );

  CREATE INDEX IF NOT EXISTS idx_transactions_date ON raw.raw_transactions(transaction_date DESC);
  CREATE INDEX IF NOT EXISTS idx_transactions_category ON raw.raw_transactions(category);
  CREATE INDEX IF NOT EXISTS idx_transactions_account ON raw.raw_transactions(account_name);
  CREATE INDEX IF NOT EXISTS idx_transactions_institution ON raw.raw_transactions(institution_name);

  GRANT SELECT, INSERT, UPDATE, DELETE ON raw.raw_transactions TO metrics_user;
  GRANT USAGE, SELECT ON raw.raw_transactions_id_seq TO metrics_user;


-- ============================================================================
-- Teller (Financial Data)
-- Must create accounts first — transactions and balances FK to it
-- ============================================================================

CREATE TABLE IF NOT EXISTS raw.raw_teller_accounts (
    id SERIAL PRIMARY KEY,
    teller_account_id VARCHAR(255) NOT NULL UNIQUE,
    enrollment_id VARCHAR(255),
    institution_name VARCHAR(255),
    institution_id VARCHAR(255),
    account_name VARCHAR(255),
    account_type VARCHAR(50),
    account_subtype VARCHAR(50),
    account_status VARCHAR(50),
    currency VARCHAR(10),
    last_four VARCHAR(10),
    inserted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE raw.raw_teller_accounts IS 'Bank accounts connected via Teller API';

CREATE TABLE IF NOT EXISTS raw.raw_teller_transactions (
    id SERIAL PRIMARY KEY,
    teller_transaction_id VARCHAR(255) NOT NULL UNIQUE,
    teller_account_id VARCHAR(255) NOT NULL REFERENCES raw.raw_teller_accounts(teller_account_id) ON DELETE CASCADE,
    transaction_date DATE NOT NULL,
    description VARCHAR(500),
    amount NUMERIC(12, 2) NOT NULL,
    status VARCHAR(50),
    type VARCHAR(50),
    category VARCHAR(100),
    merchant_name VARCHAR(255),
    merchant_category VARCHAR(100),
    running_balance NUMERIC(12, 2),
    inserted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_teller_transactions_account ON raw.raw_teller_transactions(teller_account_id);
CREATE INDEX IF NOT EXISTS idx_teller_transactions_date ON raw.raw_teller_transactions(transaction_date DESC);

COMMENT ON TABLE raw.raw_teller_transactions IS 'Financial transactions from Teller API';

CREATE TABLE IF NOT EXISTS raw.raw_teller_balances (
    id SERIAL PRIMARY KEY,
    teller_account_id VARCHAR(255) NOT NULL REFERENCES raw.raw_teller_accounts(teller_account_id) ON DELETE CASCADE,
    ledger_balance NUMERIC(12, 2),
    available_balance NUMERIC(12, 2),
    recorded_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    inserted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_teller_balances_account ON raw.raw_teller_balances(teller_account_id);
CREATE INDEX IF NOT EXISTS idx_teller_balances_recorded ON raw.raw_teller_balances(recorded_at DESC);

COMMENT ON TABLE raw.raw_teller_balances IS 'Daily account balance snapshots from Teller';

GRANT SELECT, INSERT, UPDATE, DELETE ON raw.raw_teller_accounts TO metrics_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON raw.raw_teller_transactions TO metrics_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON raw.raw_teller_balances TO metrics_user;
GRANT USAGE, SELECT ON raw.raw_teller_accounts_id_seq TO metrics_user;
GRANT USAGE, SELECT ON raw.raw_teller_transactions_id_seq TO metrics_user;
GRANT USAGE, SELECT ON raw.raw_teller_balances_id_seq TO metrics_user;

-- ============================================================================
-- SimpleFIN Bridge bank transactions (simplefin_extractor job)
-- ============================================================================

CREATE TABLE IF NOT EXISTS raw.raw_simplefin_transactions (
    account_id        TEXT           NOT NULL,
    transaction_id    TEXT           NOT NULL,
    institution_name  TEXT,
    account_name      TEXT,
    posted_at         TIMESTAMPTZ    NOT NULL,
    transacted_at     TIMESTAMPTZ,
    amount            NUMERIC(14, 2) NOT NULL,
    description       TEXT,
    payload           JSONB          NOT NULL,
    inserted_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    -- SimpleFIN transaction ids are only unique within an account
    PRIMARY KEY (account_id, transaction_id)
);

CREATE INDEX IF NOT EXISTS idx_simplefin_transactions_posted ON raw.raw_simplefin_transactions(posted_at DESC);

COMMENT ON TABLE raw.raw_simplefin_transactions IS 'Posted bank transactions from SimpleFIN Bridge';

CREATE TABLE IF NOT EXISTS raw.raw_simplefin_balances (
    account_id         TEXT           NOT NULL,
    conn_id            TEXT,
    institution_name   TEXT,
    account_name       TEXT,
    currency           TEXT,
    balance            NUMERIC(14, 2) NOT NULL,
    -- NULL when SimpleFIN omits it, which means it equals balance
    available_balance  NUMERIC(14, 2),
    balance_date       TIMESTAMPTZ    NOT NULL,
    payload            JSONB          NOT NULL,
    inserted_at        TIMESTAMPTZ    NOT NULL DEFAULT now(),
    -- balance_date only moves when the bank refreshes, so unchanged days dedupe
    PRIMARY KEY (account_id, balance_date)
);

COMMENT ON TABLE raw.raw_simplefin_balances IS 'Account balance snapshots from SimpleFIN Bridge, one per bank refresh';

-- Least-privilege writer for the extractor. Password is set out of band and
-- stored outside the repo (see docs/finance/simplefin-extractor.md).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bank_writer') THEN
        CREATE ROLE bank_writer LOGIN;
    END IF;
END
$$;

GRANT CONNECT ON DATABASE home_metrics TO bank_writer;
GRANT USAGE ON SCHEMA raw TO bank_writer;
GRANT SELECT, INSERT ON raw.raw_simplefin_transactions TO bank_writer;
GRANT SELECT, INSERT ON raw.raw_simplefin_balances TO bank_writer;
