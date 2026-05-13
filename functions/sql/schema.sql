-- PostgreSQL schema for subscriptions, entitlements, usage aggregation, and remote config.
-- Timestamps are stored as epoch milliseconds (BIGINT) to match mobile sync payloads.

CREATE TABLE IF NOT EXISTS merchants (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL UNIQUE,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS app_users (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  phone TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'OWNER',
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  last_login_at BIGINT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_merchant_phone
  ON app_users(merchant_id, phone);

CREATE TABLE IF NOT EXISTS subscription_state (
  merchant_id TEXT PRIMARY KEY REFERENCES merchants(id),
  plan_code TEXT NOT NULL,
  plan_name TEXT NOT NULL,
  plan_version INTEGER NOT NULL DEFAULT 1,
  pricing_version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'TRIAL',
  trial_ends_at BIGINT,
  grace_ends_at BIGINT,
  period_start BIGINT,
  period_end BIGINT,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_subscription_state_updated
  ON subscription_state(updated_at);

CREATE TABLE IF NOT EXISTS plans (
  plan_code TEXT NOT NULL,
  version INTEGER NOT NULL,
  name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  PRIMARY KEY (plan_code, version)
);
CREATE INDEX IF NOT EXISTS idx_plans_active
  ON plans(plan_code, is_active, version);

CREATE TABLE IF NOT EXISTS plan_features (
  plan_code TEXT NOT NULL,
  plan_version INTEGER NOT NULL,
  feature_key TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  limit_value INTEGER,
  unit TEXT,
  updated_at BIGINT NOT NULL,
  PRIMARY KEY (plan_code, plan_version, feature_key)
);

CREATE TABLE IF NOT EXISTS plan_prices (
  plan_code TEXT NOT NULL,
  pricing_version INTEGER NOT NULL,
  currency TEXT NOT NULL,
  amount INTEGER NOT NULL,
  billing_period TEXT NOT NULL DEFAULT 'monthly',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  PRIMARY KEY (plan_code, pricing_version, currency)
);
CREATE INDEX IF NOT EXISTS idx_plan_prices_active
  ON plan_prices(plan_code, is_active, pricing_version);

CREATE TABLE IF NOT EXISTS entitlements (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  feature_key TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  limit_value INTEGER,
  unit TEXT,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_entitlements_merchant_feature
  ON entitlements(merchant_id, feature_key);

CREATE TABLE IF NOT EXISTS feature_flags (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  flag_key TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  payload JSONB,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_feature_flags_merchant_flag
  ON feature_flags(merchant_id, flag_key);

CREATE TABLE IF NOT EXISTS remote_config (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  config_key TEXT NOT NULL,
  payload JSONB,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_remote_config_merchant_key
  ON remote_config(merchant_id, config_key);

CREATE TABLE IF NOT EXISTS usage_events (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  metric_key TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  occurred_at BIGINT NOT NULL,
  source TEXT,
  metadata JSONB,
  created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_usage_events_metric_time
  ON usage_events(merchant_id, metric_key, occurred_at);

CREATE TABLE IF NOT EXISTS usage_balances (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  metric_key TEXT NOT NULL,
  window_start BIGINT NOT NULL,
  window_end BIGINT NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  limit_value INTEGER,
  soft_limit BOOLEAN NOT NULL DEFAULT true,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_usage_balances_window
  ON usage_balances(merchant_id, metric_key, window_start, window_end);
