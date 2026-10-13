BEGIN;

CREATE TABLE IF NOT EXISTS affiliates (
  id TEXT PRIMARY KEY,
  phone TEXT NOT NULL,
  normalized_phone TEXT NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT,
  display_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliates_normalized_phone
  ON affiliates(normalized_phone);
CREATE INDEX IF NOT EXISTS idx_affiliates_status_updated
  ON affiliates(status, updated_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS affiliate_merchants (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  affiliate_id TEXT NOT NULL REFERENCES affiliates(id),
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'INACTIVE')),
  linked_at BIGINT NOT NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_merchants_scope
  ON affiliate_merchants(merchant_id, affiliate_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_merchants_merchant_status
  ON affiliate_merchants(merchant_id, status, updated_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS affiliate_codes (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  affiliate_id TEXT NOT NULL REFERENCES affiliates(id),
  code TEXT NOT NULL,
  normalized_code TEXT NOT NULL,
  benefit_type TEXT NOT NULL
    CHECK (benefit_type IN ('FIXED_AMOUNT', 'PERCENTAGE', 'POINTS')),
  benefit_value DOUBLE PRECISION NOT NULL,
  starts_at BIGINT,
  expires_at BIGINT,
  usage_limit INTEGER,
  usage_count INTEGER NOT NULL DEFAULT 0,
  first_visit_only BOOLEAN NOT NULL DEFAULT true,
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'DISABLED')),
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_codes_scope
  ON affiliate_codes(merchant_id, affiliate_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_codes_normalized
  ON affiliate_codes(normalized_code);
CREATE INDEX IF NOT EXISTS idx_affiliate_codes_merchant_status
  ON affiliate_codes(merchant_id, status, updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_affiliate_codes_merchant_affiliate
  ON affiliate_codes(merchant_id, affiliate_id, updated_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS affiliate_code_lookup (
  normalized_code TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  affiliate_id TEXT NOT NULL REFERENCES affiliates(id),
  affiliate_code_id TEXT NOT NULL REFERENCES affiliate_codes(id),
  code TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'DISABLED')),
  benefit_type TEXT NOT NULL
    CHECK (benefit_type IN ('FIXED_AMOUNT', 'PERCENTAGE', 'POINTS')),
  benefit_value DOUBLE PRECISION NOT NULL,
  starts_at BIGINT,
  expires_at BIGINT,
  usage_limit INTEGER,
  usage_count INTEGER NOT NULL DEFAULT 0,
  first_visit_only BOOLEAN NOT NULL DEFAULT true,
  updated_at BIGINT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_code_lookup_scope
  ON affiliate_code_lookup(merchant_id, affiliate_code_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_code_lookup_merchant_updated
  ON affiliate_code_lookup(merchant_id, updated_at DESC, normalized_code DESC);

CREATE TABLE IF NOT EXISTS affiliate_attributions (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  affiliate_id TEXT NOT NULL REFERENCES affiliates(id),
  affiliate_code_id TEXT NOT NULL REFERENCES affiliate_codes(id),
  customer_id TEXT NOT NULL,
  qualifying_sale_id TEXT,
  status TEXT NOT NULL DEFAULT 'CONFIRMED'
    CHECK (status IN ('CONFIRMED', 'REJECTED', 'CANCELLED')),
  rejection_code TEXT
    CHECK (
      rejection_code IS NULL OR rejection_code IN (
        'CODE_NOT_FOUND',
        'CODE_DISABLED',
        'CODE_NOT_STARTED',
        'CODE_EXPIRED',
        'CODE_USAGE_LIMIT_REACHED',
        'AFFILIATE_INACTIVE',
        'SELF_REFERRAL_NOT_ALLOWED',
        'CUSTOMER_NOT_ELIGIBLE',
        'CUSTOMER_ALREADY_REFERRED',
        'BENEFIT_INVALID'
      )
    ),
  attributed_at BIGINT NOT NULL,
  first_sale_at BIGINT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_attributions_non_rejected_customer
  ON affiliate_attributions(merchant_id, customer_id)
  WHERE status <> 'REJECTED';
CREATE INDEX IF NOT EXISTS idx_affiliate_attributions_merchant_affiliate
  ON affiliate_attributions(merchant_id, affiliate_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_affiliate_attributions_merchant_customer
  ON affiliate_attributions(merchant_id, customer_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS affiliate_rewards (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  affiliate_id TEXT NOT NULL REFERENCES affiliates(id),
  attribution_id TEXT NOT NULL REFERENCES affiliate_attributions(id),
  reward_type TEXT NOT NULL
    CHECK (reward_type IN ('FIRST_QUALIFYING_SALE', 'CUSTOMER_RETURN')),
  value_type TEXT NOT NULL
    CHECK (value_type IN ('POINTS', 'FIXED_AMOUNT')),
  reward_value DOUBLE PRECISION NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'APPROVED', 'PAID', 'CANCELLED')),
  approval_required BOOLEAN NOT NULL DEFAULT true,
  source_sale_id TEXT,
  approved_at BIGINT,
  approved_by_app_user_id TEXT,
  cancelled_at BIGINT,
  cancelled_by_app_user_id TEXT,
  cancellation_reason TEXT,
  paid_at BIGINT,
  paid_by_app_user_id TEXT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_rewards_attribution_type
  ON affiliate_rewards(merchant_id, attribution_id, reward_type);
CREATE INDEX IF NOT EXISTS idx_affiliate_rewards_merchant_status
  ON affiliate_rewards(merchant_id, status, updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_affiliate_rewards_merchant_affiliate
  ON affiliate_rewards(merchant_id, affiliate_id, reward_type, updated_at DESC);

CREATE TABLE IF NOT EXISTS affiliate_events (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  affiliate_id TEXT NOT NULL REFERENCES affiliates(id),
  event_type TEXT NOT NULL
    CHECK (
      event_type IN (
        'AFFILIATE_CREATED',
        'AFFILIATE_CODE_CREATED',
        'REFERRAL_CODE_VALIDATED',
        'REFERRAL_ATTRIBUTED',
        'REFERRAL_REJECTED',
        'AFFILIATE_REWARD_CREATED',
        'AFFILIATE_REWARD_APPROVED',
        'AFFILIATE_REWARD_CANCELLED',
        'REFERRED_CUSTOMER_RETURNED'
      )
    ),
  attribution_id TEXT REFERENCES affiliate_attributions(id),
  reward_id TEXT REFERENCES affiliate_rewards(id),
  sale_id TEXT,
  customer_id TEXT,
  occurred_at BIGINT NOT NULL,
  created_at BIGINT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_affiliate_events_merchant_occurred
  ON affiliate_events(merchant_id, occurred_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_affiliate_events_merchant_affiliate
  ON affiliate_events(merchant_id, affiliate_id, occurred_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_affiliate_events_merchant_type
  ON affiliate_events(merchant_id, event_type, occurred_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS affiliate_fraud_signals (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  affiliate_id TEXT REFERENCES affiliates(id),
  signal_type TEXT NOT NULL
    CHECK (
      signal_type IN (
        'OFFLINE_CODE_REJECTED',
        'VALIDATION_BURST',
        'SELF_REFERRAL_ATTEMPT',
        'DUPLICATE_ATTRIBUTION_ATTEMPT'
      )
    ),
  severity TEXT NOT NULL
    CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH')),
  attribution_id TEXT REFERENCES affiliate_attributions(id),
  reward_id TEXT REFERENCES affiliate_rewards(id),
  sale_id TEXT,
  customer_id TEXT,
  created_at BIGINT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_affiliate_fraud_signals_merchant_severity
  ON affiliate_fraud_signals(merchant_id, severity, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_affiliate_fraud_signals_merchant_affiliate
  ON affiliate_fraud_signals(merchant_id, affiliate_id, created_at DESC, id DESC);

-- Customers and sales belong to the legacy sync schema, which is not created
-- by this additive file. Add integrity constraints when those tables are
-- present without making a clean affiliate bootstrap depend on them.
DO $$
BEGIN
  IF to_regclass('public.customers') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'fk_affiliate_attributions_customer'
    ) THEN
      ALTER TABLE affiliate_attributions
        ADD CONSTRAINT fk_affiliate_attributions_customer
        FOREIGN KEY (customer_id) REFERENCES customers(id);
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'fk_affiliate_events_customer'
    ) THEN
      ALTER TABLE affiliate_events
        ADD CONSTRAINT fk_affiliate_events_customer
        FOREIGN KEY (customer_id) REFERENCES customers(id);
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'fk_affiliate_fraud_signals_customer'
    ) THEN
      ALTER TABLE affiliate_fraud_signals
        ADD CONSTRAINT fk_affiliate_fraud_signals_customer
        FOREIGN KEY (customer_id) REFERENCES customers(id);
    END IF;
  END IF;

  IF to_regclass('public.sales') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'fk_affiliate_attributions_sale'
    ) THEN
      ALTER TABLE affiliate_attributions
        ADD CONSTRAINT fk_affiliate_attributions_sale
        FOREIGN KEY (qualifying_sale_id) REFERENCES sales(id);
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'fk_affiliate_rewards_sale'
    ) THEN
      ALTER TABLE affiliate_rewards
        ADD CONSTRAINT fk_affiliate_rewards_sale
        FOREIGN KEY (source_sale_id) REFERENCES sales(id);
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'fk_affiliate_events_sale'
    ) THEN
      ALTER TABLE affiliate_events
        ADD CONSTRAINT fk_affiliate_events_sale
        FOREIGN KEY (sale_id) REFERENCES sales(id);
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'fk_affiliate_fraud_signals_sale'
    ) THEN
      ALTER TABLE affiliate_fraud_signals
        ADD CONSTRAINT fk_affiliate_fraud_signals_sale
        FOREIGN KEY (sale_id) REFERENCES sales(id);
    END IF;
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS affiliate_rate_limits (
  id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(id),
  bucket_key TEXT NOT NULL,
  window_started_at BIGINT NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0,
  updated_at BIGINT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_rate_limits_bucket
  ON affiliate_rate_limits(merchant_id, bucket_key);
CREATE INDEX IF NOT EXISTS idx_affiliate_rate_limits_window
  ON affiliate_rate_limits(merchant_id, window_started_at DESC, id DESC);

ALTER TABLE IF EXISTS sales
  ADD COLUMN IF NOT EXISTS gross_amount DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS referral_benefit_type TEXT,
  ADD COLUMN IF NOT EXISTS referral_benefit_value DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS referral_benefit_amount DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS affiliate_code_id TEXT,
  ADD COLUMN IF NOT EXISTS referral_status TEXT;

ALTER TABLE IF EXISTS sync_queue
  ADD COLUMN IF NOT EXISTS local_id TEXT,
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS last_sync_error TEXT;

DO $$
BEGIN
  IF to_regclass('public.sales') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sales_merchant_affiliate_code ON sales(merchant_id, affiliate_code_id, created_at DESC, id DESC)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sales_merchant_referral_status ON sales(merchant_id, referral_status, updated_at DESC, id DESC)';
  END IF;
  IF to_regclass('public.sync_queue') IS NOT NULL THEN
    EXECUTE $sql$UPDATE sync_queue SET local_id = COALESCE(NULLIF(local_id, ''), entity_id) WHERE local_id IS NULL OR local_id = ''$sql$;
    EXECUTE $sql$UPDATE sync_queue SET idempotency_key = COALESCE(NULLIF(idempotency_key, ''), id) WHERE idempotency_key IS NULL OR idempotency_key = ''$sql$;
    EXECUTE 'UPDATE sync_queue SET last_sync_error = last_error WHERE last_sync_error IS NULL AND last_error IS NOT NULL';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sync_queue_merchant_local_id ON sync_queue(merchant_id, entity_type, local_id)';
    EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_queue_merchant_idempotency_key ON sync_queue(merchant_id, idempotency_key) WHERE idempotency_key IS NOT NULL';
  END IF;
END
$$;

COMMIT;
