CREATE TABLE IF NOT EXISTS config_items (
  id UUID PRIMARY KEY,
  config_key TEXT NOT NULL UNIQUE,
  config_type TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  default_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS config_segments (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  conditions JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS config_rules (
  id UUID PRIMARY KEY,
  config_key TEXT NOT NULL,
  segment_id UUID REFERENCES config_segments(id),
  priority INTEGER NOT NULL DEFAULT 100,
  rollout_pct INTEGER NOT NULL DEFAULT 100,
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  payload_override JSONB,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS experiment_assignments (
  id UUID PRIMARY KEY,
  config_key TEXT NOT NULL,
  merchant_id TEXT NOT NULL,
  variant TEXT NOT NULL,
  assigned_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_config_rules_key
  ON config_rules(config_key, priority);
CREATE INDEX IF NOT EXISTS idx_experiment_assignments
  ON experiment_assignments(config_key, merchant_id);
