import assert from 'node:assert/strict';
import test from 'node:test';
import { resolveAuthenticatedRequestScope } from './customer_request_auth.js';

test('customer API uses customer actor without merchant scope', () => {
  assert.deepEqual(
    resolveAuthenticatedRequestScope({
      path: '/customer/session',
      resolvedMerchantId: 'firebase-uid-fallback',
      hasAdminAccess: false,
      supportsBodyMerchantScope: false,
    }),
    {
      actor: 'CUSTOMER',
      merchantId: '',
      hasRequiredScope: true,
    },
  );
});

test('customer core remains a merchant-scoped API', () => {
  assert.deepEqual(
    resolveAuthenticatedRequestScope({
      path: '/customer-core/identities',
      resolvedMerchantId: 'merchant-a',
      hasAdminAccess: false,
      supportsBodyMerchantScope: true,
    }),
    {
      actor: 'MERCHANT',
      merchantId: 'merchant-a',
      hasRequiredScope: true,
    },
  );
});

test('merchant API still rejects a missing scope', () => {
  assert.deepEqual(
    resolveAuthenticatedRequestScope({
      path: '/sync/push',
      resolvedMerchantId: null,
      hasAdminAccess: false,
      supportsBodyMerchantScope: false,
    }),
    {
      actor: 'MERCHANT',
      merchantId: '',
      hasRequiredScope: false,
    },
  );
});
