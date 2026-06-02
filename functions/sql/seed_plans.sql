-- Seed plan catalog and pricing (version 1).
-- amount is an integer in MZN for monthly billing; adjust to match live pricing.

WITH ts AS (
  SELECT (EXTRACT(EPOCH FROM NOW()) * 1000)::bigint AS now_ms
)
INSERT INTO plans (
  plan_code,
  version,
  name,
  is_active,
  created_at,
  updated_at
)
SELECT plan_code, version, name, true, now_ms, now_ms
FROM ts,
  (VALUES
    ('free', 1, 'Free'),
    ('starter', 1, 'Starter'),
    ('pro', 1, 'Pro'),
    ('business', 1, 'Business'),
    ('growth', 1, 'Growth')
  ) AS seed(plan_code, version, name)
ON CONFLICT (plan_code, version)
DO UPDATE SET
  name = EXCLUDED.name,
  is_active = EXCLUDED.is_active,
  updated_at = EXCLUDED.updated_at;

WITH ts AS (
  SELECT (EXTRACT(EPOCH FROM NOW()) * 1000)::bigint AS now_ms
)
INSERT INTO plan_prices (
  plan_code,
  pricing_version,
  currency,
  amount,
  billing_period,
  is_active,
  created_at,
  updated_at
)
SELECT plan_code, pricing_version, currency, amount, 'monthly', true, now_ms, now_ms
FROM ts,
  (VALUES
    ('free', 1, 'MZN', 0),
    ('starter', 1, 'MZN', 2000),
    ('pro', 1, 'MZN', 3500),
    ('business', 1, 'MZN', 5000),
    ('growth', 1, 'MZN', 5000)
  ) AS seed(plan_code, pricing_version, currency, amount)
ON CONFLICT (plan_code, pricing_version, currency)
DO UPDATE SET
  amount = EXCLUDED.amount,
  billing_period = EXCLUDED.billing_period,
  is_active = EXCLUDED.is_active,
  updated_at = EXCLUDED.updated_at;
