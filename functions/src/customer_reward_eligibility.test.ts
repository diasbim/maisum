import assert from 'node:assert/strict';
import test from 'node:test';

import { isCustomerRewardExpired } from './customer_reward_eligibility.js';

test('recognizes expired rewards in both supported timestamp fields', () => {
  assert.equal(isCustomerRewardExpired({ expires_at: 999 }, 1_000), true);
  assert.equal(isCustomerRewardExpired({ expiresAt: 1_000 }, 1_000), true);
});

test('keeps future and missing expiration values active', () => {
  assert.equal(isCustomerRewardExpired({ expires_at: 1_001 }, 1_000), false);
  assert.equal(isCustomerRewardExpired({}, 1_000), false);
  assert.equal(isCustomerRewardExpired({ expires_at: 0 }, 1_000), false);
});
