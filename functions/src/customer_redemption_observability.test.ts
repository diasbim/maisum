import assert from 'node:assert/strict';
import test from 'node:test';
import {
  customerRedemptionLogRecord,
} from './customer_redemption_observability.js';

test('redemption telemetry contains only approved operational fields', () => {
  const record = customerRedemptionLogRecord({
    event: 'consumed',
    merchantId: 'merchant-1',
    redemptionId: 'redemption-1',
    fulfillmentStatus: 'CONSUMED',
    surface: 'merchant',
  });

  assert.deepEqual(record, {
    event: 'customer_redemption_lifecycle',
    lifecycle_event: 'consumed',
    surface: 'merchant',
    merchant_id: 'merchant-1',
    redemption_id: 'redemption-1',
    fulfillment_status: 'CONSUMED',
  });
  assert.equal(JSON.stringify(record).includes('redemption_code'), false);
  assert.equal(JSON.stringify(record).includes('phone'), false);
  assert.equal(JSON.stringify(record).includes('name'), false);
});
