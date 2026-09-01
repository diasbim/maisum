import assert from 'node:assert/strict';
import test from 'node:test';

import {
  customerRedemptionCodeExpiresAt,
  customerRedemptionFulfillmentState,
  supportsCustomerRedemptionReissue,
} from './customer_redemption_fulfillment.js';

const ttl = 15 * 60 * 1000;

test('resolves pending, consumed, and expired redemption states', () => {
  assert.equal(
    customerRedemptionFulfillmentState(
      { redeemed_at: 1_000, fulfillment_status: 'PENDING' },
      1_001,
      ttl,
    ),
    'PENDING',
  );
  assert.equal(
    customerRedemptionFulfillmentState(
      { redeemed_at: 1_000, fulfillment_status: 'CONSUMED' },
      1_000 + ttl + 1,
      ttl,
    ),
    'CONSUMED',
  );
  assert.equal(
    customerRedemptionFulfillmentState(
      { redemption_code_expires_at: 2_000 },
      2_000,
      ttl,
    ),
    'EXPIRED',
  );
});

test('derives legacy expiration from the redemption timestamp', () => {
  assert.equal(
    customerRedemptionCodeExpiresAt({ redeemed_at: 5_000 }, ttl),
    5_000 + ttl,
  );
});

test('only customer-issued redemption codes support reissue', () => {
  assert.equal(
    supportsCustomerRedemptionReissue({
      redemption_code: 'r1_abcdefghijklmnopqrstuvwx',
    }),
    true,
  );
  assert.equal(supportsCustomerRedemptionReissue({}), false);
  assert.equal(
    supportsCustomerRedemptionReissue({ redemption_code: 'merchant-code' }),
    false,
  );
});
