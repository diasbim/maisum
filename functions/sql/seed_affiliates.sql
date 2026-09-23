BEGIN;

INSERT INTO merchants (id, name, phone, created_at, updated_at)
VALUES
  (
    'merchant-affiliates-dev',
    'MaisUm Afiliados Demo',
    '+258840000001',
    1757890800000,
    1757890800000
  ),
  (
    'merchant-affiliates-secondary',
    'MaisUm Afiliados Secundário',
    '+258840000002',
    1757890800000,
    1757890800000
  )
ON CONFLICT (id)
DO UPDATE SET
  name = EXCLUDED.name,
  phone = EXCLUDED.phone,
  updated_at = EXCLUDED.updated_at;

INSERT INTO affiliates (
  id,
  phone,
  normalized_phone,
  first_name,
  last_name,
  display_name,
  status,
  created_at,
  updated_at
)
VALUES
  (
    'affiliate-ana',
    '+258841111111',
    '258841111111',
    'Ana',
    'Silva',
    'Ana Silva',
    'ACTIVE',
    1757890800000,
    1757890800000
  ),
  (
    'affiliate-bruno',
    '+258842222222',
    '258842222222',
    'Bruno',
    'Machava',
    'Bruno Machava',
    'ACTIVE',
    1757890800000,
    1757890800000
  )
ON CONFLICT (id)
DO UPDATE SET
  phone = EXCLUDED.phone,
  normalized_phone = EXCLUDED.normalized_phone,
  first_name = EXCLUDED.first_name,
  last_name = EXCLUDED.last_name,
  display_name = EXCLUDED.display_name,
  status = EXCLUDED.status,
  updated_at = EXCLUDED.updated_at;

INSERT INTO affiliate_merchants (
  id,
  merchant_id,
  affiliate_id,
  status,
  linked_at,
  created_at,
  updated_at
)
VALUES
  (
    'merchant-affiliates-dev_affiliate-ana',
    'merchant-affiliates-dev',
    'affiliate-ana',
    'ACTIVE',
    1757890800000,
    1757890800000,
    1757890800000
  ),
  (
    'merchant-affiliates-dev_affiliate-bruno',
    'merchant-affiliates-dev',
    'affiliate-bruno',
    'ACTIVE',
    1757890800000,
    1757890800000,
    1757890800000
  ),
  (
    'merchant-affiliates-secondary_affiliate-ana',
    'merchant-affiliates-secondary',
    'affiliate-ana',
    'INACTIVE',
    1757890800000,
    1757890800000,
    1757890800000
  )
ON CONFLICT (id)
DO UPDATE SET
  status = EXCLUDED.status,
  linked_at = EXCLUDED.linked_at,
  updated_at = EXCLUDED.updated_at;

INSERT INTO affiliate_codes (
  id,
  merchant_id,
  affiliate_id,
  code,
  normalized_code,
  benefit_type,
  benefit_value,
  starts_at,
  expires_at,
  usage_limit,
  usage_count,
  first_visit_only,
  status,
  created_at,
  updated_at
)
VALUES
  (
    'code-ana-dev',
    'merchant-affiliates-dev',
    'affiliate-ana',
    'AFI-ANA-2345',
    'AFI-ANA-2345',
    'FIXED_AMOUNT',
    50,
    1757890800000,
    1760482800000,
    NULL,
    0,
    true,
    'ACTIVE',
    1757890800000,
    1757890800000
  ),
  (
    'code-bruno-dev',
    'merchant-affiliates-dev',
    'affiliate-bruno',
    'AFI-BRUNO-6789',
    'AFI-BRUNO-6789',
    'POINTS',
    25,
    1757890800000,
    1760482800000,
    100,
    0,
    true,
    'ACTIVE',
    1757890800000,
    1757890800000
  )
ON CONFLICT (id)
DO UPDATE SET
  code = EXCLUDED.code,
  normalized_code = EXCLUDED.normalized_code,
  benefit_type = EXCLUDED.benefit_type,
  benefit_value = EXCLUDED.benefit_value,
  starts_at = EXCLUDED.starts_at,
  expires_at = EXCLUDED.expires_at,
  usage_limit = EXCLUDED.usage_limit,
  usage_count = EXCLUDED.usage_count,
  first_visit_only = EXCLUDED.first_visit_only,
  status = EXCLUDED.status,
  updated_at = EXCLUDED.updated_at;

INSERT INTO affiliate_code_lookup (
  normalized_code,
  merchant_id,
  affiliate_id,
  affiliate_code_id,
  code,
  status,
  benefit_type,
  benefit_value,
  starts_at,
  expires_at,
  usage_limit,
  usage_count,
  first_visit_only,
  updated_at,
  payload
)
SELECT
  normalized_code,
  merchant_id,
  affiliate_id,
  id,
  code,
  status,
  benefit_type,
  benefit_value,
  starts_at,
  expires_at,
  usage_limit,
  usage_count,
  first_visit_only,
  updated_at,
  '{"source":"seed"}'::jsonb
FROM affiliate_codes
WHERE id IN ('code-ana-dev', 'code-bruno-dev')
ON CONFLICT (normalized_code)
DO UPDATE SET
  merchant_id = EXCLUDED.merchant_id,
  affiliate_id = EXCLUDED.affiliate_id,
  affiliate_code_id = EXCLUDED.affiliate_code_id,
  code = EXCLUDED.code,
  status = EXCLUDED.status,
  benefit_type = EXCLUDED.benefit_type,
  benefit_value = EXCLUDED.benefit_value,
  starts_at = EXCLUDED.starts_at,
  expires_at = EXCLUDED.expires_at,
  usage_limit = EXCLUDED.usage_limit,
  usage_count = EXCLUDED.usage_count,
  first_visit_only = EXCLUDED.first_visit_only,
  updated_at = EXCLUDED.updated_at,
  payload = EXCLUDED.payload;

-- Lifecycle rows deliberately remain empty. They require real customer and
-- sale parents when the legacy sync tables exist, and a seed must not invent
-- operational sales merely to demonstrate affiliate configuration.
INSERT INTO affiliate_events (
  id,
  merchant_id,
  affiliate_id,
  event_type,
  occurred_at,
  created_at,
  schema_version,
  payload
)
VALUES
  (
    'event-affiliate-ana-created',
    'merchant-affiliates-dev',
    'affiliate-ana',
    'AFFILIATE_CREATED',
    1757890800000,
    1757890800000,
    1,
    '{"source":"seed"}'::jsonb
  ),
  (
    'event-affiliate-bruno-created',
    'merchant-affiliates-dev',
    'affiliate-bruno',
    'AFFILIATE_CREATED',
    1757890800000,
    1757890800000,
    1,
    '{"source":"seed"}'::jsonb
  )
ON CONFLICT (id)
DO NOTHING;

INSERT INTO affiliate_rate_limits (
  id,
  merchant_id,
  bucket_key,
  window_started_at,
  request_count,
  updated_at,
  metadata
)
VALUES
  (
    'rl-merchant-affiliates-dev-validate',
    'merchant-affiliates-dev',
    'validate-code:2026-09-15T00',
    1757894400000,
    3,
    1757896200000,
    '{"window_minutes":60}'::jsonb
  )
ON CONFLICT (id)
DO UPDATE SET
  request_count = EXCLUDED.request_count,
  updated_at = EXCLUDED.updated_at,
  metadata = EXCLUDED.metadata;

COMMIT;
