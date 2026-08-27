import assert from 'node:assert/strict';
import test from 'node:test';
import {
  isCustomerUidAllowed,
  resolveCustomerFeatureFlags,
} from './customer_feature_flags.js';

test('customer feature flags default to disabled', () => {
  assert.deepEqual(resolveCustomerFeatureFlags({}), {
    customerAppEnabled: false,
    customerRedemptionEnabled: false,
    customerQrEnabled: false,
    customerPushEnabled: false,
    customerDeepLinksEnabled: false,
  });
});

test('customer feature flags only enable literal true values', () => {
  const flags = resolveCustomerFeatureFlags({
    CUSTOMER_APP_ENABLED: 'true',
    CUSTOMER_REDEMPTION_ENABLED: 'TRUE',
    CUSTOMER_QR_ENABLED: 'true',
    CUSTOMER_PUSH_ENABLED: 'false',
    CUSTOMER_DEEP_LINKS_ENABLED: '1',
  });

  assert.equal(flags.customerAppEnabled, true);
  assert.equal(flags.customerRedemptionEnabled, false);
  assert.equal(flags.customerQrEnabled, true);
  assert.equal(flags.customerPushEnabled, false);
  assert.equal(flags.customerDeepLinksEnabled, false);
});

test('customer rollout allow-list is optional and matches exact Firebase UIDs', () => {
  assert.equal(isCustomerUidAllowed({}, 'uid-a'), true);
  const environment = { CUSTOMER_APP_ALLOWED_UIDS: 'uid-a, uid-b' };
  assert.equal(isCustomerUidAllowed(environment, 'uid-a'), true);
  assert.equal(isCustomerUidAllowed(environment, 'uid-b'), true);
  assert.equal(isCustomerUidAllowed(environment, 'uid-c'), false);
  assert.equal(isCustomerUidAllowed(environment, 'uid'), false);
});
