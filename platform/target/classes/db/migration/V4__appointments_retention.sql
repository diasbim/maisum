CREATE TABLE IF NOT EXISTS appointments (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  scheduled_date TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL,
  source TEXT NOT NULL,
  reminder_sent BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_appointments_merchant_date
  ON appointments(merchant_id, scheduled_date);
CREATE INDEX IF NOT EXISTS idx_appointments_merchant_status_date
  ON appointments(merchant_id, status, scheduled_date);

CREATE TABLE IF NOT EXISTS retention_metrics (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  last_visit_at TIMESTAMPTZ,
  days_inactive INTEGER NOT NULL DEFAULT 0,
  risk_level TEXT NOT NULL,
  total_visits INTEGER NOT NULL DEFAULT 0,
  average_visit_interval INTEGER NOT NULL DEFAULT 0,
  total_spent NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
  recovered BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL,
  synced BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS idx_retention_metrics_merchant_risk
  ON retention_metrics(merchant_id, risk_level);
CREATE INDEX IF NOT EXISTS idx_retention_metrics_merchant_last_visit
  ON retention_metrics(merchant_id, last_visit_at);
