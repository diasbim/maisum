-- Seed plan features from the current Flutter plan catalog (version 1).

WITH ts AS (
  SELECT (EXTRACT(EPOCH FROM NOW()) * 1000)::bigint AS now_ms
)
INSERT INTO plan_features (
  plan_code,
  plan_version,
  feature_key,
  is_enabled,
  limit_value,
  unit,
  updated_at
)
SELECT plan_code, plan_version, feature_key, is_enabled, NULL, NULL, now_ms
FROM ts,
  (VALUES
    ('free', 1, 'whatsapp_automation', true),
    ('free', 1, 'campaigns', false),
    ('free', 1, 'analytics', false),
    ('free', 1, 'multi_device', false),
    ('free', 1, 'cloud_backup', false),

    ('starter', 1, 'whatsapp_automation', true),
    ('starter', 1, 'campaigns', true),
    ('starter', 1, 'analytics', true),
    ('starter', 1, 'multi_device', false),
    ('starter', 1, 'cloud_backup', false),

    ('growth', 1, 'whatsapp_automation', true),
    ('growth', 1, 'campaigns', true),
    ('growth', 1, 'analytics', true),
    ('growth', 1, 'multi_device', true),
    ('growth', 1, 'cloud_backup', true)
  ) AS seed(plan_code, plan_version, feature_key, is_enabled)
ON CONFLICT (plan_code, plan_version, feature_key)
DO UPDATE SET
  is_enabled = EXCLUDED.is_enabled,
  limit_value = EXCLUDED.limit_value,
  unit = EXCLUDED.unit,
  updated_at = EXCLUDED.updated_at;
