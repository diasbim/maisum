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
    ('free', 1, 'engage_view_risk', false),
    ('free', 1, 'engage_manage_recovery', false),
    ('free', 1, 'engage_manage_visits', false),
    ('free', 1, 'engage_manage_surveys', false),

    ('starter', 1, 'whatsapp_automation', true),
    ('starter', 1, 'campaigns', true),
    ('starter', 1, 'analytics', true),
    ('starter', 1, 'multi_device', false),
    ('starter', 1, 'cloud_backup', false),
    ('starter', 1, 'engage_view_risk', false),
    ('starter', 1, 'engage_manage_recovery', false),
    ('starter', 1, 'engage_manage_visits', false),
    ('starter', 1, 'engage_manage_surveys', false),

    ('pro', 1, 'whatsapp_automation', true),
    ('pro', 1, 'campaigns', true),
    ('pro', 1, 'analytics', true),
    ('pro', 1, 'multi_device', false),
    ('pro', 1, 'cloud_backup', false),
    ('pro', 1, 'engage_view_risk', true),
    ('pro', 1, 'engage_manage_recovery', false),
    ('pro', 1, 'engage_manage_visits', false),
    ('pro', 1, 'engage_manage_surveys', false),

    ('business', 1, 'whatsapp_automation', true),
    ('business', 1, 'campaigns', true),
    ('business', 1, 'analytics', true),
    ('business', 1, 'multi_device', true),
    ('business', 1, 'cloud_backup', true),
    ('business', 1, 'engage_view_risk', true),
    ('business', 1, 'engage_manage_recovery', true),
    ('business', 1, 'engage_manage_visits', true),
    ('business', 1, 'engage_manage_surveys', true),

    ('growth', 1, 'whatsapp_automation', true),
    ('growth', 1, 'campaigns', true),
    ('growth', 1, 'analytics', true),
    ('growth', 1, 'multi_device', true),
    ('growth', 1, 'cloud_backup', true),
    ('growth', 1, 'engage_view_risk', true),
    ('growth', 1, 'engage_manage_recovery', true),
    ('growth', 1, 'engage_manage_visits', true),
    ('growth', 1, 'engage_manage_surveys', true)
  ) AS seed(plan_code, plan_version, feature_key, is_enabled)
ON CONFLICT (plan_code, plan_version, feature_key)
DO UPDATE SET
  is_enabled = EXCLUDED.is_enabled,
  limit_value = EXCLUDED.limit_value,
  unit = EXCLUDED.unit,
  updated_at = EXCLUDED.updated_at;
