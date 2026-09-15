BEGIN;

DROP INDEX IF EXISTS idx_sync_queue_merchant_idempotency_key;
DROP INDEX IF EXISTS idx_sync_queue_merchant_local_id;
DROP INDEX IF EXISTS idx_sales_merchant_referral_status;
DROP INDEX IF EXISTS idx_sales_merchant_affiliate_code;

ALTER TABLE IF EXISTS sync_queue
  DROP COLUMN IF EXISTS last_sync_error,
  DROP COLUMN IF EXISTS idempotency_key,
  DROP COLUMN IF EXISTS local_id;

ALTER TABLE IF EXISTS sales
  DROP COLUMN IF EXISTS referral_status,
  DROP COLUMN IF EXISTS affiliate_code_id,
  DROP COLUMN IF EXISTS referral_benefit_amount,
  DROP COLUMN IF EXISTS referral_benefit_value,
  DROP COLUMN IF EXISTS referral_benefit_type,
  DROP COLUMN IF EXISTS gross_amount;

DROP TABLE IF EXISTS affiliate_rate_limits;
DROP TABLE IF EXISTS affiliate_fraud_signals;
DROP TABLE IF EXISTS affiliate_events;
DROP TABLE IF EXISTS affiliate_rewards;
DROP TABLE IF EXISTS affiliate_attributions;
DROP TABLE IF EXISTS affiliate_code_lookup;
DROP TABLE IF EXISTS affiliate_codes;
DROP TABLE IF EXISTS affiliate_merchants;
DROP TABLE IF EXISTS affiliates;

COMMIT;
