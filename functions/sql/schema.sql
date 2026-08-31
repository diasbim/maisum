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
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  invited_at BIGINT,
  accepted_at BIGINT,
  invited_by_app_user_id TEXT,
  deactivated_at BIGINT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  last_login_at BIGINT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_merchant_phone
  ON app_users(merchant_id, phone);
CREATE INDEX IF NOT EXISTS idx_app_users_merchant_status
  ON app_users(merchant_id, status);

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

CREATE TABLE IF NOT EXISTS admin_audit_events (
  id TEXT PRIMARY KEY,
  actor_app_user_id TEXT,
  actor_firebase_uid TEXT,
  actor_role TEXT,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT,
  merchant_id TEXT,
  details JSONB,
  created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_events_created
  ON admin_audit_events(created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_events_target
  ON admin_audit_events(target_type, target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_events_merchant
  ON admin_audit_events(merchant_id, created_at DESC);

-- Derived analytics copy of immutable Firestore retention events.
-- It intentionally has no merchant foreign key so projection retries do not
-- depend on merchant synchronization order.
CREATE TABLE IF NOT EXISTS retention_domain_events (
  event_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  merchant_id TEXT NOT NULL,
  canonical_customer_id TEXT NOT NULL,
  business_customer_id TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  correlation_id TEXT NOT NULL,
  causation_id TEXT,
  occurred_at BIGINT NOT NULL,
  recorded_at BIGINT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  projected_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_retention_domain_events_merchant_occurred
  ON retention_domain_events(merchant_id, occurred_at DESC, event_id DESC);
CREATE INDEX IF NOT EXISTS idx_retention_domain_events_customer_occurred
  ON retention_domain_events(
    merchant_id,
    business_customer_id,
    occurred_at DESC,
    event_id DESC
  );
CREATE INDEX IF NOT EXISTS idx_retention_domain_events_type_occurred
  ON retention_domain_events(merchant_id, event_type, occurred_at DESC);

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

ALTER TABLE IF EXISTS customers
  ADD COLUMN IF NOT EXISTS archived_at BIGINT,
  ADD COLUMN IF NOT EXISTS archived_by_app_user_id TEXT;

ALTER TABLE IF EXISTS sales
  ADD COLUMN IF NOT EXISTS updated_at BIGINT,
  ADD COLUMN IF NOT EXISTS cancellation_status TEXT NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN IF NOT EXISTS cancelled_at BIGINT,
  ADD COLUMN IF NOT EXISTS cancelled_by_app_user_id TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT,
  ADD COLUMN IF NOT EXISTS replacement_sale_id TEXT;

DO $$
BEGIN
  IF to_regclass('public.sales') IS NOT NULL THEN
    EXECUTE 'UPDATE sales SET updated_at = COALESCE(updated_at, created_at) WHERE updated_at IS NULL';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sales_merchant_updated ON sales(merchant_id, updated_at, id)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sales_merchant_cancellation_status ON sales(merchant_id, cancellation_status, updated_at)';
  END IF;
  IF to_regclass('public.customers') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_customers_merchant_archived_at ON customers(merchant_id, archived_at, updated_at, id)';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS sync_tombstones (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  deleted_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_tombstones_entity
  ON sync_tombstones(merchant_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_sync_tombstones_deleted
  ON sync_tombstones(merchant_id, deleted_at, id);
CREATE TABLE IF NOT EXISTS merchant_items (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  default_price DOUBLE PRECISION,
  is_active BOOLEAN NOT NULL DEFAULT true,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_merchant_items_scope_type
  ON merchant_items(merchant_id, type, is_active, display_order);
CREATE INDEX IF NOT EXISTS idx_merchant_items_updated
  ON merchant_items(merchant_id, updated_at, id);

CREATE TABLE IF NOT EXISTS sale_items (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  sale_id TEXT NOT NULL,
  merchant_item_id TEXT NOT NULL REFERENCES merchant_items(id),
  name_snapshot TEXT NOT NULL,
  type_snapshot TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  unit_price DOUBLE PRECISION,
  subtotal DOUBLE PRECISION,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id
  ON sale_items(sale_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sale_items_updated
  ON sale_items(merchant_id, updated_at, id);

CREATE TABLE IF NOT EXISTS appointments (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  customer_id TEXT NOT NULL,
  scheduled_date BIGINT NOT NULL,
  status TEXT NOT NULL,
  source TEXT NOT NULL,
  reminder_sent BOOLEAN NOT NULL DEFAULT false,
  merchant_item_id TEXT,
  staff_app_user_id TEXT,
  duration_minutes INTEGER,
  notes TEXT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
);
ALTER TABLE appointments
  ADD COLUMN IF NOT EXISTS merchant_item_id TEXT,
  ADD COLUMN IF NOT EXISTS staff_app_user_id TEXT,
  ADD COLUMN IF NOT EXISTS duration_minutes INTEGER,
  ADD COLUMN IF NOT EXISTS notes TEXT;
CREATE INDEX IF NOT EXISTS idx_appointments_merchant_date
  ON appointments(merchant_id, scheduled_date);
CREATE INDEX IF NOT EXISTS idx_appointments_merchant_item
  ON appointments(merchant_id, merchant_item_id);
CREATE INDEX IF NOT EXISTS idx_appointments_staff_date
  ON appointments(merchant_id, staff_app_user_id, scheduled_date);

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
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT,
  open_slot SMALLINT GENERATED ALWAYS AS (
    CASE WHEN LOWER(status) = 'open' THEN 1 ELSE NULL END
  ) STORED
);
ALTER TABLE recovery_tasks
  ADD COLUMN IF NOT EXISTS open_slot SMALLINT GENERATED ALWAYS AS (
    CASE WHEN LOWER(status) = 'open' THEN 1 ELSE NULL END
  ) STORED;
WITH ranked_open_tasks AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY merchant_id, customer_id
           ORDER BY updated_at DESC, id DESC
         ) AS open_rank
  FROM recovery_tasks
  WHERE LOWER(status) = 'open'
)
UPDATE recovery_tasks AS task
SET status = 'superseded'
FROM ranked_open_tasks AS ranked
WHERE task.id = ranked.id AND ranked.open_rank > 1;
CREATE UNIQUE INDEX IF NOT EXISTS idx_recovery_tasks_one_open_customer
  ON recovery_tasks(merchant_id, customer_id, open_slot);
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
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
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
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
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
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
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
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
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
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
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
  updated_at BIGINT NOT NULL,
  created_by_app_user_id TEXT,
  updated_by_app_user_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_survey_response_answers_response
  ON survey_response_answers(response_id, question_id);
