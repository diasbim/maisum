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

CREATE TABLE IF NOT EXISTS customer_risk_scores (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  customer_id TEXT NOT NULL,
  days_since_visit INTEGER NOT NULL DEFAULT 0,
  risk_level TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_risk_scores_merchant_customer
  ON customer_risk_scores(merchant_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_risk_scores_risk_priority
  ON customer_risk_scores(merchant_id, risk_level, priority);

CREATE TABLE IF NOT EXISTS recovery_tasks (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  customer_id TEXT NOT NULL,
  priority TEXT NOT NULL,
  status TEXT NOT NULL,
  due_at BIGINT,
  notes TEXT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_recovery_tasks_merchant_status_due
  ON recovery_tasks(merchant_id, status, due_at);
CREATE INDEX IF NOT EXISTS idx_recovery_tasks_merchant_priority
  ON recovery_tasks(merchant_id, priority, updated_at);

CREATE TABLE IF NOT EXISTS recovery_actions (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  customer_id TEXT NOT NULL,
  task_id TEXT REFERENCES recovery_tasks(id),
  action_type TEXT NOT NULL,
  payload JSONB,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_recovery_actions_merchant_customer
  ON recovery_actions(merchant_id, customer_id, created_at);
CREATE INDEX IF NOT EXISTS idx_recovery_actions_merchant_task
  ON recovery_actions(merchant_id, task_id);

CREATE TABLE IF NOT EXISTS visit_reports (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  task_id TEXT REFERENCES recovery_tasks(id),
  customer_id TEXT NOT NULL,
  result TEXT NOT NULL,
  notes TEXT,
  visited_at BIGINT NOT NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_visit_reports_merchant_visited_at
  ON visit_reports(merchant_id, visited_at);
CREATE INDEX IF NOT EXISTS idx_visit_reports_merchant_result
  ON visit_reports(merchant_id, result, visited_at);

CREATE TABLE IF NOT EXISTS surveys (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  title TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_surveys_merchant_active
  ON surveys(merchant_id, is_active, updated_at);

CREATE TABLE IF NOT EXISTS survey_questions (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  survey_id TEXT NOT NULL REFERENCES surveys(id),
  question_text TEXT NOT NULL,
  question_type TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_required BOOLEAN NOT NULL DEFAULT false,
  options_payload JSONB,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_survey_questions_survey_order
  ON survey_questions(survey_id, sort_order);

CREATE TABLE IF NOT EXISTS survey_responses (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  survey_id TEXT NOT NULL REFERENCES surveys(id),
  customer_id TEXT,
  submitted_at BIGINT NOT NULL,
  channel TEXT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_survey_responses_merchant_survey
  ON survey_responses(merchant_id, survey_id, submitted_at);

CREATE TABLE IF NOT EXISTS survey_response_answers (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  response_id TEXT NOT NULL REFERENCES survey_responses(id),
  question_id TEXT NOT NULL REFERENCES survey_questions(id),
  answer_text TEXT,
  answer_numeric DOUBLE PRECISION,
  answer_bool BOOLEAN,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_survey_response_answers_response
  ON survey_response_answers(response_id, question_id);
