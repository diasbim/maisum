CREATE TABLE IF NOT EXISTS merchants (
  id TEXT PRIMARY KEY,
  name TEXT,
  phone TEXT,
  streak_days INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  total_points INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_customers_merchant_phone
  ON customers(merchant_id, phone);
CREATE INDEX IF NOT EXISTS idx_customers_merchant_updated
  ON customers(merchant_id, updated_at);

CREATE TABLE IF NOT EXISTS sales (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  amount NUMERIC(12, 2) NOT NULL,
  points INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  device_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_sales_merchant_created
  ON sales(merchant_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sales_customer
  ON sales(customer_id);

CREATE TABLE IF NOT EXISTS rewards (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL,
  name TEXT NOT NULL,
  points_required INTEGER NOT NULL,
  description TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rewards_merchant_updated
  ON rewards(merchant_id, updated_at);

CREATE TABLE IF NOT EXISTS redemptions (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  reward_id TEXT NOT NULL,
  points_spent INTEGER NOT NULL,
  redeemed_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_redemptions_merchant_redeemed
  ON redemptions(merchant_id, redeemed_at);

CREATE TABLE IF NOT EXISTS merchant_streaks (
  merchant_id TEXT PRIMARY KEY,
  streak_days INTEGER NOT NULL DEFAULT 0,
  last_active_day DATE,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS notification_queue (
  id UUID PRIMARY KEY,
  merchant_id TEXT NOT NULL,
  channel TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  payload JSONB,
  scheduled_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  retry_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notification_queue_status
  ON notification_queue(status, scheduled_at);
