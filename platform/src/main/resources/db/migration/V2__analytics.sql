CREATE TABLE IF NOT EXISTS analytics_events (
  id UUID PRIMARY KEY,
  merchant_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL,
  source TEXT,
  device_id TEXT,
  app_version TEXT,
  properties JSONB
);
CREATE INDEX IF NOT EXISTS idx_analytics_events_type_time
  ON analytics_events(event_type, occurred_at);
CREATE INDEX IF NOT EXISTS idx_analytics_events_merchant_time
  ON analytics_events(merchant_id, occurred_at);

CREATE TABLE IF NOT EXISTS merchant_daily_kpis (
  merchant_id TEXT NOT NULL,
  day DATE NOT NULL,
  sales_count INTEGER NOT NULL DEFAULT 0,
  repeat_customers INTEGER NOT NULL DEFAULT 0,
  whatsapp_usage INTEGER NOT NULL DEFAULT 0,
  feature_adoption JSONB,
  paid_conversion BOOLEAN,
  churn_risk_score NUMERIC(5,2),
  retention_cohort INTEGER,
  health_score NUMERIC(5,2),
  updated_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (merchant_id, day)
);
